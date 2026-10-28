using System.Runtime.InteropServices.WindowsRuntime;
using FileRadar.Models;
using FileRadar.Services;
using Microsoft.UI;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;

namespace FileRadar.Views;

public sealed partial class MainPage
{
    private void PersistSettings() => App.Settings.Save(App.Theme);

    private void ApplyChromeView()
    {
        var chrome = ChromeViewIds.Normalize(App.Theme.ChromeView);
        var browser = _destination is Destination.Home or Destination.Browse;

        WorkspaceTabsBar.Visibility = chrome == ChromeViewIds.WorkspaceTabs ? Visibility.Visible : Visibility.Collapsed;
        KeyboardLegendBar.Visibility = chrome == ChromeViewIds.CommandRail ? Visibility.Visible : Visibility.Collapsed;
        RadarWatermark.Visibility = chrome == ChromeViewIds.RadarGlass ? Visibility.Visible : Visibility.Collapsed;

        var commandRail = chrome == ChromeViewIds.CommandRail;
        CommandRailBorder.Visibility = commandRail ? Visibility.Visible : Visibility.Collapsed;
        CommandRailColumn.Width = commandRail ? new GridLength(FileRadarChrome.CommandRailWidth) : new GridLength(0);

        // Command Rail replaces the wide sidebar; other views keep Favorites/Places.
        if (commandRail)
        {
            SidebarBorder.Visibility = Visibility.Collapsed;
            SidebarColumn.Width = new GridLength(0);
        }
        else
        {
            SidebarBorder.Visibility = Visibility.Visible;
            SidebarColumn.Width = new GridLength(FileRadarChrome.SidebarWidth);
        }

        // Preview Theater: dual-pane + large Quick Look (inspector is part of the chrome).
        var forcePreview = chrome == ChromeViewIds.PreviewTheater;
        if (forcePreview)
        {
            App.Theme.InspectorOpen = true;
            App.Theme.DualPane = true;
        }
        else if (chrome is ChromeViewIds.CommandRail or ChromeViewIds.RadarGlass)
        {
            // These chromes keep the dual-pane stage clear unless the user re-opens inspector.
        }

        var showInspector = forcePreview || App.Theme.InspectorOpen;
        if (showInspector)
        {
            InspectorColumn.Width = new GridLength(forcePreview ? FileRadarChrome.PreviewWidth : 300);
            InspectorBorder.Visibility = Visibility.Visible;
            InspectorThumb.Height = forcePreview ? 220 : 160;
        }
        else
        {
            InspectorColumn.Width = new GridLength(0);
            InspectorBorder.Visibility = Visibility.Collapsed;
        }

        // Workspace Tabs: Queue drawer on the right.
        var showQueue = chrome == ChromeViewIds.WorkspaceTabs;
        QueueDrawerBorder.Visibility = showQueue ? Visibility.Visible : Visibility.Collapsed;
        QueueColumn.Width = showQueue ? new GridLength(FileRadarChrome.QueueWidth) : new GridLength(0);

        // Path pills: Radar Glass uses accent border; others use quiet border / none.
        var pill = chrome == ChromeViewIds.RadarGlass;
        LeftPathPill.BorderThickness = new Thickness(pill ? 1 : 0);
        RightPathPill.BorderThickness = new Thickness(pill ? 1 : 0);
        LeftPathPill.CornerRadius = new CornerRadius(pill ? 999 : FileRadarChrome.RadiusControl);
        RightPathPill.CornerRadius = new CornerRadius(pill ? 999 : FileRadarChrome.RadiusControl);
        LeftPathPill.Padding = pill ? new Thickness(10, 2, 10, 2) : new Thickness(0);
        RightPathPill.Padding = pill ? new Thickness(10, 2, 10, 2) : new Thickness(0);

        // Sync pill between panes for Command Rail.
        var syncPill = chrome == ChromeViewIds.CommandRail && App.Theme.DualPane && browser;
        SyncPillBtn.Visibility = syncPill ? Visibility.Visible : Visibility.Collapsed;
        DualDivider.Visibility = App.Theme.DualPane && browser && !syncPill ? Visibility.Visible : Visibility.Collapsed;
        DualDividerHost.Width = syncPill ? 44 : (App.Theme.DualPane && browser ? 1 : 0);
        DualDividerCol.Width = syncPill
            ? new GridLength(44)
            : (App.Theme.DualPane && browser ? new GridLength(1) : new GridLength(0));

        if (chrome == ChromeViewIds.WorkspaceTabs)
            RebuildWorkspaceTabs();

        ChromeBtn.Foreground = (Brush)Application.Current.Resources["FrAccentBrush"];
        ToolTipService.SetToolTip(ChromeBtn, $"Chrome: {ChromeViewIds.DisplayName(chrome)}  ·  Ctrl+Shift+C");
        ApplyRichIcons();
        UpdateTransferHud();
    }

