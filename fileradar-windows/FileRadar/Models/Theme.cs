namespace FileRadar.Models;

/// <summary>Looks retained for catalog parity. Primary chrome is Modern only.</summary>
public enum AppLook
{
    Modern,
    Elegant,
    Colourful,
    Minimal
}

public enum AppearanceMode
{
    System,
    Light,
    Dark
}

public enum ViewMode
{
    Grid,
    List
}

public sealed class ThemePalette
{
    public required string Accent { get; init; }
    public required string Accent2 { get; init; }
    public required string Bg { get; init; }
    public required string Panel { get; init; }
    public required string Panel2 { get; init; }
    public required string Text { get; init; }
    public required string Muted { get; init; }
    public required string Border { get; init; }
    public required string Chip { get; init; }
    public required string Selection { get; init; }
    public double Radius { get; init; }
}

public static class ThemeCatalog
{
    public static ThemePalette Resolve(AppLook look, bool dark) => (look, dark) switch
    {
        // Showcase Modern — soft frosted slate + electric blue (mockup)
        (_, false) => new ThemePalette
        {
            Accent = "#007AFF", Accent2 = "#5AC8FA", Bg = "#E8E8ED", Panel = "#F5F5F7",
            Panel2 = "#FFFFFF", Text = "#1D1D1F", Muted = "#6E6E73", Border = "#D2D2D7",
            Chip = "#E5F0FF", Selection = "#007AFF22", Radius = 12
        },
        _ => new ThemePalette
        {
            Accent = "#0A84FF", Accent2 = "#64D2FF", Bg = "#1C1C1E", Panel = "#2C2C2E",
            Panel2 = "#3A3A3C", Text = "#F5F5F7", Muted = "#98989D", Border = "#48484A",
            Chip = "#1C3A5F", Selection = "#0A84FF33", Radius = 12
        }
    };
}

public sealed class ThemeSettings
{
    /// <summary>Locked to Modern for primary chrome — mockup Showcase Home.</summary>
    public AppLook Look { get; set; } = AppLook.Modern;
    /// <summary>Dark by default to match Showcase mockup frosted chrome.</summary>
    public AppearanceMode Appearance { get; set; } = AppearanceMode.Dark;
    public ViewMode ViewMode { get; set; } = ViewMode.Grid;
    public bool DualPane { get; set; }
    public bool InspectorOpen { get; set; } = true;

    public bool IsDark(bool systemDark) => Appearance switch
    {
        AppearanceMode.Light => false,
        AppearanceMode.Dark => true,
        _ => systemDark
    };

    public void CycleAppearance()
    {
        Appearance = Appearance switch
        {
            AppearanceMode.Light => AppearanceMode.Dark,
            AppearanceMode.Dark => AppearanceMode.System,
            _ => AppearanceMode.Light
        };
    }
}
