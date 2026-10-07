using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;

namespace Kornucopia.Core;

public static class Columns
{
    public static readonly string[] All = ["backlog", "doing", "review", "done"];
    public static string Color(string column) => column switch
    { "backlog" => "yellow", "doing" => "blue", "review" => "purple", "done" => "green", _ => throw new ArgumentException("Invalid column.") };
}

// Numeric dates retain Swift Codable's epoch (2001-01-01 UTC).
public sealed record Card
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Title { get; init; } = "";
    public string Notes { get; init; } = "";
    public string Column { get; init; } = "backlog";
    public string Color { get; init; } = "yellow";
    public double CreatedAt { get; init; } = BoardStore.Now;
    public double UpdatedAt { get; init; } = BoardStore.Now;
}

public sealed record BoardSnapshot
{
    public int SchemaVersion { get; init; } = 1;
    public IReadOnlyList<Card> Cards { get; init; } = [];
    // Empty default titles are localized in the UI, never in the stored data.
    public string BoardTitle { get; init; } = "";
    public int WipLimit { get; init; } = 2;
}

public static class BoardBudget
{
    public const int FileBytes = 16 * 1024 * 1024;
    public const int CardCount = 10_000;
    public const int BoardTitleBytes = 1024;
    public const int CardTitleBytes = 4096;
    public const int CardNotesBytes = 256 * 1024;
    public const int TextBytes = 8 * 1024 * 1024;
    public const int JsonDepth = 32;
    public const int JsonTokens = 250_000;
}