    private void ApplyRichIcons()
    {
        var chrome = ChromeViewIds.Normalize(App.Theme.ChromeView);
        BrandIcon.Source = IconCatalog.Get("brand");
        AppearanceIconImg.Source = IconCatalog.Get(
            App.Theme.Appearance == AppearanceMode.Light ? "sun" : "moon");
        ChromeIconImg.Source = IconCatalog.Get(IconCatalog.ForChrome(chrome));
        DualPaneIconImg.Source = IconCatalog.Get("dualpane");
        ViewModeIconImg.Source = IconCatalog.Get("grid");
        SyncIconImg.Source = IconCatalog.Get("sync");
        InspectorIconImg.Source = IconCatalog.Get("inspector");
        TransfersIconImg.Source = IconCatalog.Get("transfers");
        OverflowIconImg.Source = IconCatalog.Get("more");

        RailHomeImg.Source = IconCatalog.Get("rail-home");
        RailSearchImg.Source = IconCatalog.Get("rail-search");
        RailSyncImg.Source = IconCatalog.Get("rail-sync");
        RailXferImg.Source = IconCatalog.Get("rail-xfer");
        RailPrefsImg.Source = IconCatalog.Get("rail-prefs");

        NavHomeImg.Source = IconCatalog.Get("home");
        NavShelvesImg.Source = IconCatalog.Get("shelves");
        NavSearchImg.Source = IconCatalog.Get("search");
        NavCleanupImg.Source = IconCatalog.Get("cleanup");
        NavDuplicatesImg.Source = IconCatalog.Get("duplicates");
        NavTimelineImg.Source = IconCatalog.Get("timeline");
        NavWorkspacesImg.Source = IconCatalog.Get("workspaces");
        NavRecycleImg.Source = IconCatalog.Get("recycle");
        DropStackIconImg.Source = IconCatalog.Get("dropstack");
        SyncPillIconImg.Source = IconCatalog.Get("xfer-pill");
        HudIconImg.Source = IconCatalog.Get(App.Transfers.IsPaused ? "sync" : "transfers");
        QueueIconImg.Source = IconCatalog.Get("queue");
        ShowInExplorerIconImg.Source = IconCatalog.Get(IconCatalog.FolderKeySafe(chrome));
        if (InspectorGlyphImg.Visibility == Visibility.Visible && _selected is null)
            InspectorGlyphImg.Source = IconCatalog.Get("document");
    }


    private void RebuildWorkspaceTabs()
    {
        WorkspaceTabsPanel.Children.Clear();
        var names = new List<string> { "Work", "Photos", "Archive" };
        foreach (var ws in App.Workspaces.Workspaces.Take(3))
        {
            if (!names.Contains(ws.Name, StringComparer.OrdinalIgnoreCase))
                names.Add(ws.Name);
        }
        for (var i = 0; i < Math.Min(names.Count, 5); i++)
        {
            var name = names[i];
            var active = i == 0;
            var btn = new Button
            {
                Content = name,
                Padding = new Thickness(14, 6, 14, 8),
                FontSize = 12,
                FontWeight = active ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
                Background = active
                    ? (Brush)Application.Current.Resources["FrPanel2Brush"]
                    : new SolidColorBrush(Colors.Transparent),
                Foreground = active
                    ? (Brush)Application.Current.Resources["FrAccentBrush"]
                    : (Brush)Application.Current.Resources["FrMutedBrush"],
                BorderThickness = new Thickness(0, 0, 0, active ? 2 : 0),
                BorderBrush = (Brush)Application.Current.Resources["FrAccentBrush"],
                CornerRadius = new CornerRadius(8, 8, 0, 0)
            };
            var captured = name;
            btn.Click += (_, _) =>
            {
                var match = App.Workspaces.Workspaces.FirstOrDefault(w =>
                    string.Equals(w.Name, captured, StringComparison.OrdinalIgnoreCase));
                if (match is not null)
                {
                    if (Directory.Exists(match.CurrentPath)) App.Library.Navigate(match.CurrentPath);
                    if (Directory.Exists(match.SecondaryPath)) App.Library.NavigateSecondary(match.SecondaryPath);
                    App.Theme.DualPane = match.DualPane;
                    App.Theme.InspectorOpen = match.InspectorOpen;
                    Refresh();
                }
            };
            WorkspaceTabsPanel.Children.Add(btn);
        }
    }

