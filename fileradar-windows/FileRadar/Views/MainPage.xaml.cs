using System.Diagnostics;
using System.Runtime.InteropServices.WindowsRuntime;
using FileRadar.Models;
using FileRadar.Services;
using IconCatalog = FileRadar.Services.IconCatalog;
using Microsoft.UI;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.System;
using WinRT.Interop;
using Color = Windows.UI.Color;

namespace FileRadar.Views;

public sealed partial class MainPage : Page
{
    private Destination _destination = Destination.Home;
    private FileItem? _selected;
    private readonly List<FileItem> _selection = [];
    private bool _systemDark;
    private Button? _activeNav;
    private bool _rightPaneActive;
    private readonly Dictionary<Border, FileItem> _cardMap = [];

    public MainPage()
    {
        InitializeComponent();
        Loaded += OnLoaded;
        App.Transfers.Changed += (_, _) => DispatcherQueue.TryEnqueue(UpdateTransferHud);
        App.DropStack.Changed += (_, _) => DispatcherQueue.TryEnqueue(RefreshDropStackUi);
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            _systemDark = Application.Current.RequestedTheme == ApplicationTheme.Dark;
            // ForkLift-first defaults
            App.Theme.DualPane = true;
            App.Theme.ViewMode = ViewMode.List;
            App.Theme.InspectorOpen = false;
            App.Theme.PreferCopyOnDrop = true;

            var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            var docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            if (Directory.Exists(desktop)) App.Library.Navigate(desktop);
            if (Directory.Exists(docs)) App.Library.NavigateSecondary(docs);

            BuildFavorites();
            BuildPlaces();
            RefreshDiskBar();
            RefreshDropStackUi();
            App.Theme.ChromeView = ChromeViewIds.Normalize(App.Theme.ChromeView);
            ApplyTheme();
            DiskBarBorder.Visibility = Visibility.Visible;
            DiskNameText.Text = "System";
            DiskFreeText.Text = "Measuring free space…";
            HighlightNav(NavHome);
            NavigateTo(Destination.Home);
            RefreshDiskBar();
            UpdateTransferHud();
            ApplyDualPaneLayout();
            ApplyChromeView();

            var capture = string.Equals(Environment.GetEnvironmentVariable("FILERADAR_CAPTURE"), "1", StringComparison.Ordinal);
            if (capture)
            {
                DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, async () =>
                {
                    await Task.Delay(1200);
                    await CaptureChromeViewsAsync();
                });
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine(ex);
        }
    }

    private async Task CaptureSelfAsync()
    {
        try
        {
            var rtb = new RenderTargetBitmap();
            await rtb.RenderAsync(RootGrid);
            var pixels = await rtb.GetPixelsAsync();
            var folder = await StorageFolder.GetFolderFromPathAsync(
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FileRadar"));
            var file = await folder.CreateFileAsync("forklift-home-capture.png", CreationCollisionOption.ReplaceExisting);
            using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
            encoder.SetPixelData(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied,
                (uint)rtb.PixelWidth,
                (uint)rtb.PixelHeight,
                96, 96,
                pixels.ToArray());
            await encoder.FlushAsync();

            var dest = Path.Combine(AppContext.BaseDirectory, "fileradar-windows-forklift-home.png");
            File.Copy(file.Path, dest, true);
            File.AppendAllText(
                Path.Combine(folder.Path, "ui-load.log"),
                $"capture {rtb.PixelWidth}x{rtb.PixelHeight} -> {dest}\n");
        }
        catch (Exception ex)
        {
            try
            {
                File.AppendAllText(
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FileRadar", "ui-load.log"),
                    "capture FAIL " + ex + "\n");
            }
            catch { /* ignore */ }
        }
    }

    private void BuildFavorites()
    {
        FavoritesPanel.Children.Clear();
        foreach (var place in App.Library.FavoritePlaces.Where(Directory.Exists))
            FavoritesPanel.Children.Add(MakePlaceButton(place, "\uE735"));
    }

    private void BuildPlaces()
    {
        PlacesPanel.Children.Clear();
        foreach (var place in App.Library.QuickPlaces.Where(Directory.Exists)
                     .Where(p => !App.Library.FavoritePlaces.Contains(p, StringComparer.OrdinalIgnoreCase)))
            PlacesPanel.Children.Add(MakePlaceButton(place, "\uE8B7"));
    }

    private Button MakePlaceButton(string place, string glyph)
    {
        var name = Path.GetFileName(place.TrimEnd('\\', '/'));
        if (string.IsNullOrEmpty(name)) name = place;
        var btn = new Button
        {
            Style = (Style)Application.Current.Resources["FrNavButton"],
            Tag = place,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"],
            Padding = new Thickness(10, 6, 10, 6)
        };
        var iconKey = glyph == "\uE735" ? "star" : IconCatalog.ForPlace(place);
        btn.Content = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            Children =
            {
                IconCatalog.Make(iconKey, 20),
                new TextBlock { Text = name, FontSize = 12, VerticalAlignment = VerticalAlignment.Center }
            }
        };
        btn.Click += Favorite_Click;
        return btn;
    }

    private void Favorite_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string path }) return;
        App.Library.Navigate(path);
        _destination = Destination.Browse;
        HighlightNav(null);
        Refresh();
    }

    private void RefreshDiskBar()
    {
        var (name, free, total) = App.Library.GetSystemDriveInfo();
        DiskNameText.Text = name;
        if (total <= 0)
        {
            DiskFreeText.Text = "Disk capacity unavailable";
            DiskFreeBar.Value = 0;
            return;
        }
        DiskFreeText.Text = $"{FileItem.FormatBytes(free)} free of {FileItem.FormatBytes(total)}";
        DiskFreeBar.Value = Math.Clamp(1.0 - (double)free / total, 0, 1);
    }

    private void RefreshDropStackUi()
    {
        DropStackList.Children.Clear();
        var empty = App.DropStack.Count == 0;
        DropStackEmpty.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        DropStackClearBtn.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        DropStackPlaceBtn.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        foreach (var path in App.DropStack.Paths.Take(6))
        {
            var row = new Grid { ColumnSpacing = 6 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var name = new TextBlock
            {
                Text = Path.GetFileName(path),
                FontSize = 11,
                TextTrimming = TextTrimming.CharacterEllipsis,
                Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
            };
            var rm = new Button
            {
                Content = "\uE711",
                FontFamily = new FontFamily("Segoe MDL2 Assets"),
                FontSize = 10,
                Padding = new Thickness(4),
                Background = new SolidColorBrush(Colors.Transparent),
                BorderThickness = new Thickness(0),
                Foreground = (Brush)Application.Current.Resources["FrMutedBrush"],
                Tag = path
            };
            rm.Click += (_, _) => App.DropStack.Remove(path);
            Grid.SetColumn(rm, 1);
            row.Children.Add(name);
            row.Children.Add(rm);
            DropStackList.Children.Add(row);
        }
    }

    private void Nav_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag } btn) return;
        HighlightNav(btn);
        _destination = tag switch
        {
            "Shelves" => Destination.Shelves,
            "Search" => Destination.Search,
            "Cleanup" => Destination.Cleanup,
            "Duplicates" => Destination.Duplicates,
            "Timeline" => Destination.Timeline,
            "RecycleBin" => Destination.RecycleBin,
            "Workspaces" => Destination.Workspaces,
            _ => Destination.Home
        };
        Refresh();
    }

    private void HighlightNav(Button? btn)
    {
        var muted = (Brush)Application.Current.Resources["FrTextBrush"];
        var sel = (Brush)Application.Current.Resources["FrSelectionBrush"];
        foreach (var child in SidebarPanel.Children)
        {
            if (child is Button b && b.Tag is string)
            {
                b.Background = b == btn ? sel : new SolidColorBrush(Colors.Transparent);
                b.Foreground = muted;
                b.BorderThickness = new Thickness(0);
            }
        }
        _activeNav = btn;
    }

    private void NavigateTo(Destination dest)
    {
        _destination = dest;
        Refresh();
    }

    private void ApplyTheme()
    {
        var dark = App.Theme.IsDark(_systemDark);
        var chrome = ChromeViewIds.Normalize(App.Theme.ChromeView);
        var palette = ThemeCatalog.Resolve(AppLook.Modern, dark, chrome);
        App.ApplyThemeResources(Application.Current.Resources, palette);

        RootGrid.Background = BrushFrom(palette.Bg);
        TopBar.Background = BrushFrom(palette.Panel);
        WorkspaceTabsBar.Background = BrushFrom(palette.Panel);
        SidebarBorder.Background = BrushFrom(palette.Panel);
        CommandRailBorder.Background = BrushFrom(palette.Panel);
        InspectorBorder.Background = BrushFrom(palette.Panel);
        QueueDrawerBorder.Background = BrushFrom(palette.Panel);
        KeyboardLegendBar.Background = BrushFrom(palette.Panel);
        TransferTopStrip.Background = BrushFrom(palette.Panel2);
        TransferHud.Background = BrushFrom(dark ? "#CC2C2C2E" : "#CCF5F5F7");
        BrandText.Foreground = BrushFrom(palette.Text);

        AppearanceIconImg.Source = IconCatalog.Get(
            App.Theme.Appearance == AppearanceMode.Light ? "sun" : "moon");
        DualPaneIconImg.Opacity = App.Theme.DualPane ? 1.0 : 0.55;

        RequestedTheme = dark ? ElementTheme.Dark : ElementTheme.Light;
        App.SyncBackdropTheme(dark);
        if (_activeNav is not null) HighlightNav(_activeNav);
        ApplyDualPaneLayout();
        ApplyChromeView();
    }

    private static SolidColorBrush BrushFrom(string hex)
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
        return new SolidColorBrush(Color.FromArgb(a, r, g, b));
    }

    private void ApplyDualPaneLayout()
    {
        var browser = _destination is Destination.Home or Destination.Browse;
        var on = App.Theme.DualPane && browser;
        // Ops strip stays collapsed — Copy → / ← Copy live in overflow; path bars carry pane chrome
        DualPaneChrome.Visibility = Visibility.Collapsed;
        DualDivider.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        RightPaneShell.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        RightScroll.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        DualDividerCol.Width = on ? new GridLength(1) : new GridLength(0);
        RightPaneCol.Width = on ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
        LeftPaneCol.Width = new GridLength(1, GridUnitType.Star);
        LeftPathBar.Visibility = browser ? Visibility.Visible : Visibility.Collapsed;
        RightPathBar.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        DualPaneActiveLabel.Text = _rightPaneActive ? "Right pane active" : "Left pane active";
        LeftPaneHint.Foreground = _rightPaneActive
            ? (Brush)Application.Current.Resources["FrMutedBrush"]
            : (Brush)Application.Current.Resources["FrAccentBrush"];
        RightPaneHint.Foreground = _rightPaneActive
            ? (Brush)Application.Current.Resources["FrAccentBrush"]
            : (Brush)Application.Current.Resources["FrMutedBrush"];
        CopyOnDropCheck.IsChecked = App.Theme.PreferCopyOnDrop;
        LeftPathBox.Text = App.Library.CurrentPath;
        RightPathBox.Text = App.Library.SecondaryPath;
        MarkActivePane();
        if (on) RenderRightPane();
    }

    private void MarkActivePane()
    {
        var accent = (SolidColorBrush)Application.Current.Resources["FrAccentBrush"];
        var wash = new SolidColorBrush(Color.FromArgb(0x08, accent.Color.R, accent.Color.G, accent.Color.B));
        var stroke = new SolidColorBrush(Color.FromArgb(0x8C, accent.Color.R, accent.Color.G, accent.Color.B));
        var browser = _destination is Destination.Home or Destination.Browse;
        if (!App.Theme.DualPane || !browser)
        {
            LeftPaneFrame.BorderThickness = new Thickness(0);
            RightPaneFrame.BorderThickness = new Thickness(0);
            LeftPaneFrame.Background = new SolidColorBrush(Colors.Transparent);
            RightPaneFrame.Background = new SolidColorBrush(Colors.Transparent);
            return;
        }
        LeftPaneFrame.BorderBrush = stroke;
        RightPaneFrame.BorderBrush = stroke;
        LeftPaneFrame.BorderThickness = _rightPaneActive ? new Thickness(0) : new Thickness(1.5);
        RightPaneFrame.BorderThickness = _rightPaneActive ? new Thickness(1.5) : new Thickness(0);
        LeftPaneFrame.Background = _rightPaneActive ? new SolidColorBrush(Colors.Transparent) : wash;
        RightPaneFrame.Background = _rightPaneActive ? wash : new SolidColorBrush(Colors.Transparent);
    }

    private void RenderRightPane()
    {
        RightContent.Children.Clear();
        var items = App.Library.ListDirectory(App.Library.SecondaryPath);
        if (items.Count == 0)
            RightContent.Children.Add(EmptyLabel("This folder is empty."));
        else
            RightContent.Children.Add(App.Theme.ViewMode == ViewMode.List
                ? BuildBrowserList(items, rightPane: true)
                : BuildRecentsGrid(items));
    }

    private void Refresh()
    {
        ApplyTheme();
        MainContent.Children.Clear();
        RightContent.Children.Clear();
        _selection.Clear();
        _cardMap.Clear();
        RefreshDiskBar();
        RefreshDropStackUi();

        var isBrowser = _destination is Destination.Home or Destination.Browse;
        var isTool = !isBrowser;
        ToolHeader.Visibility = isTool ? Visibility.Visible : Visibility.Collapsed;
        BrowseActions.Visibility = isTool && _destination is not Destination.Shelves and not Destination.Workspaces
            ? Visibility.Visible : Visibility.Collapsed;
        SubtitleText.Visibility = isTool ? Visibility.Visible : Visibility.Collapsed;
        BreadcrumbText.Text = _destination switch
        {
            Destination.Home => "›  Browser",
            Destination.Browse => $"›  {Path.GetFileName(App.Library.CurrentPath.TrimEnd('\\'))}",
            Destination.Shelves => "›  Shelves",
            Destination.Workspaces => "›  Workspaces",
            Destination.Search => "›  Search",
            Destination.Cleanup => "›  Cleanup",
            Destination.Duplicates => "›  Duplicates",
            Destination.Timeline => "›  Timeline",
            Destination.RecycleBin => "›  Recycle Bin",
            _ => "›  FileRadar"
        };

        switch (_destination)
        {
            case Destination.Home:
            case Destination.Browse:
                TitleText.Text = "Browser";
                PathText.Text = App.Library.CurrentPath;
                RenderBrowserLeft();
                break;
            case Destination.Shelves:
                TitleText.Text = "Shelves";
                SubtitleText.Text = "Curated album groups — secondary to the dual-pane browser";
                PathText.Text = "";
                RenderShowcaseHome();
                {
                    var seed = App.Library.BuildRecents(1).FirstOrDefault()
                               ?? App.Library.BuildAlbumShelves().FirstOrDefault()?.Cover;
                    if (seed is not null) SelectItem(seed);
                }
                break;
            case Destination.Search:
                TitleText.Text = "Search";
                SubtitleText.Text = "Filename search across your places";
                PathText.Text = "";
                RenderFileCollection(App.Library.Search(SearchBox.Text ?? ""), "No matches yet — type a query above.");
                break;
            case Destination.Cleanup:
                TitleText.Text = "Cleanup";
                SubtitleText.Text = "Largest files in Downloads";
                PathText.Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
                RenderFileCollection(App.Library.CleanupCandidates(), "Downloads looks tidy.");
                break;
            case Destination.Duplicates:
                TitleText.Text = "Duplicates";
                SubtitleText.Text = "Same name + size groups";
                PathText.Text = "";
                RenderDuplicates();
                break;
            case Destination.Timeline:
                TitleText.Text = "Timeline";
                SubtitleText.Text = "Files from the last two weeks";
                PathText.Text = "";
                RenderTimeline();
                break;
            case Destination.RecycleBin:
                TitleText.Text = "Recycle Bin";
                SubtitleText.Text = "FileRadar staging trash";
                PathText.Text = App.Library.StagingTrashPath;
                RenderRecycleBin();
                break;
            case Destination.Workspaces:
                TitleText.Text = "Workspaces";
                SubtitleText.Text = "Restore tabs, panes, and places — locations only, never moves files.";
                SubtitleText.Visibility = Visibility.Visible;
                PathText.Text = "";
                RenderWorkspaces();
                break;
        }

        ApplyDualPaneLayout();
        UpdateTransferHud();
    }

    private void RenderBrowserLeft()
    {
        var items = App.Library.ListDirectory(App.Library.CurrentPath);
        if (items.Count == 0)
            MainContent.Children.Add(EmptyLabel("This folder is empty or inaccessible."));
        else
            MainContent.Children.Add(App.Theme.ViewMode == ViewMode.List
                ? BuildBrowserList(items, rightPane: false)
                : BuildRecentsGrid(items));
        if (items.Count > 0) SelectItem(items[0]);
    }

    private void RenderShowcaseHome()
    {
        var shelvesHeader = new Grid { Margin = new Thickness(0, 0, 0, 4) };
        shelvesHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        shelvesHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var shelvesTitle = new StackPanel { Spacing = 2 };
        shelvesTitle.Children.Add(new TextBlock
        {
            Text = "Shelves",
            FontSize = FileRadarChrome.TypeHeading,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        });
        shelvesTitle.Children.Add(new TextBlock
        {
            Text = "Curated groups of your files",
            FontSize = 12,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        });
        Grid.SetColumn(shelvesTitle, 0);
        shelvesHeader.Children.Add(shelvesTitle);

        // Mac: accent text link, not an outlined utility chip
        var editBtn = new Button
        {
            Content = "Edit Shelves",
            Background = new SolidColorBrush(Colors.Transparent),
            BorderThickness = new Thickness(0),
            Padding = new Thickness(8, 4, 8, 4),
            FontSize = 13,
            Foreground = (Brush)Application.Current.Resources["FrAccentBrush"]
        };
        editBtn.Click += (_, _) =>
        {
            var pics = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
            if (Directory.Exists(pics))
            {
                App.Library.Navigate(pics);
                _destination = Destination.Browse;
                HighlightNav(null);
                Refresh();
            }
        };
        Grid.SetColumn(editBtn, 1);
        shelvesHeader.Children.Add(editBtn);
        MainContent.Children.Add(shelvesHeader);

        var albums = App.Library.BuildAlbumShelves();
        if (albums.Count == 0)
        {
            MainContent.Children.Add(EmptyLabel("No shelves yet — once folders are scanned, album cards appear here."));
        }
        else
        {
            var shelfScroll = new ScrollViewer
            {
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
                HorizontalScrollMode = ScrollMode.Enabled,
                VerticalScrollMode = ScrollMode.Disabled
            };
            var shelfRow = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = FileRadarChrome.SpaceCardGap,
                Padding = new Thickness(0, 4, 0, 8)
            };
            foreach (var album in albums)
                shelfRow.Children.Add(BuildShelfAlbumCard(album));
            shelfScroll.Content = shelfRow;
            MainContent.Children.Add(shelfScroll);
        }

        var recentsHeader = new Grid { Margin = new Thickness(0, 8, 0, 4) };
        recentsHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        recentsHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var recentsTitle = new StackPanel { Spacing = 2 };
        recentsTitle.Children.Add(new TextBlock
        {
            Text = "Recents",
            FontSize = FileRadarChrome.TypeHeading,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        });
        recentsTitle.Children.Add(new TextBlock
        {
            Text = "Recently accessed files",
            FontSize = 12,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        });
        Grid.SetColumn(recentsTitle, 0);
        recentsHeader.Children.Add(recentsTitle);

        // Mac Recents chrome: Sort + Grid/List segmented
        var recentsChrome = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            VerticalAlignment = VerticalAlignment.Center
        };
        recentsChrome.Children.Add(new TextBlock
        {
            Text = "Date",
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        });
        var viewSeg = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 0 };
        Button ViewChip(string label, bool on, Action click)
        {
            var b = new Button
            {
                Content = label,
                Padding = new Thickness(10, 4, 10, 4),
                FontSize = 11,
                CornerRadius = new CornerRadius(6),
                BorderThickness = new Thickness(0),
                Background = on
                    ? (Brush)Application.Current.Resources["FrSelectionBrush"]
                    : new SolidColorBrush(Colors.Transparent),
                Foreground = on
                    ? (Brush)Application.Current.Resources["FrAccentBrush"]
                    : (Brush)Application.Current.Resources["FrMutedBrush"]
            };
            b.Click += (_, _) => click();
            return b;
        }
        viewSeg.Children.Add(ViewChip("Grid", App.Theme.ViewMode == ViewMode.Grid, () =>
        {
            App.Theme.ViewMode = ViewMode.Grid;
            Refresh();
        }));
        viewSeg.Children.Add(ViewChip("List", App.Theme.ViewMode == ViewMode.List, () =>
        {
            App.Theme.ViewMode = ViewMode.List;
            Refresh();
        }));
        recentsChrome.Children.Add(viewSeg);
        Grid.SetColumn(recentsChrome, 1);
        recentsHeader.Children.Add(recentsChrome);
        MainContent.Children.Add(recentsHeader);

        var recents = App.Library.BuildRecents();
        if (recents.Count == 0)
            MainContent.Children.Add(EmptyLabel("No recent files yet."));
        else if (App.Theme.ViewMode == ViewMode.List)
            MainContent.Children.Add(BuildRecentsList(recents));
        else
        {
            var grid = BuildRecentsGrid(recents);
            MainContent.Children.Add(grid);
            // Apply Mac-style selection stroke on the first recent after layout
            if (recents.Count > 0)
            {
                var first = recents[0];
                SelectItem(first);
                var card = _cardMap.FirstOrDefault(kv => kv.Value.Path == first.Path).Key;
                if (card is not null) ApplyCardSelection(card);
            }
        }
    }

    private void RenderWorkspaces()
    {
        var saveRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 0, 0, 16) };
        var nameBox = new TextBox
        {
            PlaceholderText = "Workspace name — e.g. Photos, Projects",
            Width = 280,
            FontSize = 13
        };
        var saveBtn = new Button
        {
            Content = "Save current layout",
            Style = (Style)Application.Current.Resources["FrGhostButton"],
            Background = (Brush)Application.Current.Resources["FrAccentBrush"],
            Foreground = new SolidColorBrush(Colors.White),
            BorderThickness = new Thickness(0)
        };
        saveBtn.Click += (_, _) =>
        {
            App.Workspaces.Save(nameBox.Text ?? "", App.Library.CurrentPath, App.Library.SecondaryPath,
                App.Theme.DualPane, App.Theme.InspectorOpen);
            nameBox.Text = "";
            Refresh();
        };
        saveRow.Children.Add(nameBox);
        saveRow.Children.Add(saveBtn);
        MainContent.Children.Add(saveRow);

        if (App.Workspaces.Workspaces.Count == 0)
        {
            MainContent.Children.Add(EmptyLabel("No workspaces yet. Arrange panes, then save a name like Photos or Projects."));
            return;
        }

        foreach (var ws in App.Workspaces.Workspaces)
        {
            var row = new Border
            {
                Padding = new Thickness(14, 12, 14, 12),
                Margin = new Thickness(0, 0, 0, 8),
                CornerRadius = new CornerRadius(FileRadarChrome.RadiusControl),
                Background = (Brush)Application.Current.Resources["FrPanel2Brush"],
                BorderBrush = (Brush)Application.Current.Resources["FrBorderBrush"],
                BorderThickness = new Thickness(1)
            };
            var g = new Grid { ColumnSpacing = 12 };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var info = new StackPanel { Spacing = 2 };
            info.Children.Add(new TextBlock
            {
                Text = ws.Name,
                FontSize = FileRadarChrome.TypeHeading,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
            });
            info.Children.Add(new TextBlock
            {
                Text = $"{(ws.DualPane ? "dual pane" : "single pane")} · inspector {(ws.InspectorOpen ? "on" : "off")}",
                FontSize = FileRadarChrome.TypeCaption,
                Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
            });
            var restore = new Button { Content = "Restore", Tag = ws };
            restore.Click += (_, _) =>
            {
                App.Library.Navigate(ws.CurrentPath);
                App.Library.NavigateSecondary(ws.SecondaryPath);
                App.Theme.DualPane = ws.DualPane;
                App.Theme.InspectorOpen = ws.InspectorOpen;
                _destination = Destination.Browse;
                HighlightNav(null);
                Refresh();
            };
            var del = new Button { Content = "Delete", Tag = ws };
            del.Click += (_, _) =>
            {
                App.Workspaces.Delete(ws.Id);
                Refresh();
            };
            Grid.SetColumn(restore, 1);
            Grid.SetColumn(del, 2);
            g.Children.Add(info);
            g.Children.Add(restore);
            g.Children.Add(del);
            row.Child = g;
            MainContent.Children.Add(row);
        }
    }

    private FrameworkElement BuildShelfAlbumCard(ShelfAlbum album)
    {
        var radius = FileRadarChrome.RadiusCard;
        var card = new StackPanel { Width = 200, Spacing = 8 };

        var cover = new Border
        {
            Width = 200,
            Height = 140,
            CornerRadius = new CornerRadius(radius),
            Background = KindPlateBrush(album.Kind),
            BorderBrush = (Brush)Application.Current.Resources["FrBorderBrush"],
            BorderThickness = new Thickness(1),
        };

        var coverGrid = new Grid();
        var glyph = IconCatalog.Make(
            album.Cover is null ? "folder" : IconCatalog.ForFileItem(album.Cover, App.Theme.ChromeView),
            48);
        glyph.HorizontalAlignment = HorizontalAlignment.Center;
        glyph.VerticalAlignment = VerticalAlignment.Center;
        coverGrid.Children.Add(glyph);
        var img = new Image { Stretch = Stretch.UniformToFill, Visibility = Visibility.Collapsed };
        coverGrid.Children.Add(img);
        cover.Child = coverGrid;
        card.Children.Add(cover);

        card.Children.Add(new TextBlock
        {
            Text = album.Title,
            FontSize = FileRadarChrome.TypeBody,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        });
        card.Children.Add(new TextBlock
        {
            Text = album.Subtitle,
            FontSize = 12,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        });

        card.PointerPressed += (_, _) =>
        {
            if (album.Items.Count > 0)
                SelectItem(album.Items[0]);
        };
        card.DoubleTapped += (_, _) =>
        {
            var path = album.Cover?.Path;
            if (path is null) return;
            var dir = Path.GetDirectoryName(path);
            if (dir is null || !Directory.Exists(dir)) return;
            App.Library.Navigate(dir);
            _destination = Destination.Browse;
            HighlightNav(null);
            Refresh();
        };

        _ = LoadCoverAsync(album.Cover, img, glyph);
        return card;
    }

    private async Task LoadCoverAsync(FileItem? item, Image img, FrameworkElement glyph)
    {
        if (item is null) return;
        var bmp = await ThumbnailService.TryLoadAsync(item.Path, 280);
        if (bmp is null) return;
        img.Source = bmp;
        img.Visibility = Visibility.Visible;
        glyph.Visibility = Visibility.Collapsed;
    }

    private Panel BuildRecentsGrid(IReadOnlyList<FileItem> items)
    {
        var gv = new GridView
        {
            SelectionMode = ListViewSelectionMode.None,
            IsItemClickEnabled = true
        };
        gv.ItemClick += (_, args) =>
        {
            if (args.ClickedItem is FrameworkElement fe && fe.Tag is FileItem fi)
                SelectItem(fi);
        };

        foreach (var item in items)
            gv.Items.Add(BuildRecentCard(item));

        return new Grid { Children = { gv } };
    }

    private FrameworkElement BuildRecentCard(FileItem item)
    {
        var radius = FileRadarChrome.RadiusCard;
        var accent = ((SolidColorBrush)Application.Current.Resources["FrAccentBrush"]).Color;
        // cardFill ≈ primary @ 4% (unified-look) — soft plate, not flat utility box
        var cardFill = new SolidColorBrush(Color.FromArgb(0x0A, 0xFF, 0xFF, 0xFF));
        var card = new Border
        {
            Width = 168,
            Margin = new Thickness(0, 0, FileRadarChrome.SpaceCardGap - 4, 12),
            Padding = new Thickness(8),
            CornerRadius = new CornerRadius(radius),
            Background = cardFill,
            BorderBrush = new SolidColorBrush(Color.FromArgb(0, accent.R, accent.G, accent.B)),
            BorderThickness = new Thickness(FileRadarChrome.SelectionStroke),
            Tag = item
        };
        _cardMap[card] = item;

        var stack = new StackPanel { Spacing = 8 };
        var thumb = new Border
        {
            Height = 120,
            CornerRadius = new CornerRadius(radius - 2),
            Background = KindPlateBrush(item.Kind)
        };
        var thumbGrid = new Grid();
        var glyph = IconCatalog.Make(IconCatalog.ForFileItem(item, App.Theme.ChromeView), 52);
        glyph.HorizontalAlignment = HorizontalAlignment.Center;
        glyph.VerticalAlignment = VerticalAlignment.Center;
        var img = new Image { Stretch = Stretch.UniformToFill, Visibility = Visibility.Collapsed };
        thumbGrid.Children.Add(glyph);
        thumbGrid.Children.Add(img);
        thumb.Child = thumbGrid;
        stack.Children.Add(thumb);

        stack.Children.Add(new TextBlock
        {
            Text = item.Name,
            FontSize = FileRadarChrome.TypeBody,
            MaxLines = 2,
            TextWrapping = TextWrapping.WrapWholeWords,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        });
        stack.Children.Add(new TextBlock
        {
            Text = item.RelativeTimeLabel,
            FontSize = FileRadarChrome.TypeCaption,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        });
        card.Child = stack;

        card.PointerPressed += (_, _) =>
        {
            SelectItem(item);
            ApplyCardSelection(card);
        };
        card.DoubleTapped += (_, _) => OpenItem(item);
        card.RightTapped += (_, args) => ShowItemMenu(item, card, args.GetPosition(card));

        _ = LoadCoverAsync(item, img, glyph);
        return card;
    }

    private void ApplyCardSelection(Border selected)
    {
        var accent = ((SolidColorBrush)Application.Current.Resources["FrAccentBrush"]).Color;
        var wash = new SolidColorBrush(Color.FromArgb(
            (byte)(FileRadarChrome.AccentFillOpacity * 255), accent.R, accent.G, accent.B));
        var stroke = new SolidColorBrush(accent);
        var idle = new SolidColorBrush(Color.FromArgb(0x0A, 0xFF, 0xFF, 0xFF));

        foreach (var kv in _cardMap)
        {
            if (kv.Key == selected)
            {
                kv.Key.Background = wash;
                kv.Key.BorderBrush = stroke;
            }
            else
            {
                kv.Key.Background = idle;
                kv.Key.BorderBrush = new SolidColorBrush(Color.FromArgb(0, accent.R, accent.G, accent.B));
            }
        }
    }

    private void ShowItemMenu(FileItem item, FrameworkElement anchor, Windows.Foundation.Point point)
    {
        var flyout = new MenuFlyout();
        var open = new MenuFlyoutItem { Text = "Open" };
        open.Click += (_, _) => OpenItem(item);
        var stack = new MenuFlyoutItem { Text = "Add to Drop Stack" };
        stack.Click += (_, _) => { App.DropStack.Add(item.Path); };
        var rename = new MenuFlyoutItem { Text = "Rename…          Ctrl+Shift+R" };
        rename.Click += (_, _) =>
        {
            SelectItem(item);
            _ = ShowBatchRenameAsync();
        };
        var explorer = new MenuFlyoutItem { Text = "Show in Explorer" };
        explorer.Click += (_, _) =>
        {
            SelectItem(item);
            ShowInExplorer_Click(explorer, new RoutedEventArgs());
        };
        flyout.Items.Add(open);
        flyout.Items.Add(stack);
        flyout.Items.Add(rename);
        flyout.Items.Add(explorer);
        flyout.ShowAt(anchor, point);
    }

    private Panel BuildRecentsList(IReadOnlyList<FileItem> items)
        => BuildBrowserList(items, rightPane: false);

    private Panel BuildBrowserList(IReadOnlyList<FileItem> items, bool rightPane)
    {
        var list = new StackPanel { Spacing = 0 };
        foreach (var item in items)
            list.Children.Add(BuildBrowserRow(item, rightPane));
        return list;
    }

    private FrameworkElement BuildBrowserRow(FileItem item, bool rightPane)
    {
        var row = new Border
        {
            Padding = new Thickness(8, 5, 8, 5),
            CornerRadius = new CornerRadius(4),
            Background = new SolidColorBrush(Colors.Transparent),
            BorderThickness = new Thickness(0),
            Tag = item
        };
        var g = new Grid { ColumnSpacing = 10 };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(72) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(88) });

        g.Children.Add(IconCatalog.Make(IconCatalog.ForFileItem(item, App.Theme.ChromeView), 22));
        var name = new TextBlock
        {
            Text = item.Name,
            FontSize = FileRadarChrome.TypeBody,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        };
        Grid.SetColumn(name, 1);
        g.Children.Add(name);

        var size = new TextBlock
        {
            Text = item.IsDirectory ? "—" : item.SizeLabel,
            FontSize = FileRadarChrome.TypeCaption,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        };
        Grid.SetColumn(size, 2);
        g.Children.Add(size);

        var modified = new TextBlock
        {
            Text = item.ModifiedUtc.ToLocalTime().ToString("yyyy-MM-dd"),
            FontSize = FileRadarChrome.TypeCaption,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        };
        Grid.SetColumn(modified, 3);
        g.Children.Add(modified);
        row.Child = g;

        row.PointerPressed += (_, _) =>
        {
            _rightPaneActive = rightPane;
            SelectItem(item);
            ApplyDualPaneLayout();
            row.Background = (Brush)Application.Current.Resources["FrSelectionBrush"];
        };
        row.DoubleTapped += (_, _) =>
        {
            _rightPaneActive = rightPane;
            OpenItem(item);
        };
        row.RightTapped += (_, args) =>
        {
            _rightPaneActive = rightPane;
            SelectItem(item);
            ShowItemMenu(item, row, args.GetPosition(row));
        };
        return row;
    }

    private FrameworkElement BuildRecentRow(FileItem item)
    {
        var row = new Grid
        {
            Padding = new Thickness(10, 8, 10, 8),
            ColumnSpacing = 12,
            Tag = item
        };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(44) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });

        var thumb = new Border
        {
            Width = 40,
            Height = 40,
            CornerRadius = new CornerRadius(6),
            Background = (Brush)Application.Current.Resources["FrPanelBrush"]
        };
        var g = new Grid();
        var glyph = IconCatalog.Make(IconCatalog.ForFileItem(item, App.Theme.ChromeView), 28);
        glyph.HorizontalAlignment = HorizontalAlignment.Center;
        glyph.VerticalAlignment = VerticalAlignment.Center;
        var img = new Image { Stretch = Stretch.UniformToFill, Visibility = Visibility.Collapsed };
        g.Children.Add(glyph);
        g.Children.Add(img);
        thumb.Child = g;
        Grid.SetColumn(thumb, 0);
        row.Children.Add(thumb);

        var info = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        info.Children.Add(new TextBlock
        {
            Text = item.Name,
            FontSize = FileRadarChrome.TypeBody,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        });
        info.Children.Add(new TextBlock
        {
            Text = item.RelativeTimeLabel,
            FontSize = FileRadarChrome.TypeCaption,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        });
        Grid.SetColumn(info, 1);
        row.Children.Add(info);

        var size = new TextBlock
        {
            Text = item.SizeLabel,
            FontSize = FileRadarChrome.TypeCaption,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Right,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        };
        Grid.SetColumn(size, 2);
        row.Children.Add(size);

        row.PointerPressed += (_, _) =>
        {
            SelectItem(item);
            row.Background = (Brush)Application.Current.Resources["FrSelectionBrush"];
        };
        row.DoubleTapped += (_, _) => OpenItem(item);
        _ = LoadCoverAsync(item, img, glyph);
        return row;
    }

    private void RenderDuplicates()
    {
        var groups = App.Library.FindDuplicates();
        if (groups.Count == 0)
        {
            MainContent.Children.Add(EmptyLabel("No duplicate name+size groups found."));
            return;
        }
        foreach (var g in groups)
        {
            MainContent.Children.Add(new TextBlock
            {
                Text = $"{g.Items[0].Name} · {g.Items.Count} copies",
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = (Brush)Application.Current.Resources["FrTextBrush"],
                Margin = new Thickness(0, 10, 0, 6)
            });
            MainContent.Children.Add(BuildRecentsGrid(g.Items));
        }
    }

    private void RenderTimeline()
    {
        var days = App.Library.Timeline();
        if (days.Count == 0)
        {
            MainContent.Children.Add(EmptyLabel("Nothing recent in the scanned places."));
            return;
        }
        foreach (var (day, items) in days)
        {
            MainContent.Children.Add(new TextBlock
            {
                Text = day,
                FontSize = FileRadarChrome.TypeHeading,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = (Brush)Application.Current.Resources["FrTextBrush"],
                Margin = new Thickness(0, 8, 0, 4)
            });
            MainContent.Children.Add(BuildRecentsGrid(items));
        }
    }

    private void RenderRecycleBin()
    {
        var bar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 0, 0, 8) };
        var restore = new Button { Content = "Restore selected to Desktop" };
        restore.Click += (_, _) =>
        {
            App.Library.RestoreFromTrash(_selection, Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory));
            Refresh();
        };
        var empty = new Button { Content = "Empty FileRadar trash" };
        empty.Click += (_, _) =>
        {
            App.Library.EmptyTrash();
            Refresh();
        };
        bar.Children.Add(restore);
        bar.Children.Add(empty);
        MainContent.Children.Add(bar);
        RenderFileCollection(App.Library.ListRecycleBin(), "Trash is empty.");
    }

    private void RenderFileCollection(IReadOnlyList<FileItem> items, string empty)
    {
        if (items.Count == 0)
        {
            MainContent.Children.Add(EmptyLabel(empty));
            return;
        }
        MainContent.Children.Add(App.Theme.ViewMode == ViewMode.List
            ? BuildBrowserList(items, rightPane: false)
            : BuildRecentsGrid(items));
    }

    private static TextBlock EmptyLabel(string text) => new()
    {
        Text = text,
        Foreground = (Brush)Application.Current.Resources["FrMutedBrush"],
        Margin = new Thickness(4, 8, 4, 8),
        FontSize = FileRadarChrome.TypeBody
    };

    private static Brush KindPlateBrush(FileKind kind)
    {
        var hex = kind switch
        {
            FileKind.Images => "#1C3A5F",
            FileKind.Documents => "#2A3340",
            FileKind.Videos => "#2A2438",
            FileKind.Music => "#24352E",
            FileKind.Archives => "#3A3220",
            FileKind.Apps => "#2C2C3A",
            _ => "#2C2C2E"
        };
        if (Application.Current.RequestedTheme == ApplicationTheme.Light
            || (App.MainWindow?.Content as FrameworkElement)?.ActualTheme == ElementTheme.Light)
        {
            hex = kind switch
            {
                FileKind.Images => "#E8F0FF",
                FileKind.Documents => "#EEF1F6",
                FileKind.Videos => "#F0EAF8",
                FileKind.Music => "#E8F5EF",
                FileKind.Archives => "#F7F0E4",
                FileKind.Apps => "#EEEAF5",
                _ => "#EEF0F3"
            };
        }
        hex = hex.TrimStart('#');
        return new SolidColorBrush(Color.FromArgb(255,
            Convert.ToByte(hex[..2], 16),
            Convert.ToByte(hex[2..4], 16),
            Convert.ToByte(hex[4..6], 16)));
    }

    private void SelectItem(FileItem item)
    {
        _selected = item;
        _selection.Clear();
        _selection.Add(item);

        InspectorName.Text = item.Name;
        InspectorModified.Text = item.RelativeTimeLabel;
        InspectorGlyphImg.Source = IconCatalog.Get(IconCatalog.ForFileItem(item, App.Theme.ChromeView));
        InspectorGlyphImg.Visibility = Visibility.Visible;
        InspectorImage.Visibility = Visibility.Collapsed;
        ShowInExplorerBtn.IsEnabled = true;

        InspectorMetaPanel.Children.Clear();
        AddMetaRow(InspectorMetaPanel, "Kind", item.KindDisplayName);
        AddMetaRow(InspectorMetaPanel, "File Size", item.SizeLabel);
        if (item.Width is int w && item.Height is int h)
            AddMetaRow(InspectorMetaPanel, "Dimensions", $"{w} × {h}");
        AddMetaRow(InspectorMetaPanel, "Location", Path.GetDirectoryName(item.Path) ?? item.Path);

        InspectorTagsPanel.Children.Clear();
        var tags = InferTags(item).ToList();
        InspectorTagsEmpty.Visibility = tags.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        foreach (var tag in tags)
        {
            InspectorTagsPanel.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(999),
                Padding = new Thickness(10, 4, 10, 4),
                Margin = new Thickness(0, 0, 6, 6),
                Background = (Brush)Application.Current.Resources["FrChipBrush"],
                Child = new TextBlock
                {
                    Text = tag,
                    FontSize = FileRadarChrome.TypeCaption,
                    Foreground = (Brush)Application.Current.Resources["FrAccentBrush"]
                }
            });
        }

        InspectorMorePanel.Children.Clear();
        AddMetaRow(InspectorMorePanel, "Path", item.Path);
        AddMetaRow(InspectorMorePanel, "Extension", string.IsNullOrEmpty(item.Extension) ? "—" : item.Extension);
        AddMetaRow(InspectorMorePanel, "Modified UTC", item.ModifiedUtc.ToString("u"));
        var addStack = new Button
        {
            Content = "Add to Drop Stack",
            FontSize = 12,
            HorizontalAlignment = HorizontalAlignment.Left,
            Background = new SolidColorBrush(Colors.Transparent),
            BorderThickness = new Thickness(0),
            Foreground = (Brush)Application.Current.Resources["FrAccentBrush"],
            Margin = new Thickness(0, 8, 0, 0)
        };
        addStack.Click += AddToDropStack_Click;
        InspectorMorePanel.Children.Add(addStack);

        _ = LoadInspectorPreviewAsync(item);
    }

    private void AddMetaRow(Panel panel, string label, string value)
    {
        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var l = new TextBlock
        {
            Text = label,
            FontSize = FileRadarChrome.TypeBody,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        };
        var v = new TextBlock
        {
            Text = value,
            FontSize = FileRadarChrome.TypeBody,
            TextAlignment = TextAlignment.Right,
            TextWrapping = TextWrapping.WrapWholeWords,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        };
        Grid.SetColumn(v, 1);
        row.Children.Add(l);
        row.Children.Add(v);
        panel.Children.Add(row);
    }

    private static IEnumerable<string> InferTags(FileItem item)
    {
        var tags = new List<string> { item.KindDisplayName.ToLowerInvariant() };
        var name = item.Name.ToLowerInvariant();
        if (name.Contains("screen")) tags.Add("screenshot");
        if (name.Contains("invoice") || name.Contains("receipt")) tags.Add("finance");
        if (item.Extension.Equals(".pdf", StringComparison.OrdinalIgnoreCase)) tags.Add("pdf");
        if (item.CanThumbnail) tags.Add("photo");
        return tags.Distinct();
    }

    private async Task LoadInspectorPreviewAsync(FileItem item)
    {
        var bmp = await ThumbnailService.TryLoadAsync(item.Path, 480);
        if (_selected?.Path != item.Path) return;
        if (bmp is null) return;
        InspectorImage.Source = bmp;
        InspectorImage.Visibility = Visibility.Visible;
        InspectorGlyphImg.Visibility = Visibility.Collapsed;

        if (item.CanThumbnail && bmp.PixelWidth > 0)
            AddMetaRow(InspectorMetaPanel, "Dimensions", $"{bmp.PixelWidth} × {bmp.PixelHeight}");
    }

    private async void OpenItem(FileItem item)
    {
        if (item.IsDirectory)
        {
            if (App.Theme.DualPane && _rightPaneActive)
                App.Library.NavigateSecondary(item.Path);
            else
            {
                App.Library.Navigate(item.Path);
                _destination = Destination.Browse;
                HighlightNav(null);
            }
            Refresh();
            return;
        }
        try
        {
            await Launcher.LaunchUriAsync(new Uri(item.Path));
        }
        catch
        {
            try { Process.Start(new ProcessStartInfo(item.Path) { UseShellExecute = true }); }
            catch { /* ignore */ }
        }
    }

    private void UpdateTransferHud()
    {
        var q = App.Transfers;
        var chrome = ChromeViewIds.Normalize(App.Theme.ChromeView);
        var pct = $"{(int)Math.Round(q.AggregateProgress * 100)}%";
        var pause = q.IsPaused ? "Resume" : "Pause";
        if (q.ActiveCount == 0 && q.Items.Any(i => i.Status == TransferStatus.Failed))
            pause = "Dismiss";

        // B: top strip
        var topStrip = chrome == ChromeViewIds.PreviewTheater && q.HudVisible;
        TransferTopStrip.Visibility = topStrip ? Visibility.Visible : Visibility.Collapsed;
        if (topStrip)
        {
            TopStripHeadline.Text = q.HudHeadline;
            TopStripProgress.Value = q.AggregateProgress;
            TopStripPercent.Text = pct;
            TopStripPauseBtn.Content = pause;
        }

        // D: queue drawer
        if (chrome == ChromeViewIds.WorkspaceTabs)
        {
            QueueHeadline.Text = q.HudVisible ? q.HudHeadline : "Queue idle";
            QueueProgress.Value = q.AggregateProgress;
            QueuePercent.Text = pct;
            QueuePauseBtn.Content = pause;
        }

        // A/C: docked bottom drawer (Radar Glass) or floating capsule (Command Rail)
        var showHud = q.HudVisible && chrome is ChromeViewIds.RadarGlass or ChromeViewIds.CommandRail;
        TransferHud.Visibility = showHud ? Visibility.Visible : Visibility.Collapsed;
        if (!showHud) return;

        HudHeadline.Text = q.HudHeadline;
        HudProgress.Value = q.AggregateProgress;
        HudPercent.Text = pct;
        HudPauseBtn.Content = pause;
        HudIconImg.Source = IconCatalog.Get(q.IsPaused ? "sync" : "transfers");

        if (chrome == ChromeViewIds.RadarGlass)
        {
            TransferHud.HorizontalAlignment = HorizontalAlignment.Stretch;
            TransferHud.VerticalAlignment = VerticalAlignment.Bottom;
            TransferHud.CornerRadius = new CornerRadius(16);
            TransferHud.Margin = new Thickness(12, 0, 12, 12);
            TransferHud.MaxWidth = 10000;
            TransferHud.Padding = new Thickness(18, 14, 18, 14);
        }
        else
        {
            TransferHud.HorizontalAlignment = HorizontalAlignment.Center;
            TransferHud.VerticalAlignment = VerticalAlignment.Bottom;
            TransferHud.CornerRadius = new CornerRadius(999);
            TransferHud.Margin = new Thickness(16, 0, 16, 48);
            TransferHud.MaxWidth = FileRadarChrome.HudMaxWidth;
            TransferHud.Padding = new Thickness(18, 12, 18, 12);
        }
    }

    // —— Event handlers ——

    private void ShowInExplorer_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"/select,\"{_selected.Path}\"",
                UseShellExecute = true
            });
        }
        catch { /* ignore */ }
    }

    private void AddToDropStack_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        App.DropStack.Add(_selected.Path);
    }

    private void AppearanceBtn_Click(object sender, RoutedEventArgs e)
    {
        App.Theme.CycleAppearance();
        PersistSettings();
        Refresh();
    }

    private void DualPaneBtn_Click(object sender, RoutedEventArgs e)
    {
        App.Theme.DualPane = !App.Theme.DualPane;
        PersistSettings();
        Refresh();
    }

    private void ViewModeBtn_Click(object sender, RoutedEventArgs e)
    {
        App.Theme.ViewMode = App.Theme.ViewMode == ViewMode.Grid ? ViewMode.List : ViewMode.Grid;
        PersistSettings();
        Refresh();
    }

    private void InspectorBtn_Click(object sender, RoutedEventArgs e)
    {
        App.Theme.InspectorOpen = !App.Theme.InspectorOpen;
        PersistSettings();
        Refresh();
    }

    private void TransfersBtn_Click(object sender, RoutedEventArgs e)
    {
        if (!App.Transfers.HudVisible)
            App.Transfers.EnqueueDemo("Manual preview", 2);
        UpdateTransferHud();
    }

    private Flyout BuildOverflowFlyout()
    {
        var panel = new StackPanel { MinWidth = 220, Spacing = 2, Padding = new Thickness(4) };
        Button Item(string label, RoutedEventHandler handler)
        {
            var b = new Button
            {
                Content = label,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Background = new SolidColorBrush(Colors.Transparent),
                BorderThickness = new Thickness(0),
                Padding = new Thickness(10, 8, 10, 8),
                FontSize = 13,
                Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
            };
            b.Click += handler;
            panel.Children.Add(b);
            return b;
        }
        Item("View → Chrome…          Ctrl+Shift+C", ChromeBtn_Click);
        Item("Copy selection → right pane", CopyLeftToRight_Click);
        Item("Copy selection ← left pane", CopyRightToLeft_Click);
        Item("Batch rename…          Ctrl+Shift+R", BatchRename_Click);
        Item("Compare / Sync…", CompareSync_Click);
        Item("Save workspace…", SaveWorkspace_Click);
        Item("Shelves (secondary)…", (_, _) =>
        {
            _destination = Destination.Shelves;
            HighlightNav(null);
            Refresh();
        });
        Item("Keyboard shortcuts", ShortcutsHelp_Click);
        return new Flyout { Content = panel, Placement = FlyoutPlacementMode.Bottom };
    }

    private void OverflowBtn_Click(object sender, RoutedEventArgs e)
    {
        BuildOverflowFlyout().ShowAt(OverflowBtn, new FlyoutShowOptions { Placement = FlyoutPlacementMode.BottomEdgeAlignedRight });
    }

    private void HudPause_Click(object sender, RoutedEventArgs e)
    {
        if (App.Transfers.ActiveCount == 0)
        {
            App.Transfers.ClearFinished();
            UpdateTransferHud();
            return;
        }
        App.Transfers.IsPaused = !App.Transfers.IsPaused;
        UpdateTransferHud();
    }

    private void HudCancel_Click(object sender, RoutedEventArgs e)
    {
        App.Transfers.CancelAll();
        UpdateTransferHud();
    }

    private void DropStackClear_Click(object sender, RoutedEventArgs e) => App.DropStack.Clear();

    private async void DropStackPlace_Click(object sender, RoutedEventArgs e)
    {
        if (App.DropStack.Count == 0) return;
        var folder = await PickFolderAsync();
        if (folder is null) return;
        App.Transfers.EnqueueMove(App.DropStack.Paths.ToList(), folder);
        App.DropStack.Clear();
        UpdateTransferHud();
    }

    private void DropStack_DragOver(object sender, DragEventArgs e)
    {
        e.AcceptedOperation = DataPackageOperation.Copy;
        e.DragUIOverride.Caption = "Add to Drop Stack";
        var accent = ((SolidColorBrush)Application.Current.Resources["FrAccentBrush"]).Color;
        DropStackBorder.Background = new SolidColorBrush(Color.FromArgb(
            (byte)(FileRadarChrome.DropTargetWashOpacity * 255), accent.R, accent.G, accent.B));
    }

    private async void DropStack_Drop(object sender, DragEventArgs e)
    {
        DropStackBorder.Background = (Brush)Application.Current.Resources["FrPanel2Brush"];
        if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;
        var items = await e.DataView.GetStorageItemsAsync();
        foreach (var item in items)
            App.DropStack.Add(item.Path);
    }

    private void DropStack_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        DropStackBorder.Background = (Brush)Application.Current.Resources["FrPanel2Brush"];
    }

    private void CopyOnDrop_Changed(object sender, RoutedEventArgs e)
    {
        App.Theme.PreferCopyOnDrop = CopyOnDropCheck.IsChecked == true;
    }

    private async void ChooseRightFolder_Click(object sender, RoutedEventArgs e)
    {
        var folder = await PickFolderAsync();
        if (folder is null) return;
        App.Library.NavigateSecondary(folder);
        _rightPaneActive = true;
        App.Theme.DualPane = true;
        Refresh();
    }

    private async void CompareSync_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new ContentDialog
        {
            Title = "Compare / Sync",
            Content = "Pick two folders to preview name differences. Sync apply stays a paid preview — nothing is overwritten here.",
            PrimaryButtonText = "Choose folders",
            CloseButtonText = "Close",
            XamlRoot = XamlRoot
        };
        if (await dlg.ShowAsync() != ContentDialogResult.Primary) return;
        var left = await PickFolderAsync();
        if (left is null) return;
        var right = await PickFolderAsync();
        if (right is null) return;
        App.Library.Navigate(left);
        App.Library.NavigateSecondary(right);
        App.Theme.DualPane = true;
        _destination = Destination.Browse;
        HighlightNav(null);
        Refresh();

        var leftNames = new HashSet<string>(
            App.Library.ListDirectory(left).Select(i => i.Name), StringComparer.OrdinalIgnoreCase);
        var rightNames = App.Library.ListDirectory(right).Select(i => i.Name).ToList();
        var onlyRight = rightNames.Count(n => !leftNames.Contains(n));
        var onlyLeft = leftNames.Count(n => !rightNames.Contains(n, StringComparer.OrdinalIgnoreCase));
        SubtitleText.Text = $"Compare preview · only left {onlyLeft} · only right {onlyRight}";
        SubtitleText.Visibility = Visibility.Visible;
    }

    private async void BatchRename_Click(object sender, RoutedEventArgs e)
    {
        await ShowBatchRenameAsync();
    }

    private async Task ShowBatchRenameAsync()
    {
        var files = _selection.Count > 0 ? _selection.ToList()
            : App.Library.BuildRecents(8).Take(5).ToList();
        if (files.Count == 0)
        {
            await new ContentDialog
            {
                Title = "Batch rename",
                Content = "Select files first, then rename them here.",
                CloseButtonText = "OK",
                XamlRoot = XamlRoot
            }.ShowAsync();
            return;
        }

        var patternBox = new TextBox
        {
            Text = "{name}-{n}",
            PlaceholderText = "{name}-{n}  or  re:find|replace",
            Margin = new Thickness(0, 8, 0, 8)
        };
        var preview = new TextBlock
        {
            FontSize = 12,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"],
            TextWrapping = TextWrapping.WrapWholeWords
        };
        void RefreshPreview()
        {
            var plan = BatchRenameService.Preview(files, patternBox.Text ?? "");
            preview.Text = string.Join("\n", plan.Take(8).Select(p => $"{p.File.Name}  →  {p.NewName}"));
        }
        patternBox.TextChanged += (_, _) => RefreshPreview();
        RefreshPreview();

        var stack = new StackPanel { Spacing = 6 };
        stack.Children.Add(new TextBlock
        {
            Text = $"{files.Count} selected · tokens {{name}}, {{n}}, {{date}} · regex: re:find|replace",
            FontSize = 12,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"],
            TextWrapping = TextWrapping.WrapWholeWords
        });
        stack.Children.Add(patternBox);
        stack.Children.Add(preview);

        var dlg = new ContentDialog
        {
            Title = "Batch rename",
            Content = stack,
            PrimaryButtonText = $"Rename {files.Count}",
            CloseButtonText = "Cancel",
            XamlRoot = XamlRoot
        };
        if (await dlg.ShowAsync() != ContentDialogResult.Primary) return;
        var plan = BatchRenameService.Preview(files, patternBox.Text ?? "");
        BatchRenameService.Apply(plan);
        Refresh();
    }

    private async void SaveWorkspace_Click(object sender, RoutedEventArgs e)
    {
        var box = new TextBox { PlaceholderText = "Workspace name" };
        var dlg = new ContentDialog
        {
            Title = "Save workspace",
            Content = box,
            PrimaryButtonText = "Save",
            CloseButtonText = "Cancel",
            XamlRoot = XamlRoot
        };
        if (await dlg.ShowAsync() != ContentDialogResult.Primary) return;
        App.Workspaces.Save(box.Text ?? "", App.Library.CurrentPath, App.Library.SecondaryPath,
            App.Theme.DualPane, App.Theme.InspectorOpen);
        HighlightNav(null);
        _destination = Destination.Workspaces;
        // find Workspaces nav
        foreach (var child in SidebarPanel.Children)
        {
            if (child is Button b && b.Tag is string s && s == "Workspaces")
            {
                HighlightNav(b);
                break;
            }
        }
        Refresh();
    }

    private async void ShortcutsHelp_Click(object sender, RoutedEventArgs e)
    {
        await new ContentDialog
        {
            Title = "Keyboard shortcuts",
            Content = "Ctrl+\\  Dual pane\nCtrl+Shift+C  Chrome / Layout\nCtrl+Shift+R  Batch rename\nCtrl+Shift+T  Transfers\nCtrl+Alt+I  Inspector\nCtrl+1 / Ctrl+2  Grid / List\nCtrl+Shift+A  Appearance\nDelete  Trash selection\nEnter  Open\nAlt+↑  Up",
            CloseButtonText = "OK",
            XamlRoot = XamlRoot
        }.ShowAsync();
    }

    private void Page_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        var ctrl = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        var shift = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        var alt = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Menu)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

        if (ctrl && shift && e.Key == VirtualKey.R) { _ = ShowBatchRenameAsync(); e.Handled = true; }
        else if (ctrl && shift && e.Key == VirtualKey.C) { ChromeBtn_Click(this, new RoutedEventArgs()); e.Handled = true; }
        else if (ctrl && shift && e.Key == VirtualKey.T) { TransfersBtn_Click(this, new RoutedEventArgs()); e.Handled = true; }
        else if (ctrl && shift && e.Key == VirtualKey.A) { AppearanceBtn_Click(this, new RoutedEventArgs()); e.Handled = true; }
        else if (ctrl && alt && e.Key == VirtualKey.I) { InspectorBtn_Click(this, new RoutedEventArgs()); e.Handled = true; }
        else if (ctrl && e.Key == VirtualKey.Number1) { App.Theme.ViewMode = ViewMode.Grid; Refresh(); e.Handled = true; }
        else if (ctrl && e.Key == VirtualKey.Number2) { App.Theme.ViewMode = ViewMode.List; Refresh(); e.Handled = true; }
        else if (ctrl && e.Key == (VirtualKey)0xDC) { DualPaneBtn_Click(this, new RoutedEventArgs()); e.Handled = true; } // \
        else if (e.Key == VirtualKey.Delete) { TrashBtn_Click(this, new RoutedEventArgs()); e.Handled = true; }
        else if (e.Key == VirtualKey.Enter && _selected is not null) { OpenItem(_selected); e.Handled = true; }
        else if (alt && e.Key == VirtualKey.Up) { UpBtn_Click(this, new RoutedEventArgs()); e.Handled = true; }
    }

    private async Task<string?> PickFolderAsync()
    {
        try
        {
            var picker = new FolderPicker();
            picker.FileTypeFilter.Add("*");
            if (App.MainWindow is not null)
            {
                var hwnd = WindowNative.GetWindowHandle(App.MainWindow);
                InitializeWithWindow.Initialize(picker, hwnd);
            }
            var folder = await picker.PickSingleFolderAsync();
            return folder?.Path;
        }
        catch
        {
            return null;
        }
    }

    private void SearchBox_QuerySubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
    {
        _destination = Destination.Search;
        HighlightNav(null);
        Refresh();
    }

    private void SearchBox_TextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        if (args.Reason == AutoSuggestionBoxTextChangeReason.UserInput && _destination == Destination.Search)
            Refresh();
    }

    private void UpBtn_Click(object sender, RoutedEventArgs e)
    {
        var parent = Directory.GetParent(App.Library.CurrentPath)?.FullName;
        if (parent is null) return;
        App.Library.Navigate(parent);
        _destination = Destination.Browse;
        Refresh();
    }

    private void TrashBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_selection.Count == 0) return;
        App.Library.MoveToTrash(_selection.ToList());
        Refresh();
    }

    private void OpenBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        OpenItem(_selected);
    }

    private void LeftPane_Activate(object sender, PointerRoutedEventArgs e)
    {
        _rightPaneActive = false;
        ApplyDualPaneLayout();
    }

    private void RightPane_Activate(object sender, PointerRoutedEventArgs e)
    {
        _rightPaneActive = true;
        ApplyDualPaneLayout();
    }

    private void LeftUp_Click(object sender, RoutedEventArgs e)
    {
        var parent = Directory.GetParent(App.Library.CurrentPath)?.FullName;
        if (parent is null) return;
        _rightPaneActive = false;
        App.Library.Navigate(parent);
        _destination = Destination.Browse;
        Refresh();
    }

    private void RightUp_Click(object sender, RoutedEventArgs e)
    {
        var parent = Directory.GetParent(App.Library.SecondaryPath)?.FullName;
        if (parent is null) return;
        _rightPaneActive = true;
        App.Library.NavigateSecondary(parent);
        App.Theme.DualPane = true;
        _destination = Destination.Browse;
        Refresh();
    }

    private void LeftHome_Click(object sender, RoutedEventArgs e)
    {
        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        if (!Directory.Exists(desktop)) return;
        _rightPaneActive = false;
        App.Library.Navigate(desktop);
        _destination = Destination.Home;
        HighlightNav(NavHome);
        Refresh();
    }

    private void RightHome_Click(object sender, RoutedEventArgs e)
    {
        var docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        if (!Directory.Exists(docs)) return;
        _rightPaneActive = true;
        App.Library.NavigateSecondary(docs);
        App.Theme.DualPane = true;
        _destination = Destination.Home;
        HighlightNav(NavHome);
        Refresh();
    }

    private void LeftPathBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != VirtualKey.Enter) return;
        var path = LeftPathBox.Text?.Trim();
        if (string.IsNullOrEmpty(path) || !Directory.Exists(path)) return;
        _rightPaneActive = false;
        App.Library.Navigate(path);
        _destination = Destination.Browse;
        Refresh();
        e.Handled = true;
    }

    private void RightPathBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != VirtualKey.Enter) return;
        var path = RightPathBox.Text?.Trim();
        if (string.IsNullOrEmpty(path) || !Directory.Exists(path)) return;
        _rightPaneActive = true;
        App.Library.NavigateSecondary(path);
        App.Theme.DualPane = true;
        _destination = Destination.Browse;
        Refresh();
        e.Handled = true;
    }

    private void CopyLeftToRight_Click(object sender, RoutedEventArgs e)
    {
        if (_selection.Count == 0) return;
        App.Transfers.EnqueueCopy(_selection.Select(i => i.Path).ToList(), App.Library.SecondaryPath);
        UpdateTransferHud();
    }

    private void CopyRightToLeft_Click(object sender, RoutedEventArgs e)
    {
        if (_selection.Count == 0) return;
        App.Transfers.EnqueueCopy(_selection.Select(i => i.Path).ToList(), App.Library.CurrentPath);
        UpdateTransferHud();
    }
}
