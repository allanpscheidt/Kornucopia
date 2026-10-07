using System.Globalization;
using System.Text.Json;

namespace Kornucopia.Windows;

public sealed class Locale
{
    public static readonly string[] Supported = ["pt-BR", "en", "es", "fr", "ja"];
    public static readonly string[] NativeNames = ["Português (Brasil)", "English", "Español", "Français", "日本語"];
    readonly Dictionary<string, Dictionary<string, string>> catalogs = [];
    public string Language { get; private set; } = "en";
    public event Action? Changed;
    public Locale(string preference)
    {
        foreach (var language in Supported)
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Resources", "Localization", language + ".json");
            if (!File.Exists(path)) throw new FileNotFoundException("Required interface catalog is missing.", path);
            catalogs[language] = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllBytes(path)) ?? throw new InvalidDataException("Invalid interface catalog.");
        }
        Set(preference);
    }
    public static string SystemLanguage => Normalize(CultureInfo.CurrentUICulture.Name);
    static string Normalize(string value)
    {
        if (value.StartsWith("pt", StringComparison.OrdinalIgnoreCase)) return "pt-BR";
        var shortName = value.Split('-')[0].ToLowerInvariant();
        return Supported.Contains(shortName) ? shortName : "en";
    }
    public void Set(string preference)
    {
        Language = preference == "auto" ? SystemLanguage : Normalize(preference);
        Changed?.Invoke();
    }
    public string T(string key, string fallback = "", params (string Key, object Value)[] values)
    {
        var text = catalogs.GetValueOrDefault(Language)?.GetValueOrDefault(key) ?? catalogs.GetValueOrDefault("en")?.GetValueOrDefault(key) ?? (fallback.Length > 0 ? fallback : key);
        foreach (var (name, value) in values) text = text.Replace("{" + name + "}", Convert.ToString(value, CultureInfo.InvariantCulture));
        return text;
    }
}
