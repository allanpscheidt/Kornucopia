using System.Diagnostics;
using System.Globalization;
using System.Text.Json;

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

public sealed class BoardStore
{
    static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    static readonly DateTimeOffset Epoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
    public static double Now => (DateTimeOffset.UtcNow - Epoch).TotalSeconds;
    public string DirectoryPath { get; }
    public string DocumentPath => Path.Combine(DirectoryPath, "board.json");
    public string BackupPath => Path.Combine(DirectoryPath, "board.backup.json");
    public BoardSnapshot Snapshot { get; private set; } = new();
    public string? SaveError { get; private set; }
    public string? RecoveryKey { get; private set; }
    public bool CanUndo => undo.Count > 0;
    public bool CanRedo => redo.Count > 0;
    public int DoingCount => Snapshot.Cards.Count(c => c.Column == "doing");
    public event Action? Changed;
    public event Action? WipBlocked;
    readonly List<BoardSnapshot> undo = [];
    readonly List<BoardSnapshot> redo = [];
    string? blockedWrites;
    Guid? lastEditId;
    long lastEditTick;

    public BoardStore(string? directory = null)
    {
        DirectoryPath = directory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Kornucopia");
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
        Commit(Snapshot with { Cards = Array.AsReadOnly(Snapshot.Cards.Append(card).ToArray()) });
        return card.Id;
    }
    public bool Update(Guid id, string? title = null, string? notes = null, string? column = null)
    {
        var current = Find(id);
        if (current is null || !Permits(column ?? current.Column, current.Column)) return false;
        var destination = column ?? current.Column;
        var next = current with { Title = title ?? current.Title, Notes = notes ?? current.Notes, Column = destination, Color = Columns.Color(destination) };
        if (next == current) return true;
        next = next with { UpdatedAt = Now };
        Commit(Snapshot with { Cards = Array.AsReadOnly(Snapshot.Cards.Select(c => c.Id == id ? next : c).ToArray()) }, column is null ? id : null);
        return true;
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
        Commit(Snapshot with { Cards = cards.AsReadOnly() });
        return true;
    }
    public bool Delete(Guid id)
    {
        if (Find(id) is null) return false;
        Commit(Snapshot with { Cards = Array.AsReadOnly(Snapshot.Cards.Where(c => c.Id != id).ToArray()) });
        return true;
    }
    public bool SetTitle(string title)
    {
        title = title.Trim();
        if (title != Snapshot.BoardTitle) Commit(Snapshot with { BoardTitle = title });
        return true;
    }
    public bool SetWip(int limit)
    {
        if (limit < 1 || limit < DoingCount) return false;
        if (limit != Snapshot.WipLimit) Commit(Snapshot with { WipLimit = limit });
        return true;
    }
    public bool Undo() => Restore(undo, redo);
    public bool Redo() => Restore(redo, undo);
    bool Restore(List<BoardSnapshot> source, List<BoardSnapshot> target)
    {
        lastEditId = null;
        if (source.Count == 0) return false;
        target.Add(Snapshot); Trim(target);
        Snapshot = source[^1]; source.RemoveAt(source.Count - 1);
        Flush(); Changed?.Invoke(); return true;
    }
    void Commit(BoardSnapshot next, Guid? editId = null)
    {
        var tick = Stopwatch.GetTimestamp();
        if (editId is null || editId != lastEditId || Stopwatch.GetElapsedTime(lastEditTick, tick).TotalSeconds > .7 || redo.Count != 0) { undo.Add(Snapshot); Trim(undo); }
        redo.Clear(); lastEditId = editId; lastEditTick = tick; Snapshot = next;
        Flush(); Changed?.Invoke();
    }
    static void Trim(List<BoardSnapshot> list) { if (list.Count > 100) list.RemoveRange(0, list.Count - 100); }
    public bool Flush()
    {
        if (blockedWrites is not null) { SaveError = blockedWrites; return false; }
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            var bytes = JsonSerializer.SerializeToUtf8Bytes(Snapshot, Json);
            if (File.Exists(DocumentPath))
            {
                var previous = File.ReadAllBytes(DocumentPath);
                try { Decode(previous); }
                catch (Exception e) when (e is JsonException or InvalidDataException) { Preserve(DocumentPath); RecoveryKey = "recovery.primary"; }
                if (File.Exists(DocumentPath))
                {
                    if (File.Exists(BackupPath))
                    {
                        try { Decode(File.ReadAllBytes(BackupPath)); }
                        catch (Exception e) when (e is JsonException or InvalidDataException) { Preserve(BackupPath); }
                    }
                    AtomicWrite(BackupPath, previous);
                }
            }
            AtomicWrite(DocumentPath, bytes); SaveError = null; return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { SaveError = e.Message; return false; }
    }
    public static void AtomicWrite(string path, byte[] bytes)
    {
        var temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(bytes); stream.Flush(true); }
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    static BoardSnapshot Decode(byte[] bytes)
    {
        var board = JsonSerializer.Deserialize<BoardSnapshot>(bytes, Json) ?? throw new InvalidDataException("Invalid board.");
        if (board.SchemaVersion != 1 || board.WipLimit < 1 || board.Cards is null || board.BoardTitle is null || board.Cards.Any(c => c is null) || board.Cards.Select(c => c.Id).Distinct().Count() != board.Cards.Count)
            throw new InvalidDataException("Invalid board format.");
        if (board.Cards.Any(c => c.Id == Guid.Empty || c.Title is null || c.Notes is null || !Columns.All.Contains(c.Column) || !double.IsFinite(c.CreatedAt) || !double.IsFinite(c.UpdatedAt)))
            throw new InvalidDataException("Invalid card format.");
        return board with { Cards = Array.AsReadOnly(board.Cards.Select(c => c with { Color = Columns.Color(c.Column) }).ToArray()) };
    }
    void Load()
    {
        var damaged = false;
        foreach (var path in new[] { DocumentPath, BackupPath })
        {
            if (!File.Exists(path)) continue;
            try { Snapshot = Decode(File.ReadAllBytes(path)); if (path == BackupPath) RecoveryKey = "recovery.backup"; return; }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException)
            {
                damaged = true;
                try { Preserve(path); }
                catch (Exception preserveError) when (preserveError is IOException or UnauthorizedAccessException) { blockedWrites = preserveError.Message; SaveError = blockedWrites; }
            }
        }
        if (damaged) RecoveryKey = "recovery.both";
    }
    void Preserve(string path) => File.Move(path, Path.Combine(DirectoryPath, Path.GetFileNameWithoutExtension(path) + ".corrupt-" + DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() + "-" + Guid.NewGuid().ToString("N") + ".json"));
}
