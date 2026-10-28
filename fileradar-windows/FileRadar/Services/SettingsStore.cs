using System.Text.Json;
using FileRadar.Models;

namespace FileRadar.Services;

/// <summary>Persists chrome view + appearance prefs under %LocalAppData%\FileRadar\settings.json.</summary>
public sealed class SettingsStore
{
    private readonly string _path;

    public SettingsStore()
    {
        _path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "FileRadar", "settings.json");
    }

    public void LoadInto(ThemeSettings theme)
    {
        try
        {
            if (!File.Exists(_path)) return;
            var dto = JsonSerializer.Deserialize<SettingsDto>(File.ReadAllText(_path));
            if (dto is null) return;
            theme.ChromeView = ChromeViewIds.Normalize(dto.ChromeView);
            if (Enum.TryParse<AppearanceMode>(dto.Appearance, ignoreCase: true, out var appearance))
                theme.Appearance = appearance;
            if (Enum.TryParse<ViewMode>(dto.ViewMode, ignoreCase: true, out var viewMode))
                theme.ViewMode = viewMode;
            theme.DualPane = dto.DualPane;
            theme.InspectorOpen = dto.InspectorOpen;
            theme.PreferCopyOnDrop = dto.PreferCopyOnDrop;
        }
        catch
        {
            /* keep defaults */
        }
    }

    public void Save(ThemeSettings theme)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            var dto = new SettingsDto
            {
                ChromeView = ChromeViewIds.Normalize(theme.ChromeView),
                Appearance = theme.Appearance.ToString(),
                ViewMode = theme.ViewMode.ToString(),
                DualPane = theme.DualPane,
                InspectorOpen = theme.InspectorOpen,
                PreferCopyOnDrop = theme.PreferCopyOnDrop
            };
            File.WriteAllText(_path, JsonSerializer.Serialize(dto, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch
        {
            /* ignore */
        }
    }

    private sealed class SettingsDto
    {
        public string ChromeView { get; set; } = ChromeViewIds.RadarGlass;
        public string Appearance { get; set; } = nameof(AppearanceMode.Dark);
        public string ViewMode { get; set; } = nameof(Models.ViewMode.List);
        public bool DualPane { get; set; } = true;
        public bool InspectorOpen { get; set; }
        public bool PreferCopyOnDrop { get; set; } = true;
    }
}
