using System.Diagnostics;
using FileRadar.Models;
using Microsoft.UI;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using Windows.UI;
using Color = Windows.UI.Color;

namespace FileRadar.Views;

public sealed partial class MainPage : Page
{
    private Destination _destination = Destination.Home;
    private FileItem? _selected;
    private readonly List<FileItem> _selection = [];
    private bool _systemDark;

    public MainPage()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var theme = Application.Current.RequestedTheme;
        _systemDark = theme == ApplicationTheme.Dark;
        BuildPlaces();
        ApplyTheme();
        NavigateTo(Destination.Home);
    }

    private void BuildPlaces()
    {
        PlacesList.Items.Clear();
        foreach (var place in App.Library.QuickPlaces.Where(Directory.Exists))
        {
            var name = Path.GetFileName(place.TrimEnd('\\', '/'));
            if (string.IsNullOrEmpty(name)) name = place;
            var btn = new Button
            {
                Content = name,
                Tag = place,
                Style = (Style)Application.Current.Resources["FrNavButton"],
                Foreground = (Brush)Application.Current.Resources["FrTextBrush"],
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left
            };
            btn.Click += Place_Click;
            PlacesList.Items.Add(btn);
        }
    }

    private void Place_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string path })
        {
            App.Library.Navigate(path);
            _destination = Destination.Browse;
            Refresh();
        }
    }

    private void Nav_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag }) return;
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

    private void NavigateTo(Destination dest)
    {
        _destination = dest;
        Refresh();
    }

    private void ApplyTheme()
    {
        var dark = App.Theme.IsDark(_systemDark);
        var palette = ThemeCatalog.Resolve(App.Theme.Look, dark);
        App.ApplyThemeResources(Application.Current.Resources, palette);
        RootGrid.Background = BrushFrom(palette.Bg);
        LookBtn.Content = $"Look: {App.Theme.Look}";
        AppearanceBtn.Content = App.Theme.Appearance.ToString();
        ViewModeBtn.Content = App.Theme.ViewMode.ToString();
        DualPaneBtn.Content = App.Theme.DualPane ? "Dual pane · On" : "Dual pane";
        InspectorBtn.Content = App.Theme.InspectorOpen ? "Inspector · On" : "Inspector";

        InspectorColumn.Width = App.Theme.InspectorOpen ? new GridLength(300) : new GridLength(0);
        InspectorBorder.Visibility = App.Theme.InspectorOpen ? Visibility.Visible : Visibility.Collapsed;

        DualColumn.Width = App.Theme.DualPane ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
        DualPaneBorder.Visibility = App.Theme.DualPane ? Visibility.Visible : Visibility.Collapsed;

        RequestedTheme = dark ? ElementTheme.Dark : ElementTheme.Light;
    }

    private static SolidColorBrush BrushFrom(string hex)
    {
        hex = hex.TrimStart('#');
        var r = Convert.ToByte(hex[..2], 16);
        var g = Convert.ToByte(hex[2..4], 16);
        var b = Convert.ToByte(hex[4..6], 16);
        return new SolidColorBrush(Color.FromArgb(255, r, g, b));
    }

    private void Refresh()
    {
        ApplyTheme();
        MainContent.Children.Clear();
        SecondaryContent.Children.Clear();
        _selection.Clear();

        switch (_destination)
        {
            case Destination.Home:
                TitleText.Text = "Home";
                SubtitleText.Text = "Shelves from Desktop, Documents, Pictures, Downloads";
                PathText.Text = App.Library.HomeRoot;
                RenderHome();
                break;
            case Destination.Search:
                TitleText.Text = "Search";
                SubtitleText.Text = "Plain-language filename search across your places";
                PathText.Text = "";
                RenderFileCollection(App.Library.Search(SearchBox.Text ?? ""), "No matches yet — type a query above.");
                break;
            case Destination.Cleanup:
                TitleText.Text = "Cleanup";
                SubtitleText.Text = "Largest files in Downloads — select and trash";
                PathText.Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
                RenderFileCollection(App.Library.CleanupCandidates(), "Downloads looks tidy.");
                break;
            case Destination.Duplicates:
                TitleText.Text = "Duplicates";
                SubtitleText.Text = "Same name + size groups (quick scan)";
                PathText.Text = "";
                RenderDuplicates();
                break;
            case Destination.Timeline:
                TitleText.Text = "Timeline";
                SubtitleText.Text = "Files touched in the last two weeks";
                PathText.Text = "";
                RenderTimeline();
                break;
            case Destination.RecycleBin:
                TitleText.Text = "Recycle Bin";
                SubtitleText.Text = "FileRadar staging trash (undoable moves)";
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

        if (App.Theme.DualPane)
            RenderSecondary();

        StatusText.Text = $"{_destination} · Look {App.Theme.Look} · {App.Theme.ViewMode}";
    }

    private void RenderHome()
    {
        foreach (var shelf in App.Library.BuildHomeShelves())
        {
            MainContent.Children.Add(new TextBlock
            {
                Text = shelf.Title,
                FontSize = 16,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = (Brush)Application.Current.Resources["FrTextBrush"],
                Margin = new Thickness(4, 8, 0, 4)
            });
            MainContent.Children.Add(BuildItemsPanel(shelf.Items));
        }
    }

    private void RenderDuplicates()
    {
        var groups = App.Library.FindDuplicates();
        if (groups.Count == 0)
        {
            MainContent.Children.Add(EmptyLabel("No duplicate name+size groups found in a quick scan."));
            return;
        }

        foreach (var g in groups)
        {
            MainContent.Children.Add(new TextBlock
            {
                Text = $"{g.Items[0].Name} · {g.Items.Count} copies · wasted {FileItem.FormatBytes(g.WastedBytes)}",
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = (Brush)Application.Current.Resources["FrTextBrush"],
                Margin = new Thickness(4, 10, 0, 4)
            });
            MainContent.Children.Add(BuildItemsPanel(g.Items));
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
                FontSize = 16,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = (Brush)Application.Current.Resources["FrTextBrush"],
                Margin = new Thickness(4, 8, 0, 4)
            });
            MainContent.Children.Add(BuildItemsPanel(items));
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
        MainContent.Children.Add(BuildItemsPanel(items));
    }

    private void RenderSecondary()
    {
        SecondaryContent.Children.Add(new TextBlock
        {
            Text = App.Library.SecondaryPath,
            FontSize = 12,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"],
            TextWrapping = TextWrapping.Wrap
        });
        var items = App.Library.ListDirectory(App.Library.SecondaryPath, 200);
        SecondaryContent.Children.Add(BuildItemsPanel(items, secondary: true));
    }

    private static TextBlock EmptyLabel(string text) => new()
    {
        Text = text,
        Foreground = (Brush)Application.Current.Resources["FrMutedBrush"],
        Margin = new Thickness(8)
    };

    private Panel BuildItemsPanel(IReadOnlyList<FileItem> items, bool secondary = false)
    {
        if (App.Theme.ViewMode == ViewMode.List)
        {
            var list = new StackPanel { Spacing = 2 };
            foreach (var item in items)
                list.Children.Add(BuildListRow(item, secondary));
            return list;
        }

        var gv = new GridView
        {
            SelectionMode = ListViewSelectionMode.None,
            IsItemClickEnabled = true
        };
        gv.ItemClick += (_, args) =>
        {
            if (args.ClickedItem is FrameworkElement fe && fe.Tag is FileItem fi)
                SelectItem(fi, secondary);
        };
        gv.DoubleTapped += (_, _) =>
        {
            if (_selected is not null)
                OpenItem(_selected, secondary);
        };

        foreach (var item in items)
            gv.Items.Add(BuildCard(item));

        var host = new Grid();
        host.Children.Add(gv);
        return host;
    }

    private FrameworkElement BuildCard(FileItem item)
    {
        var radius = (double)Application.Current.Resources["FrRadius"];
        var border = new Border
        {
            Width = 148,
            Height = 168,
            Margin = new Thickness(0, 0, 10, 10),
            Padding = new Thickness(10),
            CornerRadius = new CornerRadius(radius),
            BorderThickness = new Thickness(1),
            BorderBrush = (Brush)Application.Current.Resources["FrBorderBrush"],
            Background = (Brush)Application.Current.Resources["FrPanel2Brush"],
            Tag = item
        };

        var stack = new StackPanel { Spacing = 8 };
        stack.Children.Add(new FontIcon
        {
            Glyph = item.KindGlyph,
            FontSize = 36,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 18, 0, 8),
            Foreground = (Brush)Application.Current.Resources["FrAccentBrush"]
        });
        stack.Children.Add(new TextBlock
        {
            Text = item.Name,
            TextWrapping = TextWrapping.WrapWholeWords,
            MaxLines = 2,
            TextTrimming = TextTrimming.CharacterEllipsis,
            FontSize = 13,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        });
        stack.Children.Add(new TextBlock
        {
            Text = item.SizeLabel,
            FontSize = 11,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        });
        border.Child = stack;

        border.PointerPressed += (_, _) => SelectItem(item, false);
        border.DoubleTapped += (_, _) => OpenItem(item, false);
        return border;
    }

    private FrameworkElement BuildListRow(FileItem item, bool secondary)
    {
        var row = new Grid
        {
            Padding = new Thickness(8, 6, 8, 6),
            ColumnSpacing = 12,
            Tag = item
        };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(160) });

        var icon = new FontIcon
        {
            Glyph = item.KindGlyph,
            Foreground = (Brush)Application.Current.Resources["FrAccentBrush"]
        };
        Grid.SetColumn(icon, 0);
        var name = new TextBlock
        {
            Text = item.Name,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["FrTextBrush"]
        };
        Grid.SetColumn(name, 1);
        var size = new TextBlock
        {
            Text = item.SizeLabel,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        };
        Grid.SetColumn(size, 2);
        var modified = new TextBlock
        {
            Text = item.ModifiedLabel,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["FrMutedBrush"]
        };
        Grid.SetColumn(modified, 3);

        row.Children.Add(icon);
        row.Children.Add(name);
        row.Children.Add(size);
        row.Children.Add(modified);
        row.Background = new SolidColorBrush(Colors.Transparent);
        row.PointerPressed += (_, _) => SelectItem(item, secondary);
        row.DoubleTapped += (_, _) => OpenItem(item, secondary);
        return row;
    }

    private void SelectItem(FileItem item, bool secondary)
    {
        _selected = item;
        _selection.Clear();
        _selection.Add(item);
        InspectorName.Text = item.Name;
        InspectorKind.Text = item.Kind.ToString();
        InspectorSize.Text = item.SizeLabel;
        InspectorModified.Text = $"Modified {item.ModifiedLabel}";
        InspectorPath.Text = item.Path;
        InspectorGlyph.Glyph = item.KindGlyph;

        if (secondary)
            StatusText.Text = $"Secondary · {item.Name}";
        else
            StatusText.Text = item.Path;
    }

    private async void OpenItem(FileItem item, bool secondary)
    {
        if (item.IsDirectory)
        {
            if (secondary)
                App.Library.NavigateSecondary(item.Path);
            else
            {
                App.Library.Navigate(item.Path);
                _destination = Destination.Browse;
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
            catch { StatusText.Text = "Could not open file."; }
        }
    }

    private void LookBtn_Click(object sender, RoutedEventArgs e)
    {
        App.Theme.CycleLook();
        Refresh();
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

    private void DualPaneBtn_Click(object sender, RoutedEventArgs e)
    {
        App.Theme.DualPane = !App.Theme.DualPane;
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
        if (_selection.Count == 0)
        {
            StatusText.Text = "Select files to trash.";
            return;
        }
        App.Library.MoveToTrash(_selection.ToList());
        StatusText.Text = $"Moved {_selection.Count} item(s) to FileRadar trash.";
        Refresh();
    }

    private void OpenBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null)
        {
            StatusText.Text = "Select a file first.";
            return;
        }
        OpenItem(_selected, false);
    }
}
