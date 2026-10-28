using System.Diagnostics;
using System.Runtime.InteropServices.WindowsRuntime;
using FileRadar.Models;
using FileRadar.Services;
using Microsoft.UI;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;
using Windows.System;
using Color = Windows.UI.Color;

namespace FileRadar.Views;

public sealed partial class MainPage : Page
{
    private Destination _destination = Destination.Home;
    private FileItem? _selected;
    private readonly List<FileItem> _selection = [];
    private bool _systemDark;
    private Button? _activeNav;

    public MainPage()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            _systemDark = Application.Current.RequestedTheme == ApplicationTheme.Dark;
            BuildFavorites();
            RefreshDiskBar();
            App.Theme.InspectorOpen = true;
            ApplyTheme();
            // Hard-pin Showcase chrome so Home always shows the third pane + disk bar
            InspectorColumn.Width = new GridLength(340);
            InspectorBorder.Visibility = Visibility.Visible;
            DiskBarBorder.Visibility = Visibility.Visible;
            DiskNameText.Text = "System";
            DiskFreeText.Text = "Measuring free space…";
            HighlightNav(NavHome);
            NavigateTo(Destination.Home);
            RefreshDiskBar();

            var log = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "FileRadar", "ui-load.log");
            Directory.CreateDirectory(Path.GetDirectoryName(log)!);
            if (string.Equals(Environment.GetEnvironmentVariable("FILERADAR_CAPTURE"), "1", StringComparison.Ordinal))
            {
                DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, async () =>
                {
                    await Task.Delay(1200);
                    await CaptureSelfAsync();
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
            var file = await folder.CreateFileAsync("apple-home-capture.png", CreationCollisionOption.ReplaceExisting);
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

            // Also copy next to the exe for easy pickup
            var dest = Path.Combine(AppContext.BaseDirectory, "fileradar-windows-apple-home.png");
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
        {
            var name = Path.GetFileName(place.TrimEnd('\\', '/'));
            if (string.IsNullOrEmpty(name)) name = place;
            var btn = new Button
            {
                Style = (Style)Application.Current.Resources["FrNavButton"],
                Tag = place,
                Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
            };
            btn.Content = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 10,
                Children =
                {
                    new FontIcon { Glyph = "\uE8B7", FontSize = 14 },
                    new TextBlock { Text = name }
                }
            };
            btn.Click += Favorite_Click;
            FavoritesPanel.Children.Add(btn);
        }
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

    private void Nav_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag } btn) return;
        HighlightNav(btn);
        _destination = tag switch
        {
            "Search" => Destination.Search,
            "Cleanup" => Destination.Cleanup,
            "Duplicates" => Destination.Duplicates,
            "Timeline" => Destination.Timeline,
            "RecycleBin" => Destination.RecycleBin,
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
        // Showcase Home is Modern only — ignore Colourful/Minimal
        var palette = ThemeCatalog.Resolve(AppLook.Modern, dark);
        App.ApplyThemeResources(Application.Current.Resources, palette);

        RootGrid.Background = BrushFrom(palette.Bg);
        TopBar.Background = BrushFrom(palette.Panel);
        SidebarBorder.Background = BrushFrom(palette.Panel);
        InspectorBorder.Background = BrushFrom(palette.Panel);

        AppearanceIcon.Glyph = App.Theme.Appearance switch
        {
            AppearanceMode.Light => "\uE706",
            AppearanceMode.Dark => "\uE708",
            _ => "\uE771"
        };

        if (App.Theme.InspectorOpen)
        {
            InspectorColumn.Width = new GridLength(340);
            InspectorBorder.Visibility = Visibility.Visible;
        }
        else
        {
            InspectorColumn.Width = new GridLength(0);
            InspectorBorder.Visibility = Visibility.Collapsed;
        }

        RequestedTheme = dark ? ElementTheme.Dark : ElementTheme.Light;
        App.SyncBackdropTheme(dark);
        if (_activeNav is not null) HighlightNav(_activeNav);
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

    private void Refresh()
    {
        ApplyTheme();
        MainContent.Children.Clear();
        _selection.Clear();
        RefreshDiskBar();

        var isHome = _destination == Destination.Home;
        BrowseActions.Visibility = isHome ? Visibility.Collapsed : Visibility.Visible;
        SubtitleText.Visibility = isHome ? Visibility.Collapsed : Visibility.Visible;

        switch (_destination)
        {
            case Destination.Home:
                TitleText.Text = "Home";
                PathText.Text = "";
                RenderShowcaseHome();
                // Seed inspector with first recent so the third pane looks alive (mockup)
                if (_selected is null)
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
            default:
                TitleText.Text = Path.GetFileName(App.Library.CurrentPath.TrimEnd('\\')) is { Length: > 0 } n ? n : App.Library.CurrentPath;
                SubtitleText.Text = "Browse";
                PathText.Text = App.Library.CurrentPath;
                RenderFileCollection(App.Library.ListDirectory(App.Library.CurrentPath), "This folder is empty or inaccessible.");
                break;
        }
    }

    private void RenderShowcaseHome()
    {
        // —— Shelves ——
        var shelvesHeader = new Grid { Margin = new Thickness(0, 0, 0, 4) };
        shelvesHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        shelvesHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var shelvesTitle = new StackPanel { Spacing = 2 };
        shelvesTitle.Children.Add(new TextBlock
        {
            Text = "Shelves",
            FontSize = 15,
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

        var editBtn = new Button
        {
            Content = "Edit Shelves",
            Style = (Style)Application.Current.Resources["FrGhostButton"],
            Background = (Brush)Application.Current.Resources["FrPanelBrush"],
            BorderBrush = (Brush)Application.Current.Resources["FrBorderBrush"],
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        };
        editBtn.Click += (_, _) =>
        {
            // Opens Images kind shelf browse as a stand-in for shelf editing
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
            var shelfRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16, Padding = new Thickness(0, 4, 0, 8) };
            foreach (var album in albums)
                shelfRow.Children.Add(BuildShelfAlbumCard(album));
            shelfScroll.Content = shelfRow;
            MainContent.Children.Add(shelfScroll);
        }

        // —— Recents ——
        var recentsHeader = new Grid { Margin = new Thickness(0, 8, 0, 4) };
        recentsHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        recentsHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var recentsTitle = new StackPanel { Spacing = 2 };
        recentsTitle.Children.Add(new TextBlock
        {
            Text = "Recents",
            FontSize = 15,
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

        var sortLabel = new TextBlock
        {
            Text = App.Theme.ViewMode == ViewMode.Grid ? "Grid" : "List",
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"],
            Margin = new Thickness(0, 0, 4, 0)
        };
        Grid.SetColumn(sortLabel, 1);
        recentsHeader.Children.Add(sortLabel);
        MainContent.Children.Add(recentsHeader);

        var recents = App.Library.BuildRecents();
        if (recents.Count == 0)
            MainContent.Children.Add(EmptyLabel("No recent files yet."));
        else if (App.Theme.ViewMode == ViewMode.List)
            MainContent.Children.Add(BuildRecentsList(recents));
        else
            MainContent.Children.Add(BuildRecentsGrid(recents));
    }

    private FrameworkElement BuildShelfAlbumCard(ShelfAlbum album)
    {
        var radius = (double)Application.Current.Resources["FrRadius"];
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
        var glyph = new FontIcon
        {
            Glyph = album.Cover?.KindGlyph ?? "\uE8B7",
            FontSize = 36,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        };
        coverGrid.Children.Add(glyph);
        var img = new Image { Stretch = Stretch.UniformToFill, Visibility = Visibility.Collapsed };
        coverGrid.Children.Add(img);
        cover.Child = coverGrid;
        card.Children.Add(cover);

        card.Children.Add(new TextBlock
        {
            Text = album.Title,
            FontSize = 13,
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
            // Browse the cover's parent folder
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

    private async Task LoadCoverAsync(FileItem? item, Image img, FontIcon glyph)
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
        var radius = (double)Application.Current.Resources["FrRadius"];
        var card = new Border
        {
            Width = 168,
            Margin = new Thickness(0, 0, 12, 12),
            Padding = new Thickness(8),
            CornerRadius = new CornerRadius(radius),
            Background = (Brush)Application.Current.Resources["FrPanel2Brush"],
            BorderThickness = new Thickness(0),
            Tag = item
        };

        var stack = new StackPanel { Spacing = 8 };
        var thumb = new Border
        {
            Height = 120,
            CornerRadius = new CornerRadius(radius - 2),
            Background = KindPlateBrush(item.Kind)
        };
        var thumbGrid = new Grid();
        var glyph = new FontIcon
        {
            Glyph = item.KindGlyph,
            FontSize = 40,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["FrAccentBrush"]
        };
        var img = new Image { Stretch = Stretch.UniformToFill, Visibility = Visibility.Collapsed };
        thumbGrid.Children.Add(glyph);
        thumbGrid.Children.Add(img);
        thumb.Child = thumbGrid;
        stack.Children.Add(thumb);

        stack.Children.Add(new TextBlock
        {
            Text = item.Name,
            FontSize = 13,
            MaxLines = 2,
            TextWrapping = TextWrapping.WrapWholeWords,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        });
        stack.Children.Add(new TextBlock
        {
            Text = item.RelativeTimeLabel,
            FontSize = 11,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        });
        card.Child = stack;

        card.PointerPressed += (_, _) =>
        {
            SelectItem(item);
            // subtle selection wash
            card.Background = (Brush)Application.Current.Resources["FrSelectionBrush"];
        };
        card.DoubleTapped += (_, _) => OpenItem(item);

        _ = LoadCoverAsync(item, img, glyph);
        return card;
    }

    private Panel BuildRecentsList(IReadOnlyList<FileItem> items)
    {
        var list = new StackPanel { Spacing = 0 };
        var shell = new Border
        {
            Background = (Brush)Application.Current.Resources["FrPanel2Brush"],
            CornerRadius = new CornerRadius((double)Application.Current.Resources["FrRadius"]),
            Padding = new Thickness(4),
            Child = list
        };
        foreach (var item in items)
            list.Children.Add(BuildRecentRow(item));
        return new Grid { Children = { shell } };
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
        var glyph = new FontIcon
        {
            Glyph = item.KindGlyph,
            FontSize = 16,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        };
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
            FontSize = 13,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        });
        info.Children.Add(new TextBlock
        {
            Text = item.RelativeTimeLabel,
            FontSize = 11,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        });
        Grid.SetColumn(info, 1);
        row.Children.Add(info);

        var size = new TextBlock
        {
            Text = item.SizeLabel,
            FontSize = 11,
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
                FontSize = 15,
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
            ? BuildRecentsList(items)
            : BuildRecentsGrid(items));
    }

    private static TextBlock EmptyLabel(string text) => new()
    {
        Text = text,
        Foreground = (Brush)Application.Current.Resources["FrMutedBrush"],
        Margin = new Thickness(4, 8, 4, 8),
        FontSize = 13
    };

    private static Brush KindPlateBrush(FileKind kind)
    {
        // Soft tinted plates (not flat grey utility boxes)
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
        // Light mode fallthrough — ThemeCatalog already dark by default
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
        InspectorGlyph.Glyph = item.KindGlyph;
        InspectorGlyph.Visibility = Visibility.Visible;
        InspectorImage.Visibility = Visibility.Collapsed;
        ShowInExplorerBtn.IsEnabled = true;

        InspectorMetaPanel.Children.Clear();
        AddMetaRow("Kind", item.KindDisplayName);
        AddMetaRow("File Size", item.SizeLabel);
        if (item.Width is int w && item.Height is int h)
            AddMetaRow("Dimensions", $"{w} × {h}");
        AddMetaRow("Location", Path.GetDirectoryName(item.Path) ?? item.Path);

        InspectorTagsPanel.Children.Clear();
        foreach (var tag in InferTags(item))
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
                    FontSize = 11,
                    Foreground = (Brush)Application.Current.Resources["FrAccentBrush"]
                }
            });
        }

        _ = LoadInspectorPreviewAsync(item);
    }

    private void AddMetaRow(string label, string value)
    {
        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var l = new TextBlock
        {
            Text = label,
            FontSize = 13,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        };
        var v = new TextBlock
        {
            Text = value,
            FontSize = 13,
            TextAlignment = TextAlignment.Right,
            TextWrapping = TextWrapping.WrapWholeWords,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        };
        Grid.SetColumn(v, 1);
        row.Children.Add(l);
        row.Children.Add(v);
        InspectorMetaPanel.Children.Add(row);
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
        InspectorGlyph.Visibility = Visibility.Collapsed;

        // Try dimensions for images
        if (item.CanThumbnail && bmp.PixelWidth > 0)
            AddMetaRow("Dimensions", $"{bmp.PixelWidth} × {bmp.PixelHeight}");
    }

    private async void OpenItem(FileItem item)
    {
        if (item.IsDirectory)
        {
            App.Library.Navigate(item.Path);
            _destination = Destination.Browse;
            HighlightNav(null);
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

    private void AppearanceBtn_Click(object sender, RoutedEventArgs e)
    {
        App.Theme.CycleAppearance();
        Refresh();
    }

    private void ViewModeBtn_Click(object sender, RoutedEventArgs e)
    {
        App.Theme.ViewMode = App.Theme.ViewMode == ViewMode.Grid ? ViewMode.List : ViewMode.Grid;
        Refresh();
    }

    private void InspectorBtn_Click(object sender, RoutedEventArgs e)
    {
        App.Theme.InspectorOpen = !App.Theme.InspectorOpen;
        Refresh();
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
}
