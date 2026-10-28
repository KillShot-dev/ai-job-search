using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using WinRT;

namespace FileRadar;

public partial class App : Application
{
    private Window? _window;
    private WindowsSystemDispatcherQueueHelper? _dispatcherQueueHelper;
    private MicaController? _micaController;
    private SystemBackdropConfiguration? _backdropConfig;

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

        TrySetMicaBackdrop(_window);

        _window.AppWindow.Resize(new Windows.Graphics.SizeInt32(1440, 900));
        _window.Activate();
    }

    /// <summary>Frosted system chrome — Mica when available (closest WinUI analog to macOS materials).</summary>
    private bool TrySetMicaBackdrop(Window window)
    {
        if (!MicaController.IsSupported()) return false;

        _dispatcherQueueHelper = new WindowsSystemDispatcherQueueHelper();
        _dispatcherQueueHelper.EnsureWindowsSystemDispatcherQueueController();

        _backdropConfig = new SystemBackdropConfiguration
        {
            IsInputActive = true,
            Theme = SystemBackdropTheme.Default
        };

        window.Activated += (_, args) =>
        {
            if (_backdropConfig is null) return;
            _backdropConfig.IsInputActive = args.WindowActivationState != WindowActivationState.Deactivated;
        };
        window.Closed += (_, _) =>
        {
            _micaController?.Dispose();
            _micaController = null;
            _backdropConfig = null;
        };

        if (window.Content is FrameworkElement root)
        {
            root.ActualThemeChanged += (_, _) =>
            {
                if (_backdropConfig is null) return;
                _backdropConfig.Theme = root.ActualTheme switch
                {
                    ElementTheme.Dark => SystemBackdropTheme.Dark,
                    ElementTheme.Light => SystemBackdropTheme.Light,
                    _ => SystemBackdropTheme.Default
                };
            };
        }

        _micaController = new MicaController { Kind = MicaKind.Base };
        _micaController.AddSystemBackdropTarget(window.As<Microsoft.UI.Composition.ICompositionSupportsSystemBackdrop>());
        _micaController.SetSystemBackdropConfiguration(_backdropConfig);
        return true;
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

/// <summary>Required for SystemBackdrop controllers on unpackaged WinUI.</summary>
internal sealed class WindowsSystemDispatcherQueueHelper
{
    private object? _dispatcherQueueController;

    [System.Runtime.InteropServices.DllImport("CoreMessaging.dll")]
    private static extern int CreateDispatcherQueueController(
        [System.Runtime.InteropServices.In] DispatcherQueueOptions options,
        [System.Runtime.InteropServices.In, System.Runtime.InteropServices.Out, System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.IUnknown)]
        ref object? dispatcherQueueController);

    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    private struct DispatcherQueueOptions
    {
        public int dwSize;
        public int threadType;
        public int apartmentType;
    }

    public void EnsureWindowsSystemDispatcherQueueController()
    {
        if (Windows.System.DispatcherQueue.GetForCurrentThread() is not null) return;
        if (_dispatcherQueueController is not null) return;

        DispatcherQueueOptions options;
        options.dwSize = System.Runtime.InteropServices.Marshal.SizeOf<DispatcherQueueOptions>();
        options.threadType = 2; // DQTYPE_THREAD_CURRENT
        options.apartmentType = 2; // DQTAT_COM_STA
        CreateDispatcherQueueController(options, ref _dispatcherQueueController);
    }
}
