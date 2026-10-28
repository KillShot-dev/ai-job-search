using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace FileRadar.Services;

/// <summary>Path Finder–style temporary holding tray. Session-only.</summary>
public sealed class DropStackService : INotifyPropertyChanged
{
    public ObservableCollection<string> Paths { get; } = [];

    public int Count => Paths.Count;

    public void Add(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        if (!File.Exists(path) && !Directory.Exists(path)) return;
        if (Paths.Contains(path, StringComparer.OrdinalIgnoreCase)) return;
        Paths.Add(path);
        OnPropertyChanged(nameof(Count));
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void AddRange(IEnumerable<string> paths)
    {
        foreach (var p in paths) Add(p);
    }

    public void Remove(string path)
    {
        var hit = Paths.FirstOrDefault(p => string.Equals(p, path, StringComparison.OrdinalIgnoreCase));
        if (hit is null) return;
        Paths.Remove(hit);
        OnPropertyChanged(nameof(Count));
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Clear()
    {
        Paths.Clear();
        OnPropertyChanged(nameof(Count));
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? Changed;

    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
