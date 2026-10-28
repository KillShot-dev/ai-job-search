using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace FileRadar.Services;

public enum TransferStatus
{
    Queued,
    Working,
    Done,
    Cancelled,
    Failed
}

public sealed class TransferItem : INotifyPropertyChanged
{
    private TransferStatus _status = TransferStatus.Queued;
    private int _completedFiles;
    private string? _error;

    public Guid Id { get; } = Guid.NewGuid();
    public required IReadOnlyList<string> Sources { get; init; }
    public required string DestinationFolder { get; init; }
    public required bool IsMove { get; init; }

    public string Title =>
        $"{(IsMove ? "Moving" : "Copying")} {Sources.Count} item{(Sources.Count == 1 ? "" : "s")}";

    public TransferStatus Status
    {
        get => _status;
        set { if (_status == value) return; _status = value; OnPropertyChanged(); OnPropertyChanged(nameof(Progress)); }
    }

    public int CompletedFiles
    {
        get => _completedFiles;
        set { if (_completedFiles == value) return; _completedFiles = value; OnPropertyChanged(); OnPropertyChanged(nameof(Progress)); }
    }

    public string? Error
    {
        get => _error;
        set { if (_error == value) return; _error = value; OnPropertyChanged(); }
    }

    public double Progress => Sources.Count == 0 ? 1 : (double)CompletedFiles / Sources.Count;

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>ForkLift-style visible transfer queue — pause/resume/cancel between files.</summary>
public sealed class TransferQueue : INotifyPropertyChanged
{
    private bool _isPaused;
    private bool _processing;
    private bool _cancelRequested;

    public ObservableCollection<TransferItem> Items { get; } = [];

    public bool IsPaused
    {
        get => _isPaused;
        set { if (_isPaused == value) return; _isPaused = value; OnPropertyChanged(); RaiseHud(); }
    }

    public int ActiveCount => Items.Count(i => i.Status is TransferStatus.Queued or TransferStatus.Working);

    public bool HudVisible => ActiveCount > 0 || Items.Any(i => i.Status == TransferStatus.Failed);

    public double AggregateProgress
    {
        get
        {
            var active = Items.Where(i => i.Status is TransferStatus.Working or TransferStatus.Queued).ToList();
            if (active.Count == 0)
                return Items.FirstOrDefault(i => i.Status == TransferStatus.Failed)?.Progress ?? 0;
            return active.Average(i => i.Progress);
        }
    }

