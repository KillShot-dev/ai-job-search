using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace FileRadar;

public partial class App : Application
{
    private Window? _window;
    public static Window? MainWindow { get; private set; }
    public static Models.ThemeSettings Theme { get; } = new();
    public static Services.LibraryService Library { get; } = new();

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            e.Handled = true;
            System.Diagnostics.Debug.WriteLine(e.Message);
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new Window
        {
            Title = "FileRadar"
        };
        MainWindow = _window;

        var root = new Views.MainPage();
        _window.Content = root;

        _window.AppWindow.Resize(new Windows.Graphics.SizeInt32(1440, 900));
        _window.Activate();
    }

    public static void ApplyThemeResources(ResourceDictionary resources, Models.ThemePalette palette)
    {
        static Color Parse(string hex)
        {
            hex = hex.TrimStart('#');
            byte a = 255;
            if (hex.Length == 8)
            {
                a = Convert.ToByte(hex[..2], 16);
                hex = hex[2..];
            }
            var r = Convert.ToByte(hex[..2], 16);
            var g = Convert.ToByte(hex[2..4], 16);
            var b = Convert.ToByte(hex[4..6], 16);
            return Color.FromArgb(a, r, g, b);
        }

        void SetColor(string key, string hex)
        {
            var c = Parse(hex);
            resources[key + "Color"] = c;
            resources[key + "Brush"] = new SolidColorBrush(c);
        }

        SetColor("FrAccent", palette.Accent);
        SetColor("FrBg", palette.Bg);
        SetColor("FrPanel", palette.Panel);
        SetColor("FrPanel2", palette.Panel2);
        SetColor("FrText", palette.Text);
        SetColor("FrMuted", palette.Muted);
        SetColor("FrBorder", palette.Border);
        SetColor("FrChip", palette.Chip);
        resources["FrRadius"] = palette.Radius;
    }
}
