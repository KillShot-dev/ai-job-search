namespace FileRadar.Models;

/// <summary>
/// Looks from one layout. Primary chrome is Apple-like Modern (slate + blue).
/// Elegant remains a calm alternate. Colourful/Minimal stay in the catalog
/// but are not cycled from the toolbar.
/// </summary>
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
    public double Radius { get; init; }
}

public static class ThemeCatalog
{
    /// <summary>Primary looks shown in calm chrome (Modern ↔ Elegant).</summary>
    public static readonly AppLook[] PrimaryLooks = [AppLook.Modern, AppLook.Elegant];

    public static ThemePalette Resolve(AppLook look, bool dark) => (look, dark) switch
    {
        // Apple-like Modern: neutral slate, system-blue accent, soft frosted panels
        (AppLook.Modern, false) => new ThemePalette
        {
            Accent = "#0A6BFF", Accent2 = "#5B6B7C", Bg = "#F5F5F7", Panel = "#FBFBFC",
            Panel2 = "#EEF0F3", Text = "#1D1D1F", Muted = "#6E6E73", Border = "#D2D2D7",
            Chip = "#E8F0FF", Radius = 10
        },
        (AppLook.Modern, true) => new ThemePalette
        {
            Accent = "#0A84FF", Accent2 = "#8E8E93", Bg = "#1C1C1E", Panel = "#2C2C2E",
            Panel2 = "#3A3A3C", Text = "#F5F5F7", Muted = "#98989D", Border = "#48484A",
            Chip = "#1C3A5F", Radius = 10
        },
        (AppLook.Elegant, false) => new ThemePalette
        {
            Accent = "#1F736B", Accent2 = "#8B6914", Bg = "#F4F7F6", Panel = "#FBFBFC",
            Panel2 = "#E7EFED", Text = "#14201E", Muted = "#5A6B68", Border = "#D2DDD9",
            Chip = "#DFF3EF", Radius = 14
        },
        (AppLook.Elegant, true) => new ThemePalette
        {
            Accent = "#3DB8AB", Accent2 = "#D4A84B", Bg = "#101816", Panel = "#1A2421",
            Panel2 = "#24302C", Text = "#E8F2EF", Muted = "#9BB0AA", Border = "#2F3F3A",
            Chip = "#1F3A35", Radius = 14
        },
        // Retained for catalog parity; not offered in primary chrome
        (AppLook.Colourful, false) => new ThemePalette
        {
            Accent = "#E86A3C", Accent2 = "#2F7D6B", Bg = "#F3EEE6", Panel = "#FFFCF7",
            Panel2 = "#F6EFE4", Text = "#1A1714", Muted = "#6B6259", Border = "#E2D6C6",
            Chip = "#FFEADF", Radius = 14
        },
        (AppLook.Colourful, true) => new ThemePalette
        {
            Accent = "#FF8A5C", Accent2 = "#5EC2AD", Bg = "#1E1A17", Panel = "#2A2521",
            Panel2 = "#332C26", Text = "#F5EFE8", Muted = "#B3A89D", Border = "#453C34",
            Chip = "#44352B", Radius = 14
        },
        (AppLook.Minimal, false) => new ThemePalette
        {
            Accent = "#111111", Accent2 = "#555555", Bg = "#F5F5F5", Panel = "#FFFFFF",
            Panel2 = "#EEEEEE", Text = "#111111", Muted = "#666666", Border = "#DDDDDD",
            Chip = "#EEEEEE", Radius = 6
        },
        _ => new ThemePalette
        {
            Accent = "#FFFFFF", Accent2 = "#CCCCCC", Bg = "#111111", Panel = "#1C1C1C",
            Panel2 = "#262626", Text = "#F2F2F2", Muted = "#AAAAAA", Border = "#333333",
            Chip = "#2A2A2A", Radius = 6
        }
    };
}

public sealed class ThemeSettings
{
    public AppLook Look { get; set; } = AppLook.Modern;
    public AppearanceMode Appearance { get; set; } = AppearanceMode.System;
    public ViewMode ViewMode { get; set; } = ViewMode.Grid;
    public bool DualPane { get; set; }
    public bool InspectorOpen { get; set; } = true;

    public bool IsDark(bool systemDark) => Appearance switch
    {
        AppearanceMode.Light => false,
        AppearanceMode.Dark => true,
        _ => systemDark
    };

    /// <summary>Cycle only calm primary looks (Modern ↔ Elegant).</summary>
    public void CycleLook()
    {
        var all = ThemeCatalog.PrimaryLooks;
        var i = Array.IndexOf(all, Look);
        Look = all[(i + 1) % all.Length];
    }

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
