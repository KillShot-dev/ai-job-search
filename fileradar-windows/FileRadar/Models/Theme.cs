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

/// <summary>Cross-platform FileRadarChrome tokens — ForkLift-primary dual-pane chrome.</summary>
public static class FileRadarChrome
{
    public const string Accent = "#007AFF";
    public const double RadiusCard = 12;
    public const double RadiusControl = 8;
    public const double RadiusHairline = 6;
    public const double SpacePage = 12;
    public const double SpaceSection = 16;
    public const double SpaceCardGap = 10;
    public const double SpaceChromeY = 6;
    public const double SpaceHudPadX = 18;
    public const double SpaceHudPadY = 12;
    public const double TypeTitle = 20;
    public const double TypeHeading = 13;
    public const double TypeBody = 12;
    public const double TypeCaption = 11;
    public const double SelectionStroke = 1.5;
    public const double SidebarWashOpacity = 0.14;
    public const double AccentFillOpacity = 0.08;
    public const double DropTargetWashOpacity = 0.15;
    public const double HudMaxWidth = 480;
    public const double SidebarWidth = 200;
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
        // Showcase Modern — unified look tokens (docs/fileradar-unified-look.md)
        (_, false) => new ThemePalette
        {
            Accent = FileRadarChrome.Accent, Accent2 = "#5AC8FA",
            Bg = "#E8E8ED", Panel = "#F5F5F7",
            Panel2 = "#FFFFFF", Text = "#1D1D1F", Muted = "#6E6E73", Border = "#D2D2D7",
            Chip = "#E5F0FF", Selection = "#007AFF14", Radius = FileRadarChrome.RadiusCard
        },
        _ => new ThemePalette
        {
            Accent = FileRadarChrome.Accent, Accent2 = "#64D2FF",
            Bg = "#1C1C1E", Panel = "#2C2C2E",
            Panel2 = "#3A3A3C", Text = "#F5F5F7", Muted = "#98989D", Border = "#48484A",
            Chip = "#1C3A5F", Selection = "#007AFF14", Radius = FileRadarChrome.RadiusCard
        }
    };
}

public sealed class ThemeSettings
{
    /// <summary>Locked to Modern — ForkLift dual-pane power-tool calm.</summary>
    public AppLook Look { get; set; } = AppLook.Modern;
    /// <summary>Dark by default (restrained materials).</summary>
    public AppearanceMode Appearance { get; set; } = AppearanceMode.Dark;
    /// <summary>List first-class; grid secondary (orthodox FM density).</summary>
    public ViewMode ViewMode { get; set; } = ViewMode.List;
    /// <summary>Dual-pane is the launch default (ForkLift-first).</summary>
    public bool DualPane { get; set; } = true;
    public bool PreferCopyOnDrop { get; set; } = true;
    /// <summary>Inspector optional — off by default, not a Home preview wall.</summary>
    public bool InspectorOpen { get; set; }

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
