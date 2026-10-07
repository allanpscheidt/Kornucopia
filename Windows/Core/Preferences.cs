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
    readonly BoardStore.RootGuard rootGuard;
    public PreferenceStore(string directory)
    {
        rootGuard = new BoardStore.RootGuard(Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory)));
    }
    public Preferences Value { get; private set; } = new();
    public string? Error { get; private set; }
    public string? ErrorKey { get; private set; }
    string? fingerprint;
    bool accessRefused;
    public void Load()
    {
        BoardStore.EntryMetadata? metadata = null;
        StorageDirectory? storage = null;
        accessRefused = false;
        try
        {
            storage = rootGuard.Open();
            metadata = storage.Inspect("preferences.json"); if (metadata is null) return;
            var bytes = storage.Read("preferences.json", metadata.Value, MaximumFileBytes);
            Value = Decode(bytes); fingerprint = Digest(bytes); Error = null; ErrorKey = null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException or EncoderFallbackException)
        {
            ErrorKey = Key(e); Error = ErrorKey ?? e.Message;
            if (e is BoardStore.StorageException { Key: "error.storageUnsafeRoot" }) { accessRefused = true; fingerprint = null; }
            if (e is BoardStore.StorageException { Key: "error.storageChanged" or "error.storageUnsafeRoot" }) return;
            try { if (metadata is not null) storage!.Preserve("preferences.json", metadata.Value, true); }
            catch (Exception preserveError) when (preserveError is IOException or UnauthorizedAccessException) { ErrorKey = Key(preserveError); Error = ErrorKey ?? preserveError.Message; }
        }
        finally { storage?.Dispose(); }
    }
    public bool Save(Preferences value)
    {
        try
        {
            Validate(value);
            var bytes = JsonSerializer.SerializeToUtf8Bytes(value, Json);
            if (bytes.Length > MaximumFileBytes) throw new InvalidDataException("Preferences exceed the byte budget.");
            Value = value;
            if (accessRefused) throw new BoardStore.StorageException("error.storageUnsafeRoot");
            using var storage = rootGuard.Open();
            var metadata = storage.Inspect("preferences.json");
            if (metadata is not null)
            {
                try
                {
                    var current = storage.Read("preferences.json", metadata.Value, MaximumFileBytes);
                    if (fingerprint is null || Digest(current) != fingerprint)
                    {
                        Decode(current);
                        throw new BoardStore.StorageException("error.storageChanged");
                    }
                }
                catch (BoardStore.StorageException e) when (e.Key is not ("error.storageChanged" or "error.storageUnsafeRoot")) { storage.Preserve("preferences.json", metadata.Value, true); metadata = null; }
                catch (Exception e) when (e is JsonException or InvalidDataException) { storage.Preserve("preferences.json", metadata.Value, true); metadata = null; }
            }
            else if (fingerprint is not null) throw new BoardStore.StorageException("error.storageChanged");
            storage.Write("preferences.json", bytes, metadata); fingerprint = Digest(bytes); Error = null; ErrorKey = null; return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException or EncoderFallbackException)
        { ErrorKey = Key(e); Error = ErrorKey ?? e.Message; return false; }
    }
    static string Digest(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    static string? Key(Exception e) => e is BoardStore.StorageException { Key: "error.storageUnsafeRoot" } ? "error.storageUnsafeRoot" : e is BoardStore.StorageException { Key: "error.storageChanged" } ? "error.preferencesChanged" : e is BoardStore.StorageException or JsonException or InvalidDataException or EncoderFallbackException ? "error.preferencesBudget" : null;
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