    public string HudHeadline
    {
        get
        {
            var n = Math.Max(ActiveCount, 1);
            if (IsPaused) return $"Paused · {n} item{(n == 1 ? "" : "s")}";
            var verb = Items.Any(i => !i.IsMove && i.Status is TransferStatus.Working or TransferStatus.Queued)
                ? "Copying" : "Moving";
            return $"{verb} {n} item{(n == 1 ? "" : "s")}";
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? Changed;

    public void EnqueueCopy(IEnumerable<string> paths, string folder)
        => Enqueue(paths, folder, isMove: false);

    public void EnqueueMove(IEnumerable<string> paths, string folder)
        => Enqueue(paths, folder, isMove: true);

    /// <summary>Demo job for capture / HUD preview — no real file IO.</summary>
    public void EnqueueDemo(string label = "Showcase capture", int fileCount = 2)
    {
        var sources = Enumerable.Range(1, Math.Max(1, fileCount))
            .Select(i => Path.Combine(Path.GetTempPath(), $"fileradar-demo-{i}.tmp"))
            .ToList();
        var item = new TransferItem
        {
            Sources = sources,
            DestinationFolder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"),
            IsMove = false,
            Status = TransferStatus.Working,
            CompletedFiles = 0
        };
        // Override title feel via a synthetic working item
        Items.Insert(0, item);
        RaiseHud();
        _ = RunDemoAsync(item);
    }

    private async Task RunDemoAsync(TransferItem item)
    {
        for (var i = 1; i <= item.Sources.Count; i++)
        {
            while (IsPaused) await Task.Delay(200);
            if (_cancelRequested) { item.Status = TransferStatus.Cancelled; RaiseHud(); return; }
            await Task.Delay(900);
            item.CompletedFiles = i;
            RaiseHud();
        }
        item.Status = TransferStatus.Done;
        RaiseHud();
    }

    private void Enqueue(IEnumerable<string> paths, string folder, bool isMove)
    {
        var list = paths.Where(p => File.Exists(p) || Directory.Exists(p)).ToList();
        if (list.Count == 0 || !Directory.Exists(folder)) return;
        Items.Add(new TransferItem
        {
            Sources = list,
            DestinationFolder = folder,
            IsMove = isMove
        });
        RaiseHud();
        Process();
    }

    public void CancelAll()
    {
        _cancelRequested = true;
        foreach (var item in Items.Where(i => i.Status == TransferStatus.Queued))
            item.Status = TransferStatus.Cancelled;
        RaiseHud();
    }

    public void CancelItem(Guid id)
    {
        var item = Items.FirstOrDefault(i => i.Id == id);
        if (item is null) return;
        if (item.Status == TransferStatus.Queued)
            item.Status = TransferStatus.Cancelled;
        else if (item.Status == TransferStatus.Working)
            _cancelRequested = true;
        RaiseHud();
    }

    public void ClearFinished()
    {
        for (var i = Items.Count - 1; i >= 0; i--)
        {
            if (Items[i].Status is TransferStatus.Done or TransferStatus.Cancelled or TransferStatus.Failed)
                Items.RemoveAt(i);
        }
        RaiseHud();
    }

    private void Process()
    {
        if (_processing) return;
        _processing = true;
        _cancelRequested = false;
        _ = Task.Run(async () =>
        {
            while (true)
            {
                var item = Items.FirstOrDefault(i => i.Status == TransferStatus.Queued);
                if (item is null) break;
                if (_cancelRequested) break;
                while (IsPaused) await Task.Delay(200);
                if (_cancelRequested) break;
                await RunItemAsync(item);
            }
            _processing = false;
            RaiseHud();
        });
    }

    private async Task RunItemAsync(TransferItem item)
    {
        item.Status = TransferStatus.Working;
        RaiseHud();
        string? firstError = null;
        var completed = 0;
        foreach (var source in item.Sources)
        {
            if (_cancelRequested) break;
            while (IsPaused) await Task.Delay(200);
            var dest = Path.Combine(item.DestinationFolder, Path.GetFileName(source));
            var err = await Task.Run(() =>
            {
                try
                {
                    if (File.Exists(dest) || Directory.Exists(dest))
                        return $"Skipped {Path.GetFileName(source)}: name already exists.";
                    if (Directory.Exists(source))
                    {
                        if (item.IsMove) Directory.Move(source, dest);
                        else CopyDirectory(source, dest);
                    }
                    else
                    {
                        if (item.IsMove) File.Move(source, dest);
                        else File.Copy(source, dest);
                    }
                    return null;
                }
                catch (Exception ex)
                {
                    return $"Could not {(item.IsMove ? "move" : "copy")} {Path.GetFileName(source)}: {ex.Message}";
                }
            });
            if (err is not null && firstError is null) firstError = err;
            completed++;
            item.CompletedFiles = completed;
            RaiseHud();
        }

        if (_cancelRequested) item.Status = TransferStatus.Cancelled;
        else if (firstError is not null)
        {
            item.Status = TransferStatus.Failed;
            item.Error = firstError;
        }
        else item.Status = TransferStatus.Done;
        RaiseHud();
    }

    private static void CopyDirectory(string source, string dest)
    {
        Directory.CreateDirectory(dest);
        foreach (var file in Directory.EnumerateFiles(source))
            File.Copy(file, Path.Combine(dest, Path.GetFileName(file)));
        foreach (var dir in Directory.EnumerateDirectories(source))
            CopyDirectory(dir, Path.Combine(dest, Path.GetFileName(dir)));
    }

    private void RaiseHud()
    {
        OnPropertyChanged(nameof(ActiveCount));
        OnPropertyChanged(nameof(HudVisible));
        OnPropertyChanged(nameof(AggregateProgress));
        OnPropertyChanged(nameof(HudHeadline));
        OnPropertyChanged(nameof(IsPaused));
        Changed?.Invoke(this, EventArgs.Empty);
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
