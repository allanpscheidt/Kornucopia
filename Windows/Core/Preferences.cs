using System.Text.Json;
using System.Security.Cryptography;
using System.Text;

namespace Kornucopia.Core;

public sealed record Preferences
{
    public string Language { get; init; } = "auto";
    public double Width { get; init; } = 1360;
    public double Height { get; init; } = 840;
    public double? Left { get; init; }
    public double? Top { get; init; }
    public bool Maximized { get; init; }
    public Guid? EditingCardId { get; init; }
    public string Query { get; init; } = "";
}

public sealed class PreferenceStore
{
    public const int MaximumFileBytes = 64 * 1024;
    public const int MaximumQueryBytes = 4096;
    static readonly JsonSerializerOptions Json = new() { MaxDepth = 8 };
    static readonly UTF8Encoding Utf8 = new(false, true);
    readonly string directory;
    readonly string path;
    readonly BoardStore.RootGuard rootGuard;
    public PreferenceStore(string directory)
    {
        this.directory = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
        path = Path.Combine(this.directory, "preferences.json");
        rootGuard = new BoardStore.RootGuard(this.directory);
    }
    public Preferences Value { get; private set; } = new();
    public string? Error { get; private set; }
    public string? ErrorKey { get; private set; }
    string? fingerprint;
    public void Load()
    {
        BoardStore.EntryMetadata? metadata = null;
        try
        {
            rootGuard.EnsureCreated();
            metadata = BoardStore.InspectOrMissing(path); if (metadata is null) return;
            var bytes = BoardStore.ReadBounded(path, metadata.Value, MaximumFileBytes);
            rootGuard.Check();
            Value = Decode(bytes); fingerprint = Digest(bytes);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException or EncoderFallbackException)
        {
            ErrorKey = Key(e); Error = ErrorKey ?? e.Message;
            if (e is BoardStore.StorageException { Key: "error.storageChanged" }) return;
            try { if (metadata is not null) BoardStore.PreserveReserved(path, directory, metadata.Value, true, rootGuard.Check); }
            catch (Exception preserveError) when (preserveError is IOException or UnauthorizedAccessException) { ErrorKey = Key(preserveError); Error = ErrorKey ?? preserveError.Message; }
        }
    }
    public bool Save(Preferences value)
    {
        try
        {
            Validate(value);
            var bytes = JsonSerializer.SerializeToUtf8Bytes(value, Json);
            if (bytes.Length > MaximumFileBytes) throw new InvalidDataException("Preferences exceed the byte budget.");
            Value = value; rootGuard.EnsureCreated();
            var metadata = BoardStore.InspectOrMissing(path);
            if (metadata is not null)
            {
                try
                {
                    var current = BoardStore.ReadBounded(path, metadata.Value, MaximumFileBytes);
                    rootGuard.Check();
                    if (fingerprint is null || Digest(current) != fingerprint)
                    {
                        Decode(current);
                        throw new BoardStore.StorageException("error.storageChanged");
                    }
                }
                catch (BoardStore.StorageException e) when (e.Key != "error.storageChanged") { BoardStore.PreserveReserved(path, directory, metadata.Value, true, rootGuard.Check); metadata = null; }
                catch (Exception e) when (e is JsonException or InvalidDataException) { BoardStore.PreserveReserved(path, directory, metadata.Value, true, rootGuard.Check); metadata = null; }
            }
            else if (fingerprint is not null) throw new BoardStore.StorageException("error.storageChanged");
            BoardStore.AtomicWriteChecked(path, bytes, metadata, rootGuard.Check); fingerprint = Digest(bytes); Error = null; ErrorKey = null; return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException or EncoderFallbackException)
        { ErrorKey = Key(e); Error = ErrorKey ?? e.Message; return false; }
    }
    static string Digest(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    static string? Key(Exception e) => e is BoardStore.StorageException { Key: "error.storageChanged" } ? "error.preferencesChanged" : e is BoardStore.StorageException or JsonException or InvalidDataException or EncoderFallbackException ? "error.preferencesBudget" : null;
    static Preferences Decode(byte[] bytes)
    {
        var reader = new Utf8JsonReader(bytes, new JsonReaderOptions { MaxDepth = 9 }); var tokens = 0;
        while (reader.Read()) if (++tokens > 512 || reader.CurrentDepth >= 8) throw new InvalidDataException("Preferences exceed the structure budget.");
        Preferences value;
        try { value = JsonSerializer.Deserialize<Preferences>(bytes, Json) ?? throw new InvalidDataException("Invalid preferences."); }
        catch (InvalidOperationException e) { throw new InvalidDataException("Invalid encoded preference text.", e); }
        Validate(value); return value;
    }
    static void Validate(Preferences value)
    {
        if (value.Language is null || value.Query is null || value.Language.Length > 16 || !new[] { "auto", "pt-BR", "en", "es", "fr", "ja" }.Contains(value.Language) ||
            value.Query.Length > MaximumQueryBytes || Utf8.GetByteCount(value.Query) > MaximumQueryBytes ||
            !double.IsFinite(value.Width) || !double.IsFinite(value.Height) || value.Left is double left && !double.IsFinite(left) || value.Top is double top && !double.IsFinite(top))
            throw new InvalidDataException("Invalid preference fields or text budget.");
    }
}
