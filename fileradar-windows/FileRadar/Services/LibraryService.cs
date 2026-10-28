using FileRadar.Models;

namespace FileRadar.Services;

public sealed class LibraryService
{
    public string HomeRoot { get; private set; } =
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    public string CurrentPath { get; private set; } =
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    public string SecondaryPath { get; private set; } =
        Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);

    public IReadOnlyList<string> QuickPlaces { get; } =
    [
        Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
        Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
        Environment.GetFolderPath(Environment.SpecialFolder.MyPictures),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) + @"\Downloads",
        Environment.GetFolderPath(Environment.SpecialFolder.MyMusic),
        Environment.GetFolderPath(Environment.SpecialFolder.MyVideos),
    ];

    public void Navigate(string path)
    {
        if (Directory.Exists(path))
            CurrentPath = path;
    }

    public void NavigateSecondary(string path)
    {
        if (Directory.Exists(path))
            SecondaryPath = path;
    }

    public IReadOnlyList<FileItem> ListDirectory(string path, int max = 500)
    {
        var list = new List<FileItem>();
        try
        {
            var di = new DirectoryInfo(path);
            foreach (var d in di.EnumerateDirectories().Take(max))
            {
                try
                {
                    list.Add(new FileItem
                    {
                        Path = d.FullName,
                        Name = d.Name,
                        IsDirectory = true,
                        SizeBytes = 0,
                        ModifiedUtc = d.LastWriteTimeUtc,
                        Kind = FileKind.Folder,
                        Extension = ""
                    });
                }
                catch { /* skip inaccessible */ }
            }

            foreach (var f in di.EnumerateFiles().Take(Math.Max(0, max - list.Count)))
            {
                try
                {
                    list.Add(new FileItem
                    {
                        Path = f.FullName,
                        Name = f.Name,
                        IsDirectory = false,
                        SizeBytes = f.Length,
                        ModifiedUtc = f.LastWriteTimeUtc,
                        Kind = FileItem.Classify(f.FullName, false),
                        Extension = f.Extension
                    });
                }
                catch { /* skip */ }
            }
        }
        catch
        {
            return Array.Empty<FileItem>();
        }

        return list
            .OrderByDescending(i => i.IsDirectory)
            .ThenBy(i => i.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public IReadOnlyList<string> FavoritePlaces { get; } =
    [
        Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) + @"\Downloads",
        Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
    ];

    public IReadOnlyList<FileItem> GatherLibraryFiles(int perRoot = 100)
    {
        var roots = QuickPlaces.Where(Directory.Exists).Take(5).ToList();
        var all = new List<FileItem>();
        foreach (var root in roots)
            all.AddRange(ListDirectory(root, perRoot).Where(i => !i.IsDirectory));
        return all;
    }

    public IReadOnlyList<FileItem> BuildRecents(int max = 24)
        => GatherLibraryFiles()
            .OrderByDescending(i => i.ModifiedUtc)
            .Take(max)
            .ToList();

    /// <summary>Showcase album shelves — kind groups with cover images (mockup).</summary>
    public IReadOnlyList<ShelfAlbum> BuildAlbumShelves()
    {
        var all = GatherLibraryFiles();
        var albums = new List<ShelfAlbum>();

        foreach (var kind in new[] { FileKind.Images, FileKind.Documents, FileKind.Videos, FileKind.Music, FileKind.Archives })
        {
            var items = all.Where(i => i.Kind == kind)
                .OrderByDescending(i => i.ModifiedUtc)
                .Take(40)
                .ToList();
            if (items.Count == 0) continue;
            var cover = items.FirstOrDefault(i => i.CanThumbnail) ?? items[0];
            albums.Add(new ShelfAlbum
            {
                Id = $"kind-{kind}",
                Title = kind switch
                {
                    FileKind.Images => "Images",
                    FileKind.Documents => "Documents",
                    FileKind.Videos => "Videos",
                    FileKind.Music => "Music",
                    FileKind.Archives => "Archives",
                    _ => kind.ToString()
                },
                Subtitle = $"{items.Count} file{(items.Count == 1 ? "" : "s")}",
                Cover = cover,
                Kind = kind,
                Items = items
            });
        }

        // Smart-ish collections from filenames
        AddSmart(albums, all, "Screenshots", i =>
            i.Name.Contains("screenshot", StringComparison.OrdinalIgnoreCase)
            || i.Name.StartsWith("Screen Shot", StringComparison.OrdinalIgnoreCase));
        AddSmart(albums, all, "Large files", i => i.SizeBytes >= 50L * 1024 * 1024);
        AddSmart(albums, all, "PDFs", i => i.Extension.Equals(".pdf", StringComparison.OrdinalIgnoreCase));

        return albums;
    }

    private static void AddSmart(List<ShelfAlbum> albums, IReadOnlyList<FileItem> all, string title, Func<FileItem, bool> pred)
    {
        var items = all.Where(pred).OrderByDescending(i => i.ModifiedUtc).Take(40).ToList();
        if (items.Count == 0) return;
        albums.Add(new ShelfAlbum
        {
            Id = $"smart-{title}",
            Title = title,
            Subtitle = $"{items.Count} file{(items.Count == 1 ? "" : "s")}",
            Cover = items.FirstOrDefault(i => i.CanThumbnail) ?? items[0],
            Kind = items[0].Kind,
            Items = items
        });
    }

    public IReadOnlyList<ShelfGroup> BuildHomeShelves()
    {
        // Legacy helper — prefer BuildAlbumShelves + BuildRecents for Showcase Home.
        var albums = BuildAlbumShelves();
        var list = new List<ShelfGroup>
        {
            new() { Title = "Recents", Kind = FileKind.Other, Items = BuildRecents() }
        };
        list.AddRange(albums.Select(a => new ShelfGroup { Title = a.Title, Kind = a.Kind, Items = a.Items }));
        return list;
    }

    public (string Name, long Free, long Total) GetSystemDriveInfo()
    {
        try
        {
            var root = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)) ?? "C:\\";
            var drive = new DriveInfo(root);
            var name = string.IsNullOrWhiteSpace(drive.VolumeLabel) ? $"Local Disk ({drive.Name.TrimEnd('\\')})" : drive.VolumeLabel;
            return (name, drive.AvailableFreeSpace, drive.TotalSize);
        }
        catch
        {
            return ("Disk", 0, 0);
        }
    }

    public IReadOnlyList<FileItem> Search(string query, int max = 200)
    {
        if (string.IsNullOrWhiteSpace(query))
            return Array.Empty<FileItem>();

        var q = query.Trim();
        var results = new List<FileItem>();
        var roots = QuickPlaces.Where(Directory.Exists).ToList();
        if (Directory.Exists(CurrentPath) && !roots.Contains(CurrentPath))
            roots.Insert(0, CurrentPath);

        foreach (var root in roots)
        {
            if (results.Count >= max) break;
            SearchLevel(root, q, results, max, depth: 0, maxDepth: 2);
        }

        return results;
    }

    private static void SearchLevel(string dir, string q, List<FileItem> results, int max, int depth, int maxDepth)
    {
        if (results.Count >= max || depth > maxDepth) return;
        IEnumerable<string> entries;
        try { entries = Directory.EnumerateFileSystemEntries(dir); }
        catch { return; }

        foreach (var path in entries)
        {
            if (results.Count >= max) return;
            var name = Path.GetFileName(path);
            var isDir = Directory.Exists(path);
            if (name.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                try
                {
                    if (isDir)
                    {
                        var d = new DirectoryInfo(path);
                        results.Add(new FileItem
                        {
                            Path = d.FullName,
                            Name = d.Name,
                            IsDirectory = true,
                            ModifiedUtc = d.LastWriteTimeUtc,
                            Kind = FileKind.Folder
                        });
                    }
                    else
                    {
                        var f = new FileInfo(path);
                        results.Add(new FileItem
                        {
                            Path = f.FullName,
                            Name = f.Name,
                            IsDirectory = false,
                            SizeBytes = f.Length,
                            ModifiedUtc = f.LastWriteTimeUtc,
                            Kind = FileItem.Classify(f.FullName, false),
                            Extension = f.Extension
                        });
                    }
                }
                catch { /* skip */ }
            }

            if (isDir && depth < maxDepth)
                SearchLevel(path, q, results, max, depth + 1, maxDepth);
        }
    }

    public IReadOnlyList<FileItem> CleanupCandidates(int max = 100)
    {
        var downloads = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        if (!Directory.Exists(downloads))
            return Array.Empty<FileItem>();

        return ListDirectory(downloads, 400)
            .Where(i => !i.IsDirectory)
            .OrderByDescending(i => i.SizeBytes)
            .Take(max)
            .ToList();
    }

    public IReadOnlyList<DuplicateGroup> FindDuplicates(int maxGroups = 40)
    {
        var pics = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        var downloads = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        var files = new List<FileItem>();
        foreach (var root in new[] { pics, downloads }.Where(Directory.Exists))
            files.AddRange(ListDirectory(root, 300).Where(i => !i.IsDirectory && i.SizeBytes > 0));

        return files
            .GroupBy(f => $"{f.Name.ToLowerInvariant()}|{f.SizeBytes}")
            .Where(g => g.Count() > 1)
            .Take(maxGroups)
            .Select(g => new DuplicateGroup
            {
                Key = g.Key,
                Items = g.ToList()
            })
            .ToList();
    }

    public IReadOnlyList<(string Day, IReadOnlyList<FileItem> Items)> Timeline(int days = 14)
    {
        var all = new List<FileItem>();
        foreach (var root in QuickPlaces.Where(Directory.Exists).Take(3))
            all.AddRange(ListDirectory(root, 120).Where(i => !i.IsDirectory));

        var cutoff = DateTime.UtcNow.Date.AddDays(-days);
        return all
            .Where(i => i.ModifiedUtc >= cutoff)
            .GroupBy(i => i.ModifiedUtc.ToLocalTime().Date)
            .OrderByDescending(g => g.Key)
            .Select(g => (
                g.Key.ToString("dddd, MMM d"),
                (IReadOnlyList<FileItem>)g.OrderByDescending(i => i.ModifiedUtc).ToList()))
            .ToList();
    }

    public IReadOnlyList<FileItem> ListRecycleBin(int max = 100)
    {
        // Shell recycle bin enumeration needs COM; show recent deleted via known folder fallback message list.
        // Use a lightweight local "FileRadar Trash" staging folder for undoable deletes.
        var stage = StagingTrashPath;
        Directory.CreateDirectory(stage);
        return ListDirectory(stage, max);
    }

    public string StagingTrashPath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "FileRadar", "Trash");

    public void MoveToTrash(IEnumerable<FileItem> items)
    {
        Directory.CreateDirectory(StagingTrashPath);
        foreach (var item in items)
        {
            try
            {
                var dest = Path.Combine(StagingTrashPath, item.Name);
                if (File.Exists(dest) || Directory.Exists(dest))
                    dest = Path.Combine(StagingTrashPath, $"{Path.GetFileNameWithoutExtension(item.Name)}_{DateTime.Now:HHmmss}{item.Extension}");

                if (item.IsDirectory)
                    Directory.Move(item.Path, dest);
                else
                    File.Move(item.Path, dest);
            }
            catch { /* keep going */ }
        }
    }

    public void RestoreFromTrash(IEnumerable<FileItem> items, string restoreRoot)
    {
        Directory.CreateDirectory(restoreRoot);
        foreach (var item in items)
        {
            try
            {
                var dest = Path.Combine(restoreRoot, item.Name);
                if (item.IsDirectory)
                    Directory.Move(item.Path, dest);
                else
                    File.Move(item.Path, dest);
            }
            catch { /* skip */ }
        }
    }

    public void EmptyTrash()
    {
        if (!Directory.Exists(StagingTrashPath)) return;
        foreach (var f in Directory.EnumerateFiles(StagingTrashPath))
        {
            try { File.Delete(f); } catch { }
        }
        foreach (var d in Directory.EnumerateDirectories(StagingTrashPath))
        {
            try { Directory.Delete(d, true); } catch { }
        }
    }
}
