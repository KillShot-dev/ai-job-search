using System.Globalization;

namespace FileRadar.Models;

public enum FileKind
{
    Folder,
    Images,
    Videos,
    Music,
    Documents,
    Archives,
    Apps,
    Other
}

public enum Destination
{
    Home,
    Search,
    Cleanup,
    Duplicates,
    Timeline,
    RecycleBin,
    Workspaces,
    Browse
}

public sealed class FileItem
{
    public required string Path { get; init; }
    public required string Name { get; init; }
    public required bool IsDirectory { get; init; }
    public long SizeBytes { get; init; }
    public DateTime ModifiedUtc { get; init; }
    public FileKind Kind { get; init; }
    public string Extension { get; init; } = "";
    public bool IsSelected { get; set; }
    public int? Width { get; set; }
    public int? Height { get; set; }

    public string SizeLabel => IsDirectory
        ? "Folder"
        : FormatBytes(SizeBytes);

    public string ModifiedLabel => ModifiedUtc.ToLocalTime()
        .ToString("g", CultureInfo.CurrentCulture);

    public string RelativeTimeLabel
    {
        get
        {
            var local = ModifiedUtc.ToLocalTime();
            var now = DateTime.Now;
            var datePart = local.Date == now.Date
                ? "Today"
                : local.Date == now.Date.AddDays(-1)
                    ? "Yesterday"
                    : local.ToString("MMM d", CultureInfo.CurrentCulture);
            return $"{datePart}, {local:h:mm tt}";
        }
    }

    public string KindDisplayName => Kind switch
    {
        FileKind.Folder => "Folder",
        FileKind.Images => "Image",
        FileKind.Videos => "Video",
        FileKind.Music => "Audio",
        FileKind.Documents => "Document",
        FileKind.Archives => "Archive",
        FileKind.Apps => "App",
        _ => "File"
    };

    public string KindGlyph => Kind switch
    {
        FileKind.Folder => "\uE8B7",
        FileKind.Images => "\uE91B",
        FileKind.Videos => "\uE714",
        FileKind.Music => "\uE8D6",
        FileKind.Documents => "\uE8A5",
        FileKind.Archives => "\uE7B8",
        FileKind.Apps => "\uE71D",
        _ => "\uE8A5"
    };

    public bool CanThumbnail
    {
        get
        {
            if (IsDirectory) return false;
            var ext = Extension.ToLowerInvariant();
            return ext is ".png" or ".jpg" or ".jpeg" or ".gif" or ".webp" or ".bmp" or ".tif" or ".tiff";
        }
    }

    public static FileKind Classify(string path, bool isDir)
    {
        if (isDir) return FileKind.Folder;
        var ext = System.IO.Path.GetExtension(path).ToLowerInvariant();
        return ext switch
        {
            ".png" or ".jpg" or ".jpeg" or ".gif" or ".webp" or ".bmp" or ".heic" or ".tif" or ".tiff"
                => FileKind.Images,
            ".mp4" or ".mov" or ".mkv" or ".avi" or ".wmv" or ".webm"
                => FileKind.Videos,
            ".mp3" or ".wav" or ".flac" or ".aac" or ".m4a" or ".ogg"
                => FileKind.Music,
            ".pdf" or ".doc" or ".docx" or ".xls" or ".xlsx" or ".ppt" or ".pptx" or ".txt" or ".md" or ".rtf" or ".csv"
                => FileKind.Documents,
            ".zip" or ".7z" or ".rar" or ".tar" or ".gz" or ".iso"
                => FileKind.Archives,
            ".exe" or ".msi" or ".msix" or ".appx" or ".bat" or ".cmd" or ".ps1"
                => FileKind.Apps,
            _ => FileKind.Other
        };
    }

    public static string FormatBytes(long bytes)
    {
        if (bytes < 1024) return $"{bytes} B";
        double v = bytes;
        string[] units = ["KB", "MB", "GB", "TB"];
        foreach (var u in units)
        {
            v /= 1024.0;
            if (v < 1024) return $"{v:0.##} {u}";
        }
        return $"{v:0.##} PB";
    }
}

public sealed class ShelfAlbum
{
    public required string Id { get; init; }
    public required string Title { get; init; }
    public required string Subtitle { get; init; }
    public FileItem? Cover { get; init; }
    public required FileKind Kind { get; init; }
    public required IReadOnlyList<FileItem> Items { get; init; }
}

public sealed class ShelfGroup
{
    public required string Title { get; init; }
    public required FileKind Kind { get; init; }
    public required IReadOnlyList<FileItem> Items { get; init; }
}

public sealed class DuplicateGroup
{
    public required string Key { get; init; }
    public required IReadOnlyList<FileItem> Items { get; init; }
    public long WastedBytes => Items.Skip(1).Sum(i => i.SizeBytes);
}