public sealed class BoardStore
{
    static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, MaxDepth = BoardBudget.JsonDepth };
    static readonly UTF8Encoding StrictUtf8 = new(false, true);
    static readonly DateTimeOffset Epoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
    public static double Now => (DateTimeOffset.UtcNow - Epoch).TotalSeconds;
    public string DirectoryPath { get; }
    public string DocumentPath => Path.Combine(DirectoryPath, "board.json");
    public string BackupPath => Path.Combine(DirectoryPath, "board.backup.json");
    public BoardSnapshot Snapshot { get; private set; } = new();
    public string? SaveError { get; private set; }
    public string? RecoveryKey { get; private set; }
    public string? SaveErrorKey { get; private set; }
    public string? RecoveryErrorKey { get; private set; }
    public string? StorageErrorKey { get; private set; }
    public bool CanUndo => undo.Count > 0;
    public bool CanRedo => redo.Count > 0;
    public int DoingCount => Snapshot.Cards.Count(c => c.Column == "doing");
    public event Action? Changed;
    public event Action? WipBlocked;
    public event Action<string>? StorageBlocked;
    readonly List<BoardSnapshot> undo = [];
    readonly List<BoardSnapshot> redo = [];
    string? primaryFingerprint;
    string? backupFingerprint;
    readonly RootGuard rootGuard;
    Guid? lastEditId;
    long lastEditTick;

    public BoardStore(string? directory = null)
    {
        DirectoryPath = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Kornucopia")));
        rootGuard = new RootGuard(DirectoryPath);
        Load();
    }
    public Card? Find(Guid id) => Snapshot.Cards.FirstOrDefault(c => c.Id == id);
    public IEnumerable<Card> Cards(string column, string query = "")
    {
        query = query.Trim();
        return Snapshot.Cards.Where(c => c.Column == column && (query.Length == 0 || Contains(c.Title, query) || Contains(c.Notes, query)));
    }
    static bool Contains(string source, string search) => CultureInfo.InvariantCulture.CompareInfo.IndexOf(source, search, CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace) >= 0;
    bool Permits(string column, string? current = null)
    {
        if (!Columns.All.Contains(column)) return false;
        if (column == "doing" && current != "doing" && DoingCount >= Snapshot.WipLimit) { WipBlocked?.Invoke(); return false; }
        return true;
    }
    public Guid? Create(string column = "backlog")
    {
        if (!Permits(column)) return null;
        var card = new Card { Column = column, Color = Columns.Color(column) };
        return Commit(Snapshot with { Cards = Array.AsReadOnly(Snapshot.Cards.Append(card).ToArray()) }) ? card.Id : null;
    }
    public bool Update(Guid id, string? title = null, string? notes = null, string? column = null)
    {
        var current = Find(id);
        if (current is null || !Permits(column ?? current.Column, current.Column)) return false;
        var destination = column ?? current.Column;
        var next = current with { Title = title ?? current.Title, Notes = notes ?? current.Notes, Column = destination, Color = Columns.Color(destination) };
        if (next == current) return true;
        next = next with { UpdatedAt = Now };
        return Commit(Snapshot with { Cards = Array.AsReadOnly(Snapshot.Cards.Select(c => c.Id == id ? next : c).ToArray()) }, column is null ? id : null);
    }
    public bool Move(Guid id, string destination, Guid? before = null)
    {
        var card = Find(id);
        if (card is null || !Permits(destination, card.Column)) return false;
        if (before == id) return destination == card.Column;
        if (before is Guid target && Find(target)?.Column != destination) return false;
        var cards = Snapshot.Cards.Where(c => c.Id != id).ToList();
        var index = before is Guid beforeId ? cards.FindIndex(c => c.Id == beforeId) : cards.FindLastIndex(c => c.Column == destination) + 1;
        if (before is null && index == 0) index = cards.Count;
        cards.Insert(index, card with { Column = destination, Color = Columns.Color(destination) });
        if (cards.SequenceEqual(Snapshot.Cards)) return true;
        cards[index] = cards[index] with { UpdatedAt = Now };
        return Commit(Snapshot with { Cards = cards.AsReadOnly() });
    }
    public bool Delete(Guid id)
    {
        if (Find(id) is null) return false;
        return Commit(Snapshot with { Cards = Array.AsReadOnly(Snapshot.Cards.Where(c => c.Id != id).ToArray()) });
    }
    public bool SetTitle(string title)
    {
        try { TextSize(title, BoardBudget.BoardTitleBytes); }
        catch (StorageException e) { StorageErrorKey = e.Key; StorageBlocked?.Invoke(e.Key); return false; }
        title = title.Trim();
        return title == Snapshot.BoardTitle || Commit(Snapshot with { BoardTitle = title });
    }
    public bool SetWip(int limit)
    {
        if (limit < 1 || limit < DoingCount) return false;
        return limit == Snapshot.WipLimit || Commit(Snapshot with { WipLimit = limit });
    }
    public bool Undo() => Restore(undo, redo);
    public bool Redo() => Restore(redo, undo);
    bool Restore(List<BoardSnapshot> source, List<BoardSnapshot> target)
    {
        lastEditId = null;
        if (source.Count == 0) return false;
        if (!TrySerialize(source[^1], out var bytes, true)) return false;
        target.Add(Snapshot); Trim(target);
        Snapshot = source[^1]; source.RemoveAt(source.Count - 1);
        Save(bytes!); Changed?.Invoke(); return true;
    }
    bool Commit(BoardSnapshot next, Guid? editId = null)
    {
        if (!TrySerialize(next, out var bytes, true)) return false;
        var tick = Stopwatch.GetTimestamp();
        if (editId is null || editId != lastEditId || Stopwatch.GetElapsedTime(lastEditTick, tick).TotalSeconds > .7 || redo.Count != 0) { undo.Add(Snapshot); Trim(undo); }
        redo.Clear(); lastEditId = editId; lastEditTick = tick; Snapshot = next;
        Save(bytes!); Changed?.Invoke(); return true;
    }
    static void Trim(List<BoardSnapshot> list) { if (list.Count > 100) list.RemoveRange(0, list.Count - 100); }
    public bool Flush()
    {
        if (!TrySerialize(Snapshot, out var bytes, false)) return false;
        return Save(bytes!);
    }
    bool TrySerialize(BoardSnapshot snapshot, out byte[]? bytes, bool notify)
    {
        bytes = null;
        try
        {
            Validate(snapshot);
            using var output = new BoundedOutput();
            JsonSerializer.Serialize(output, snapshot, Json);
            bytes = output.ToArray(); StorageErrorKey = null; return true;
        }
        catch (StorageException e)
        {
            StorageErrorKey = e.Key;
            if (notify) StorageBlocked?.Invoke(e.Key);
            else { SaveErrorKey = e.Key; SaveError = e.Key; }
            return false;
        }
    }
    bool Save(byte[] bytes)
    {
        try
        {
            rootGuard.EnsureCreated();
            var previous = ExistingValid(DocumentPath, primaryFingerprint);
            var backup = ExistingValid(BackupPath, backupFingerprint);
            if (previous is not null)
            {
                AtomicWriteChecked(BackupPath, previous.Value.Bytes, backup?.Metadata, rootGuard.Check); backupFingerprint = Fingerprint(previous.Value.Bytes);
            }
            AtomicWriteChecked(DocumentPath, bytes, previous?.Metadata, rootGuard.Check); primaryFingerprint = Fingerprint(bytes);
            SaveError = null; SaveErrorKey = null; return true;
        }
        catch (StorageException e) { SaveError = e.Key; SaveErrorKey = e.Key; return false; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { SaveError = e.Message; SaveErrorKey = null; return false; }
    }
    (byte[] Bytes, EntryMetadata Metadata)? ExistingValid(string path, string? expected)
    {
        rootGuard.Check();
        var metadata = InspectOrMissing(path);
        if (metadata is null) { if (expected is not null) throw new StorageException("error.storageChanged"); return null; }
        try
        {
            var bytes = ReadBounded(path, metadata.Value);
            rootGuard.Check();
            if (expected is not null && Fingerprint(bytes) == expected) return (bytes, metadata.Value);
            Decode(bytes);
            throw new StorageException("error.storageChanged");
        }
        catch (StorageException e) when (e.Key != "error.storageChanged")
        {
            Preserve(path, metadata.Value); RecoveryKey = "recovery.primary"; RecoveryErrorKey = e.Key; return null;
        }
        catch (Exception e) when (e is JsonException or InvalidDataException)
        {
            Preserve(path, metadata.Value); RecoveryKey = "recovery.primary"; return null;
        }
    }
    public static void AtomicWrite(string path, byte[] bytes)
        => WriteAtomically(path, bytes, null);
    internal static void AtomicWriteChecked(string path, byte[] bytes, EntryMetadata? expected, Action? verifyRoot = null)
    {
        verifyRoot?.Invoke();
        var directory = Path.GetDirectoryName(Path.GetFullPath(path))!; CheckRoot(directory, false);
        WriteAtomically(path, bytes, () => { verifyRoot?.Invoke(); CheckRoot(directory, false); if (InspectOrMissing(path) != expected) throw new StorageException("error.storageChanged"); }, expected is not null, verifyRoot);
    }
    static void WriteAtomically(string path, byte[] bytes, Action? check, bool overwrite = true, Action? cleanupRoot = null)
    {
        var temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(bytes); stream.Flush(true); }
            check?.Invoke();
            File.Move(temporary, path, overwrite);
        }
        finally
        {
            var safe = true;
            try { cleanupRoot?.Invoke(); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { safe = false; }
            if (safe && File.Exists(temporary)) File.Delete(temporary);
        }
    }
    static BoardSnapshot Decode(byte[] bytes)
    {
        Preflight(bytes);
        BoardSnapshot board;
        try { board = JsonSerializer.Deserialize<BoardSnapshot>(bytes, Json) ?? throw new InvalidDataException("Invalid board."); }
        catch (InvalidOperationException e) { throw new InvalidDataException("Invalid encoded JSON text.", e); }
        Validate(board);
        return board with { Cards = Array.AsReadOnly(board.Cards.Select(c => c with { Color = Columns.Color(c.Column) }).ToArray()) };
    }
    static void Validate(BoardSnapshot board)
    {
        if (board.SchemaVersion != 1 || board.WipLimit < 1 || board.Cards is null || board.BoardTitle is null || board.Cards.Any(c => c is null))
            throw new InvalidDataException("Invalid board format.");
        if (board.Cards.Count > BoardBudget.CardCount) throw new StorageException("error.storageCardCount");
        long text = TextSize(board.BoardTitle, BoardBudget.BoardTitleBytes);
        var ids = new HashSet<Guid>();
        foreach (var card in board.Cards)
        {
            if (!ids.Add(card.Id) || card.Id == Guid.Empty || card.Title is null || card.Notes is null || !Columns.All.Contains(card.Column) || !double.IsFinite(card.CreatedAt) || !double.IsFinite(card.UpdatedAt))
                throw new InvalidDataException("Invalid card format.");
            text += TextSize(card.Title, BoardBudget.CardTitleBytes) + TextSize(card.Notes, BoardBudget.CardNotesBytes);
            if (text > BoardBudget.TextBytes) throw new StorageException("error.storageTextBudget");
        }
    }
    static int TextSize(string value, int maximum)
    {
        // UTF-16 length is a cheap lower bound; never scan an unbounded rejected field.
        if (value.Length > maximum) throw new StorageException("error.storageFieldSize");
        int length;
        try { length = StrictUtf8.GetByteCount(value); }
        catch (EncoderFallbackException) { throw new StorageException("error.storageFieldSize"); }
        if (length > maximum) throw new StorageException("error.storageFieldSize");
        return length;
    }
    static void Preflight(byte[] bytes)
    {
        if (bytes.Length > BoardBudget.FileBytes) throw new StorageException("error.storageFileSize");
        var reader = new Utf8JsonReader(bytes, new JsonReaderOptions { MaxDepth = BoardBudget.JsonDepth + 1 });
        var tokens = 0; var count = 0; long text = 0;
        var fieldLimit = 0; var cardsDepth = -1; var cardsProperty = false;
        try
        {
            while (reader.Read())
            {
                if (++tokens > BoardBudget.JsonTokens || reader.CurrentDepth >= BoardBudget.JsonDepth) throw new StorageException("error.storageStructure");
                if (reader.TokenType == JsonTokenType.PropertyName)
                {
                    cardsProperty = reader.CurrentDepth == 1 && reader.ValueTextEquals("cards");
                    fieldLimit = reader.CurrentDepth == 1 && reader.ValueTextEquals("boardTitle") ? BoardBudget.BoardTitleBytes :
                        cardsDepth >= 0 && reader.CurrentDepth == cardsDepth + 2 && reader.ValueTextEquals("title") ? BoardBudget.CardTitleBytes :
                        cardsDepth >= 0 && reader.CurrentDepth == cardsDepth + 2 && reader.ValueTextEquals("notes") ? BoardBudget.CardNotesBytes : 0;
                    continue;
                }
                if (cardsProperty && reader.TokenType == JsonTokenType.StartArray) cardsDepth = reader.CurrentDepth;
                cardsProperty = false;
                if (cardsDepth >= 0 && reader.CurrentDepth == cardsDepth + 1 && reader.TokenType is JsonTokenType.StartObject or JsonTokenType.StartArray or JsonTokenType.String or JsonTokenType.Number or JsonTokenType.True or JsonTokenType.False or JsonTokenType.Null)
                    if (++count > BoardBudget.CardCount) throw new StorageException("error.storageCardCount");
                if (reader.TokenType == JsonTokenType.EndArray && reader.CurrentDepth == cardsDepth) cardsDepth = -1;
                if (reader.TokenType == JsonTokenType.String && fieldLimit > 0)
                {
                    // Escapes use at most six bytes per decoded UTF-8 byte.
                    if (reader.ValueSpan.Length > fieldLimit * 6) throw new StorageException("error.storageFieldSize");
                    text += TextSize(reader.GetString()!, fieldLimit);
                    if (text > BoardBudget.TextBytes) throw new StorageException("error.storageTextBudget");
                }
                fieldLimit = 0;
            }
        }
        catch (JsonException e) when (reader.CurrentDepth >= BoardBudget.JsonDepth) { throw new StorageException("error.storageStructure", e); }
        catch (InvalidOperationException e) { throw new InvalidDataException("Invalid encoded JSON text.", e); }
    }
    void Load()
    {
        try { rootGuard.EnsureCreated(); }
        catch (StorageException e) { SaveError = e.Key; SaveErrorKey = e.Key; RecoveryErrorKey = e.Key; RecoveryKey = "recovery.both"; return; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { SaveError = e.Message; RecoveryKey = "recovery.both"; return; }
        var damaged = false;
        BoardSnapshot? primary = null, backup = null;
        foreach (var path in new[] { DocumentPath, BackupPath })
        {
            EntryMetadata? metadata = null;
            try
            {
                rootGuard.Check();
                metadata = InspectOrMissing(path); if (metadata is null) continue;
                var bytes = ReadBounded(path, metadata.Value); var decoded = Decode(bytes);
                rootGuard.Check();
                if (path == DocumentPath) { primary = decoded; primaryFingerprint = Fingerprint(bytes); }
                else { backup = decoded; backupFingerprint = Fingerprint(bytes); }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException)
            {
                damaged = true;
                if (e is StorageException storage) RecoveryErrorKey = storage.Key;
                if (e is StorageException { Key: "error.storageChanged" }) { SaveErrorKey = "error.storageChanged"; SaveError = SaveErrorKey; continue; }
                try { if (metadata is not null) Preserve(path, metadata.Value); }
                catch (StorageException preserveError) { SaveErrorKey = preserveError.Key; SaveError = preserveError.Key; }
                catch (Exception preserveError) when (preserveError is IOException or UnauthorizedAccessException) { SaveError = preserveError.Message; }
            }
        }
        Snapshot = primary ?? backup ?? new();
        if (primary is null && backup is not null) RecoveryKey = "recovery.backup";
        else if (damaged) RecoveryKey = primary is null ? "recovery.both" : "recovery.primary";
    }
    static string Fingerprint(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    void Preserve(string path, EntryMetadata metadata) => PreserveReserved(path, DirectoryPath, metadata, verifyRoot: rootGuard.Check);
    internal static void PreserveReserved(string path, string directory, EntryMetadata metadata, bool preferences = false, Action? verifyRoot = null)
    {
        // Rename only an app-reserved entry in this directory, never a link target.
        verifyRoot?.Invoke();
        CheckRoot(directory, false);
        if (Path.GetDirectoryName(Path.GetFullPath(path)) != Path.GetFullPath(directory) || metadata.Kind is not (EntryKind.Regular or EntryKind.Link)) throw new StorageException("error.storageFileType");
        if (InspectOrMissing(path) is not EntryMetadata current || current != metadata) throw new StorageException("error.storageChanged");
        verifyRoot?.Invoke();
        var name = preferences ? Path.GetFileName(path) + ".corrupt-" + Guid.NewGuid().ToString("N") : Path.GetFileNameWithoutExtension(path) + ".corrupt-" + DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() + "-" + Guid.NewGuid().ToString("N") + ".json";
        File.Move(path, Path.Combine(directory, name));
    }
    internal sealed class StorageException(string key, Exception? inner = null) : IOException(key, inner)
    {
        public string Key { get; } = key;
    }
    sealed class BoundedOutput : MemoryStream
    {
        void Permit(int count) { if (Position + count > BoardBudget.FileBytes) throw new StorageException("error.storageFileSize"); }
        public override void Write(byte[] buffer, int offset, int count) { Permit(count); base.Write(buffer, offset, count); }
        public override void Write(ReadOnlySpan<byte> buffer) { Permit(buffer.Length); base.Write(buffer); }
        public override void WriteByte(byte value) { Permit(1); base.WriteByte(value); }
    }
    internal sealed class RootGuard(string directory)
    {
        bool observed;
        string? identity;
        public void EnsureCreated()
        {
            var current = InspectOrMissing(directory);
            if (!observed)
            {
                observed = true;
                if (current is EntryMetadata initial)
                {
                    if (initial.Kind != EntryKind.Directory) throw new StorageException("error.storageFileType");
                    identity = initial.Identity;
                }
            }
            if (current is EntryMetadata existing)
            {
                if (existing.Kind != EntryKind.Directory) throw new StorageException("error.storageFileType");
                if (identity != existing.Identity) throw new StorageException("error.storageChanged");
                return;
            }
            if (identity is not null) throw new StorageException("error.storageChanged");
            var parent = Path.GetDirectoryName(directory); if (parent is not null) Directory.CreateDirectory(parent);
            var created = OperatingSystem.IsWindows() ? Native.CreateDirectory(directory, IntPtr.Zero) : Native.MkDir(directory, 0x1c0) == 0;
            if (!created)
            {
                var error = Marshal.GetLastPInvokeError();
                if (error is 17 or 183) throw new StorageException("error.storageChanged");
                throw new IOException("Unable to create the private data directory.");
            }
            current = InspectOrMissing(directory);
            if (current is not EntryMetadata owned || owned.Kind != EntryKind.Directory) throw new StorageException("error.storageChanged");
            identity = owned.Identity;
        }
        public void Check()
        {
            var current = InspectOrMissing(directory);
            if (!observed || identity is null || current is not EntryMetadata existing || existing.Identity != identity) throw new StorageException("error.storageChanged");
            if (existing.Kind != EntryKind.Directory) throw new StorageException("error.storageFileType");
        }
    }
    internal static void CheckRoot(string directory, bool create)
    {
        var metadata = InspectOrMissing(directory);
        if (metadata is not null && metadata.Value.Kind != EntryKind.Directory) throw new StorageException("error.storageFileType");
        if (!create) return;
        Directory.CreateDirectory(directory);
        if (InspectOrMissing(directory) is not EntryMetadata current || current.Kind != EntryKind.Directory) throw new StorageException("error.storageFileType");
    }
    internal enum EntryKind { Regular, Directory, Link, Other }
    internal readonly record struct EntryMetadata(string Identity, string Revision, EntryKind Kind, long Links);
    internal static EntryMetadata? InspectOrMissing(string path)
    {
        if (OperatingSystem.IsWindows())
        {
            using var handle = Native.CreateFile(path, 0x80, 7, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
            if (handle.IsInvalid) { var error = Marshal.GetLastPInvokeError(); if (error is 2 or 3) return null; throw new IOException("Unable to inspect the reserved board file."); }
            return Metadata(handle);
        }
        var buffer = Marshal.AllocHGlobal(512);
        try
        {
            if (Native.LStat(path, buffer) != 0) { var error = Marshal.GetLastPInvokeError(); if (error is 2 or 20) return null; throw new IOException("Unable to inspect the reserved board file."); }
            return UnixMetadata(buffer);
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
    static EntryMetadata Metadata(SafeFileHandle handle)
    {
        if (OperatingSystem.IsWindows())
        {
            if (!Native.FileInformation(handle, out var info) || Native.FileType(handle) != 1) throw new StorageException("error.storageFileType");
            var kind = (info.Attributes & 0x400) != 0 ? EntryKind.Link : (info.Attributes & 0x10) == 0 ? EntryKind.Regular : EntryKind.Directory;
            return new($"{info.Volume:x}:{info.IndexHigh:x}:{info.IndexLow:x}", $"{info.SizeHigh:x}:{info.SizeLow:x}:{info.Written.dwHighDateTime:x}:{info.Written.dwLowDateTime:x}", kind, info.Links);
        }
        var buffer = Marshal.AllocHGlobal(512);
        try { if (Native.FStat(handle.DangerousGetHandle().ToInt32(), buffer) != 0) throw new IOException("Unable to inspect the open board file."); return UnixMetadata(buffer); }
        finally { Marshal.FreeHGlobal(buffer); }
    }
    static EntryMetadata UnixMetadata(IntPtr data)
    {
        var mac = OperatingSystem.IsMacOS(); var arm = RuntimeInformation.ProcessArchitecture == Architecture.Arm64;
        var mode = mac ? (ushort)Marshal.ReadInt16(data, 4) : Marshal.ReadInt32(data, arm ? 16 : 24);
        var kind = (mode & 0xf000) switch { 0x8000 => EntryKind.Regular, 0x4000 => EntryKind.Directory, 0xa000 => EntryKind.Link, _ => EntryKind.Other };
        var links = mac ? (ushort)Marshal.ReadInt16(data, 6) : arm ? (uint)Marshal.ReadInt32(data, 20) : Marshal.ReadInt64(data, 16);
        var device = mac ? (uint)Marshal.ReadInt32(data) : (ulong)Marshal.ReadInt64(data);
        var inode = (ulong)Marshal.ReadInt64(data, 8);
        var size = Marshal.ReadInt64(data, mac ? 96 : 48);
        var modified = Marshal.ReadInt64(data, mac ? 48 : 88); var modifiedNanos = Marshal.ReadInt64(data, mac ? 56 : 96);
        var changed = Marshal.ReadInt64(data, mac ? 64 : 104); var changedNanos = Marshal.ReadInt64(data, mac ? 72 : 112);
        return new($"{device:x}:{inode:x}", $"{size:x}:{modified:x}:{modifiedNanos:x}:{changed:x}:{changedNanos:x}", kind, links);
    }
    internal static byte[] ReadBounded(string path, EntryMetadata expected, int maximumBytes = BoardBudget.FileBytes)
    {
        if (expected.Kind != EntryKind.Regular || expected.Links != 1) throw new StorageException("error.storageFileType");
        SafeFileHandle handle;
        if (OperatingSystem.IsWindows()) handle = Native.CreateFile(path, 0x80000000, 1, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero);
        else
        {
            var flags = OperatingSystem.IsMacOS() ? 0x104 : 0x20800; // O_NOFOLLOW | O_NONBLOCK.
            var descriptor = Native.Open(path, flags);
            handle = new SafeFileHandle(new IntPtr(descriptor), true);
        }
        using (handle)
        {
            if (handle.IsInvalid) throw new IOException("Unable to open the reserved board file safely.");
            if (Metadata(handle) != expected) throw new StorageException("error.storageChanged");
            using var stream = new FileStream(handle, FileAccess.Read, 65536, false);
            var length = stream.Length;
            if (length > maximumBytes) throw new StorageException("error.storageFileSize");
            var bytes = new byte[(int)length]; var read = 0;
            while (read < bytes.Length)
            {
                var count = stream.Read(bytes, read, bytes.Length - read);
                if (count == 0) throw new StorageException("error.storageChanged");
                read += count;
            }
            // A growing file is refused after one extra byte, never read without a bound.
            if (stream.ReadByte() != -1) throw new StorageException("error.storageFileSize");
            if (Metadata(handle) != expected) throw new StorageException("error.storageChanged");
            return bytes;
        }
    }
    static class Native
    {
        [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", EntryPoint = "GetFileInformationByHandle", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)] public static extern bool FileInformation(SafeFileHandle handle, out FileInfo info);
        [DllImport("kernel32.dll", EntryPoint = "GetFileType")] public static extern uint FileType(SafeFileHandle handle);
        [DllImport("kernel32.dll", EntryPoint = "CreateDirectoryW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)] public static extern bool CreateDirectory(string path, IntPtr security);
        [StructLayout(LayoutKind.Sequential)] public struct FileInfo
        {
            public uint Attributes; public System.Runtime.InteropServices.ComTypes.FILETIME Created, Accessed, Written;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("libc", EntryPoint = "open", SetLastError = true)] public static extern int Open(string path, int flags);
        [DllImport("libc", EntryPoint = "lstat", SetLastError = true)] public static extern int LStat(string path, IntPtr data);
        [DllImport("libc", EntryPoint = "fstat", SetLastError = true)] public static extern int FStat(int descriptor, IntPtr data);
        [DllImport("libc", EntryPoint = "mkdir", SetLastError = true)] public static extern int MkDir(string path, uint mode);
    }
}