    private void ChromeBtn_Click(object sender, RoutedEventArgs e)
    {
        var panel = new StackPanel { MinWidth = 220, Spacing = 2, Padding = new Thickness(4) };
        foreach (var id in ChromeViewIds.All)
        {
            var localId = id;
            var active = ChromeViewIds.Normalize(App.Theme.ChromeView) == localId;
            var content = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 10,
                Children =
                {
                    IconCatalog.Make(IconCatalog.ForChrome(localId), 24),
                    new TextBlock
                    {
                        Text = (active ? "●  " : "○  ") + ChromeViewIds.DisplayName(localId),
                        FontSize = 13,
                        VerticalAlignment = VerticalAlignment.Center,
                        Foreground = active
                            ? (Brush)Application.Current.Resources["FrAccentBrush"]
                            : (Brush)Application.Current.Resources["FrTextBrush"]
                    }
                }
            };
            var b = new Button
            {
                Content = content,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Background = new SolidColorBrush(Colors.Transparent),
                BorderThickness = new Thickness(0),
                Padding = new Thickness(10, 8, 10, 8)
            };
            b.Click += (_, _) =>
            {
                App.Theme.SetChrome(localId);
                PersistSettings();
                Refresh();
            };
            panel.Children.Add(b);
        }
        new Flyout { Content = panel, Placement = FlyoutPlacementMode.Bottom }
            .ShowAt(ChromeBtn, new FlyoutShowOptions { Placement = FlyoutPlacementMode.Bottom });
    }

    private void CommandRail_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag }) return;
        switch (tag)
        {
            case "Home":
                NavigateTo(Destination.Home);
                HighlightNav(NavHome);
                break;
            case "Search":
                NavigateTo(Destination.Search);
                HighlightNav(null);
                break;
            case "Sync":
                CompareSync_Click(sender, e);
                break;
            case "Transfers":
                TransfersBtn_Click(sender, e);
                break;
            case "Settings":
                AppearanceBtn_Click(sender, e);
                break;
        }
    }

    private void AddWorkspaceTab_Click(object sender, RoutedEventArgs e)
    {
        var name = $"Space {App.Workspaces.Workspaces.Count + 1}";
        App.Workspaces.Save(name, App.Library.CurrentPath, App.Library.SecondaryPath,
            App.Theme.DualPane, App.Theme.InspectorOpen);
        RebuildWorkspaceTabs();
    }

    private void CloseQueue_Click(object sender, RoutedEventArgs e)
    {
        // Queue is part of Workspace Tabs chrome — cycling chrome closes it.
        App.Theme.SetChrome(ChromeViewIds.RadarGlass);
        PersistSettings();
        Refresh();
    }

    private async Task CaptureChromeViewsAsync()
    {
        var destRoot = Path.Combine(AppContext.BaseDirectory);
        var localApp = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FileRadar");
        Directory.CreateDirectory(localApp);

        var map = new (string Id, string File)[]
        {
            (ChromeViewIds.RadarGlass, "fileradar-windows-chrome-a.png"),
            (ChromeViewIds.PreviewTheater, "fileradar-windows-chrome-b.png"),
            (ChromeViewIds.CommandRail, "fileradar-windows-chrome-c.png"),
            (ChromeViewIds.WorkspaceTabs, "fileradar-windows-chrome-d.png"),
        };

        App.Transfers.EnqueueDemo("Activities preview", 3);
        foreach (var (id, file) in map)
        {
            App.Theme.SetChrome(id);
            App.Theme.DualPane = true;
            App.Theme.InspectorOpen = id == ChromeViewIds.PreviewTheater;
            ApplyTheme();
            Refresh();
            UpdateTransferHud();
            await Task.Delay(900);
            await CaptureToFileAsync(Path.Combine(destRoot, file));
            await CaptureToFileAsync(Path.Combine(localApp, file));
        }

        App.Theme.SetChrome(ChromeViewIds.RadarGlass);
        PersistSettings();
        Refresh();
    }

    private async Task CaptureToFileAsync(string destPath)
    {
        try
        {
            var rtb = new Microsoft.UI.Xaml.Media.Imaging.RenderTargetBitmap();
            await rtb.RenderAsync(RootGrid);
            var pixels = await rtb.GetPixelsAsync();
            var folder = await Windows.Storage.StorageFolder.GetFolderFromPathAsync(
                Path.GetDirectoryName(destPath)!);
            var file = await folder.CreateFileAsync(
                Path.GetFileName(destPath), Windows.Storage.CreationCollisionOption.ReplaceExisting);
            using var stream = await file.OpenAsync(Windows.Storage.FileAccessMode.ReadWrite);
            var encoder = await Windows.Graphics.Imaging.BitmapEncoder.CreateAsync(
                Windows.Graphics.Imaging.BitmapEncoder.PngEncoderId, stream);
            encoder.SetPixelData(
                Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8,
                Windows.Graphics.Imaging.BitmapAlphaMode.Premultiplied,
                (uint)rtb.PixelWidth,
                (uint)rtb.PixelHeight,
                96, 96,
                pixels.ToArray());
            await encoder.FlushAsync();
        }
        catch (Exception ex)
        {
            try
            {
                File.AppendAllText(
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "FileRadar", "ui-load.log"),
                    $"capture FAIL {destPath} {ex}\n");
            }
            catch { /* ignore */ }
        }
    }
}
