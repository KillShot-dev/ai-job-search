using System.Text.Json;

namespace FileRadar.Services;

public sealed class SavedWorkspace
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string CurrentPath { get; set; } = "";
    public string SecondaryPath { get; set; } = "";
    public bool DualPane { get; set; }
    public bool InspectorOpen { get; set; } = true;
}

/// <summary>QSpace / Bloom layout restore — paths + pane flags only, never moves files.</summary>
public sealed class WorkspaceStore
{
    private readonly string _path;
    private List<SavedWorkspace> _items = [];

    public WorkspaceStore()
    {
        _path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "FileRadar", "workspaces.json");
        Load();
    }

    public IReadOnlyList<SavedWorkspace> Workspaces => _items;

    public void Save(string name, string current, string secondary, bool dual, bool inspector)
    {
        var trimmed = name.Trim();
        if (string.IsNullOrEmpty(trimmed)) return;
        _items.RemoveAll(w => string.Equals(w.Name, trimmed, StringComparison.OrdinalIgnoreCase));
        _items.Add(new SavedWorkspace
        {
            Name = trimmed,
            CurrentPath = current,
            SecondaryPath = secondary,
            DualPane = dual,
            InspectorOpen = inspector
        });
        Persist();
    }

    public void Delete(Guid id)
    {
        _items.RemoveAll(w => w.Id == id);
        Persist();
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(_path)) return;
            var json = File.ReadAllText(_path);
            _items = JsonSerializer.Deserialize<List<SavedWorkspace>>(json) ?? [];
        }
        catch { _items = []; }
    }

    private void Persist()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            File.WriteAllText(_path, JsonSerializer.Serialize(_items));
        }
        catch { /* ignore */ }
    }
}
