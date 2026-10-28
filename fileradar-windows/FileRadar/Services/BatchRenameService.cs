using System.Text.RegularExpressions;
using FileRadar.Models;

namespace FileRadar.Services;

public static class BatchRenameService
{
    public static string? Sanitize(string name)
    {
        var cleaned = name.Replace('/', '-').Replace('\\', '-')
            .Trim().TrimEnd('.');
        foreach (var c in Path.GetInvalidFileNameChars())
            cleaned = cleaned.Replace(c, '-');
        if (string.IsNullOrWhiteSpace(cleaned) || cleaned is "." or "..") return null;
        return cleaned;
    }

    /// <summary>
    /// Pattern tokens: {name}, {n}, {date}. Optional regex: /find/replace/ on the base name
    /// when pattern starts with "re:" (e.g. re:photo_(\d+)|img_$1).
    /// </summary>
    public static IReadOnlyList<(FileItem File, string NewName)> Preview(
        IReadOnlyList<FileItem> files, string pattern)
    {
        pattern ??= "{name}-{n}";
        var list = new List<(FileItem, string)>();
        for (var i = 0; i < files.Count; i++)
        {
            var file = files[i];
            var baseName = Path.GetFileNameWithoutExtension(file.Name);
            var ext = file.Extension;
            string next;
            if (pattern.StartsWith("re:", StringComparison.OrdinalIgnoreCase))
            {
                next = ApplyRegex(baseName, pattern[3..]) + ext;
            }
            else
            {
                var date = file.ModifiedUtc.ToLocalTime().ToString("yyyy-MM-dd");
                next = pattern
                    .Replace("{name}", baseName, StringComparison.OrdinalIgnoreCase)
                    .Replace("{n}", (i + 1).ToString(), StringComparison.OrdinalIgnoreCase)
                    .Replace("{date}", date, StringComparison.OrdinalIgnoreCase);
                if (!string.IsNullOrEmpty(ext) &&
                    !next.EndsWith(ext, StringComparison.OrdinalIgnoreCase))
                    next += ext;
            }
            list.Add((file, Sanitize(next) ?? file.Name));
        }
        return list;
    }

    private static string ApplyRegex(string input, string spec)
    {
        // find|replace — practical Bloom-style regex rename
        var parts = spec.Split('|', 2);
        if (parts.Length != 2) return input;
        try
        {
            return Regex.Replace(input, parts[0], parts[1]);
        }
        catch
        {
            return input;
        }
    }

    public static IReadOnlyList<FileItem> Apply(IReadOnlyList<(FileItem File, string NewName)> plan)
    {
        var failed = new List<FileItem>();
        foreach (var (file, newName) in plan)
        {
            var clean = Sanitize(newName);
            if (clean is null) { failed.Add(file); continue; }
            var parent = Path.GetDirectoryName(file.Path);
            if (parent is null) { failed.Add(file); continue; }
            var dest = Path.Combine(parent, clean);
            if (File.Exists(dest) || Directory.Exists(dest)) { failed.Add(file); continue; }
            try
            {
                if (file.IsDirectory) Directory.Move(file.Path, dest);
                else File.Move(file.Path, dest);
            }
            catch { failed.Add(file); }
        }
        return failed;
    }
}
