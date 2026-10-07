using System.Text.Json;

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

public sealed class PreferenceStore(string directory)
{
    readonly string path = Path.Combine(directory, "preferences.json");
    public Preferences Value { get; private set; } = new();
    public string? Error { get; private set; }
    string? blockedWrites;
    public void Load()
    {
        if (!File.Exists(path)) return;
        try
        {
            var loaded = JsonSerializer.Deserialize<Preferences>(File.ReadAllBytes(path)) ?? throw new InvalidDataException("Invalid preferences.");
            if (loaded.Language is null || loaded.Query is null || !new[] { "auto", "pt-BR", "en", "es", "fr", "ja" }.Contains(loaded.Language)) throw new InvalidDataException("Invalid preference fields.");
            Value = loaded;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException)
        {
            Error = e.Message;
            try { File.Move(path, path + ".corrupt-" + Guid.NewGuid().ToString("N")); }
            catch (Exception preserveError) when (preserveError is IOException or UnauthorizedAccessException) { blockedWrites = preserveError.Message; Error = blockedWrites; }
        }
    }
    public bool Save(Preferences value)
    {
        Value = value;
        if (blockedWrites is not null) { Error = blockedWrites; return false; }
        try { Directory.CreateDirectory(directory); BoardStore.AtomicWrite(path, JsonSerializer.SerializeToUtf8Bytes(value)); Error = null; return true; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { Error = e.Message; return false; }
    }
}
