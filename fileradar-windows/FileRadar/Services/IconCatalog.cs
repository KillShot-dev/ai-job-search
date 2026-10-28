using FileRadar.Models;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

namespace FileRadar.Services;

/// <summary>
/// FileRadar icon system (Windows) — rich PNG badges with depth/gradients.
/// Keys parallel the Mac icon system (docs/fileradar-icon-system.md).
/// </summary>
public static class IconCatalog
{
    private static readonly Dictionary<string, BitmapImage> Cache = new(StringComparer.OrdinalIgnoreCase);

    public static Image Make(string key, double size)
    {
        var img = new Image
        {
            Source = Get(key),
            Width = size,
            Height = size,
            Stretch = Stretch.Uniform,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center
        };
        return img;
    }

    public static BitmapImage Get(string key)
    {
        key = Normalize(key);
        if (Cache.TryGetValue(key, out var cached)) return cached;
        var bmp = new BitmapImage();
        var path = ResolvePath(key);
        bmp.UriSource = new Uri(path, UriKind.Absolute);
        Cache[key] = bmp;
        return bmp;
    }

    public static string ForFileKind(FileKind kind, string? chromeId = null) => kind switch
    {
        FileKind.Folder => FolderKey(chromeId),
        FileKind.Images => "image",
        FileKind.Videos => "video",
        FileKind.Music => "music",
        FileKind.Documents => "document",
        FileKind.Archives => "archive",
        FileKind.Apps => "app",
        _ => "file"
    };

    public static string ForExtension(string extension)
    {
        var ext = extension.ToLowerInvariant();
        return ext switch
        {
            ".pdf" => "pdf",
            ".cs" or ".ts" or ".js" or ".py" or ".rs" or ".go" or ".java" or ".cpp" or ".h" or ".json" or ".xml" or ".yml" or ".yaml"
                => "code",
            _ => "file"
        };
    }

    public static string ForFileItem(FileItem item, string? chromeId = null)
    {
        if (item.IsDirectory) return FolderKey(chromeId);
        if (item.Kind is FileKind.Images or FileKind.Videos or FileKind.Music
            or FileKind.Archives or FileKind.Apps)
            return ForFileKind(item.Kind, chromeId);
        var byExt = ForExtension(item.Extension);
        if (byExt is not "file") return byExt;
        return item.Kind == FileKind.Documents ? "document" : "file";
    }

    public static string ForPlace(string path)
    {
        var name = Path.GetFileName(path.TrimEnd('\\', '/')).ToLowerInvariant();
        var full = path.Replace('/', '\\');
        if (full.Contains("Desktop", StringComparison.OrdinalIgnoreCase)) return "desktop";
        if (full.Contains("Downloads", StringComparison.OrdinalIgnoreCase)) return "downloads";
        if (full.Contains("Documents", StringComparison.OrdinalIgnoreCase)) return "documents";
        if (full.Contains("Pictures", StringComparison.OrdinalIgnoreCase)) return "pictures";
        if (full.Contains("Music", StringComparison.OrdinalIgnoreCase)) return "music-place";
        if (full.Contains("Videos", StringComparison.OrdinalIgnoreCase)) return "videos-place";
        return name switch
        {
            "desktop" => "desktop",
            "downloads" => "downloads",
            "documents" => "documents",
            "pictures" => "pictures",
            "music" => "music-place",
            "videos" => "videos-place",
            _ => "folder"
        };
    }

    public static string ForDestination(Destination dest) => dest switch
    {
        Destination.Home or Destination.Browse => "home",
        Destination.Shelves => "shelves",
        Destination.Search => "search",
        Destination.Cleanup => "cleanup",
        Destination.Duplicates => "duplicates",
        Destination.Timeline => "timeline",
        Destination.Workspaces => "workspaces",
        Destination.RecycleBin => "recycle",
        _ => "folder"
    };

    public static string ForChrome(string chromeId) => ChromeViewIds.Normalize(chromeId) switch
    {
        ChromeViewIds.RadarGlass => "chrome-radar",
        ChromeViewIds.PreviewTheater => "chrome-preview",
        ChromeViewIds.CommandRail => "chrome-rail",
        ChromeViewIds.WorkspaceTabs => "chrome-tabs",
        _ => "chrome"
    };

    public static string FolderKeySafe(string? chromeId) => ChromeViewIds.Normalize(chromeId) switch
    {
        ChromeViewIds.CommandRail => "folder-teal",
        ChromeViewIds.WorkspaceTabs => "folder-amber",
        _ => "folder"
    };

    private static string FolderKey(string? chromeId) => FolderKeySafe(chromeId);

    private static string Normalize(string key) => key.Trim().ToLowerInvariant();

    private static string ResolvePath(string key)
    {
        var file = Path.Combine(AppContext.BaseDirectory, "Assets", "Icons", key + ".png");
        if (File.Exists(file)) return file;
        var fallback = Path.Combine(AppContext.BaseDirectory, "Assets", "Icons", "file.png");
        return File.Exists(fallback) ? fallback : file;
    }
}
