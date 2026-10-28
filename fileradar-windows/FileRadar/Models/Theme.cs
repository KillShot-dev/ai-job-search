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

/// <summary>Cross-platform chrome view IDs — must match Mac string IDs exactly.</summary>
public static class ChromeViewIds
{
    public const string RadarGlass = "radarGlass";
    public const string PreviewTheater = "previewTheater";
    public const string CommandRail = "commandRail";
    public const string WorkspaceTabs = "workspaceTabs";

    public static readonly string[] All =
    [
        RadarGlass,
        PreviewTheater,
        CommandRail,
        WorkspaceTabs
    ];

    public static string DisplayName(string id) => id switch
    {
        RadarGlass => "Radar Glass",
        PreviewTheater => "Preview Theater",
        CommandRail => "Command Rail",
        WorkspaceTabs => "Workspace Tabs",
        _ => id
    };

    public static string Normalize(string? id)
    {
        if (string.IsNullOrWhiteSpace(id)) return RadarGlass;
        foreach (var known in All)
        {
            if (string.Equals(known, id, StringComparison.OrdinalIgnoreCase))
                return known;
        }
        return RadarGlass;
    }

    public static string Next(string id)
    {
        var cur = Normalize(id);
        var i = Array.IndexOf(All, cur);
        return All[(i + 1) % All.Length];
    }
}

/// <summary>Cross-platform FileRadarChrome tokens — dual-pane chrome + view accents.</summary>
public static class FileRadarChrome
{
    public const string Accent = "#007AFF";
    public const string AccentTeal = "#14B8A6";
    public const string AccentAmber = "#F5A524";
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
    public const double CommandRailWidth = 64;
    public const double QueueWidth = 280;
    public const double PreviewWidth = 320;
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
    public static string AccentForChrome(string chromeId) => ChromeViewIds.Normalize(chromeId) switch
    {
        ChromeViewIds.CommandRail => FileRadarChrome.AccentTeal,
        ChromeViewIds.WorkspaceTabs => FileRadarChrome.AccentAmber,
        _ => FileRadarChrome.Accent
    };

    public static ThemePalette Resolve(AppLook look, bool dark, string? chromeId = null)
    {
        var chrome = ChromeViewIds.Normalize(chromeId);
        // Preview Theater: calmer light-capable chrome (mockup B).
        if (chrome == ChromeViewIds.PreviewTheater)
            dark = false;

        var accent = AccentForChrome(chrome);
        var accent2 = chrome switch
        {
            ChromeViewIds.CommandRail => "#5EEAD4",
            ChromeViewIds.WorkspaceTabs => "#FCD34D",
            _ => dark ? "#64D2FF" : "#5AC8FA"
        };

        if (!dark)
        {
            return new ThemePalette
            {
                Accent = accent, Accent2 = accent2,
                Bg = "#E8E8ED", Panel = "#F5F5F7",
                Panel2 = "#FFFFFF", Text = "#1D1D1F", Muted = "#6E6E73", Border = "#D2D2D7",
                Chip = chrome == ChromeViewIds.WorkspaceTabs ? "#FFF4D6" :
                       chrome == ChromeViewIds.CommandRail ? "#D5F5F0" : "#E5F0FF",
                Selection = accent + "14",
                Radius = FileRadarChrome.RadiusCard
            };
        }

        return new ThemePalette
        {
            Accent = accent, Accent2 = accent2,
            Bg = "#1C1C1E", Panel = "#2C2C2E",
            Panel2 = "#3A3A3C", Text = "#F5F5F7", Muted = "#98989D", Border = "#48484A",
            Chip = chrome == ChromeViewIds.WorkspaceTabs ? "#3A2E14" :
                   chrome == ChromeViewIds.CommandRail ? "#12352F" : "#1C3A5F",
            Selection = accent + "14",
            Radius = FileRadarChrome.RadiusCard
        };
    }
}

public sealed class ThemeSettings
{
    /// <summary>Locked to Modern — dual-pane power-tool calm.</summary>
    public AppLook Look { get; set; } = AppLook.Modern;
    /// <summary>Dark by default (restrained materials).</summary>
    public AppearanceMode Appearance { get; set; } = AppearanceMode.Dark;
    /// <summary>List first-class; grid secondary (orthodox FM density).</summary>
    public ViewMode ViewMode { get; set; } = ViewMode.List;
    /// <summary>Dual-pane is the launch default.</summary>
    public bool DualPane { get; set; } = true;
    public bool PreferCopyOnDrop { get; set; } = true;
    /// <summary>Inspector optional — forced on for Preview Theater.</summary>
    public bool InspectorOpen { get; set; }
    /// <summary>Persisted chrome view ID (radarGlass / previewTheater / commandRail / workspaceTabs).</summary>
    public string ChromeView { get; set; } = ChromeViewIds.RadarGlass;

    public bool IsDark(bool systemDark)
    {
        if (ChromeViewIds.Normalize(ChromeView) == ChromeViewIds.PreviewTheater)
            return false;
        return Appearance switch
        {
            AppearanceMode.Light => false,
            AppearanceMode.Dark => true,
            _ => systemDark
        };
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

    public void CycleChrome()
    {
        ChromeView = ChromeViewIds.Next(ChromeView);
    }

    public void SetChrome(string id)
    {
        ChromeView = ChromeViewIds.Normalize(id);
    }
}
