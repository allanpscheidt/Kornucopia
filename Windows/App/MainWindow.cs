using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Kornucopia.Core;

namespace Kornucopia.Windows;

public sealed class MainWindow : Window
{
    internal const int CardsPerPage = 100;
    public BoardStore Store { get; }
    public PreferenceStore Preferences { get; }
    public Locale Locale { get; }
    public bool SmokeMode { get; }
    public bool ClosingStarted { get; private set; }
    public int BlockedAttempts { get; private set; }
    public int StorageBlockedAttempts { get; private set; }
    public int VisibleTutorials { get; private set; }
    public int RenderedCards { get; private set; }
    Grid board = new();
    TextBlock footer = new();
    TextBox search = new();
    string query;
    string? lastStorageAlertKey;
    bool building;
    readonly Dictionary<string, StackPanel> cardsPanels = [];
    readonly Dictionary<string, ScrollViewer> columnScrolls = [];
    readonly Dictionary<(string Column, int Page), double> scrollOffsets = [];
    readonly Dictionary<string, int> columnPages = [];
    readonly Dictionary<string, int> renderedPages = [];
    readonly Dictionary<(string Column, bool Next), Button> pageButtons = [];
    Button retrySave = new();
    public MainWindow(BoardStore store, PreferenceStore preferences, Locale locale, bool smoke)
    {
        Store = store; Preferences = preferences; Locale = locale; SmokeMode = smoke; query = preferences.Value.Query ?? "";
        Title = "Kornucopia"; FontFamily = new FontFamily("Segoe UI"); Background = Ui.Canvas;
        MinWidth = Math.Min(1000, SystemParameters.WorkArea.Width); MinHeight = Math.Min(640, SystemParameters.WorkArea.Height);
        Width = Clamp(preferences.Value.Width, 1000, SystemParameters.WorkArea.Width, 1360);
        Height = Clamp(preferences.Value.Height, 640, SystemParameters.WorkArea.Height, 840);
        if (preferences.Value.Left is double left && preferences.Value.Top is double top && double.IsFinite(left) && double.IsFinite(top) && new Rect(left, top, Width, Height).IntersectsWith(SystemParameters.WorkArea)) { Left = left; Top = top; WindowStartupLocation = WindowStartupLocation.Manual; }
        else WindowStartupLocation = WindowStartupLocation.CenterScreen;
        if (preferences.Value.Maximized) WindowState = WindowState.Maximized;
        Store.Changed += Refresh;
        Store.WipBlocked += ShowWip;
        Store.StorageBlocked += ShowStorageBlocked;
        Locale.Changed += Build;
        Closing += ClosingWindow;
        PreviewKeyDown += Keyboard;
        Build();
        Loaded += (_, _) =>
        {
            if (SmokeMode) return;
            if (Store.RecoveryKey is string key)
            {
                var unsafeRoot = key == "recovery.unsafeRoot";
                var detail = Locale.T(key switch { "recovery.unsafeRoot" => "recovery.unsafeRoot", "recovery.backup" => "recovery.backupRecovered", "recovery.primary" => "recovery.previous", _ => "recovery.unreadable" });
                if (!unsafeRoot && Store.RecoveryErrorKey is string reason) detail += "\n\n" + T(reason);
                Ui.Alert(this, Locale.T(unsafeRoot ? "storage.alertTitle" : "recovery.title"), detail, Locale.T("action.understood"));
            }
            if ((Preferences.Error is not null || Preferences.ErrorKey is not null) && !(Store.RecoveryKey == "recovery.unsafeRoot" && Preferences.ErrorKey == "error.storageUnsafeRoot"))
                Ui.Alert(this, T("storage.alertTitle", "Board protection"), Preferences.ErrorKey is string preferenceKey ? T(preferenceKey) : Preferences.Error ?? "", T("action.understood"));
            if (Preferences.Value.EditingCardId is Guid id && Store.Find(id) is not null) Dispatcher.BeginInvoke(new Action(() => OpenCard(id)));
        };
    }
    static double Clamp(double value, double minimum, double maximum, double fallback) => Math.Clamp(double.IsFinite(value) ? value : fallback, Math.Min(minimum, maximum), Math.Max(minimum, maximum));
    string T(string key, string fallback = "", params (string Key, object Value)[] values) => Locale.T(key, fallback, values);
    public void Build()
    {
        CaptureOffsets();
        building = true;
        var shell = new Grid(); shell.RowDefinitions.Add(new() { Height = new GridLength(38) }); shell.RowDefinitions.Add(new() { Height = GridLength.Auto }); shell.RowDefinitions.Add(new() { Height = new GridLength(1, GridUnitType.Star) }); shell.RowDefinitions.Add(new() { Height = GridLength.Auto });
        var top = new DockPanel { Background = Ui.Night, LastChildFill = false, Margin = new Thickness(0) };
        var logo = new Image { Source = new BitmapImage(new Uri("pack://application:,,,/Resources/Cornucopia.png")), Width = 25, Height = 25, Margin = new Thickness(26, 0, 10, 0) }; top.Children.Add(logo);
        var brand = Ui.Text("KORNUCOPIA", 12, Brushes.White, true); brand.VerticalAlignment = VerticalAlignment.Center; brand.Margin = new Thickness(0); top.Children.Add(brand);
        var local = Ui.Text(T("board.localAccess", "Local access"), 11, Brushes.White); local.VerticalAlignment = VerticalAlignment.Center; local.Margin = new Thickness(0, 0, 28, 0); DockPanel.SetDock(local, Dock.Right); top.Children.Add(local);
        shell.Children.Add(top);
        var header = new Grid { Margin = new Thickness(28, 24, 28, 22) }; header.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) }); header.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        var heading = new StackPanel(); heading.Children.Add(Ui.Text(T("board.personalTitle", "PERSONAL ORGANIZATION"), 10, Ui.Accent, true));
        var boardTitle = Ui.Text(Store.Snapshot.BoardTitle.Length == 0 ? T("board.defaultTitle", "My board") : Store.Snapshot.BoardTitle, 28, Ui.Strong, true); boardTitle.TextWrapping = TextWrapping.NoWrap; boardTitle.TextTrimming = TextTrimming.CharacterEllipsis; boardTitle.ToolTip = boardTitle.Text; heading.Children.Add(boardTitle);
        heading.Children.Add(Ui.Text(T("board.summary", "Ideas, production, review and completed work."), 12, Ui.Secondary)); header.Children.Add(heading);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        search = Ui.Input(query, T("board.search", "Search cards")); search.Width = 200; search.ToolTip = T("board.search", "Search cards"); search.Margin = new Thickness(0, 0, 10, 0); search.TextChanged += (_, _) => { if (!building) { query = search.Text; ResetPagination(); SavePreferences(); Render(); } }; actions.Children.Add(search);
        actions.Children.Add(Ui.Button(T("action.newCard", "New card"), (_, _) => CreateCard("backlog"), true));
        var undo = Ui.Button("↶", (_, _) => Store.Undo()); undo.IsEnabled = Store.CanUndo; undo.ToolTip = T("action.undo") + " (Ctrl+Z)"; System.Windows.Automation.AutomationProperties.SetName(undo, T("action.undo")); actions.Children.Add(undo);
        var redo = Ui.Button("↷", (_, _) => Store.Redo()); redo.IsEnabled = Store.CanRedo; redo.ToolTip = T("action.redo") + " (Ctrl+Shift+Z)"; System.Windows.Automation.AutomationProperties.SetName(redo, T("action.redo")); actions.Children.Add(redo);
        actions.Children.Add(Ui.Button("⚙", (_, _) => OpenSettings())); System.Windows.Automation.AutomationProperties.SetName(actions.Children[^1], T("settings.title", "Settings"));
        Grid.SetColumn(actions, 1); header.Children.Add(actions); Grid.SetRow(header, 1); shell.Children.Add(header);
        board = new Grid { Margin = new Thickness(28, 0, 28, 20) };
        for (var i = 0; i < 4; i++) board.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetRow(board, 2); shell.Children.Add(board);
        var foot = new DockPanel { Background = Brushes.White, Margin = new Thickness(0), LastChildFill = true };
        retrySave = Ui.Button(T("action.retrySave"), (_, _) => { Store.Flush(); SavePreferences(); Refresh(); }); retrySave.Margin = new Thickness(8); DockPanel.SetDock(retrySave, Dock.Right); foot.Children.Add(retrySave);
        var settings = Ui.Button(T("board.doingLimit", "Limit in Doing: {limit}", ("limit", Store.Snapshot.WipLimit)), (_, _) => OpenSettings()); settings.Margin = new Thickness(8, 8, 28, 8); DockPanel.SetDock(settings, Dock.Right); foot.Children.Add(settings);
        footer = Ui.Text("", 11, Ui.Secondary); footer.Margin = new Thickness(28, 16, 0, 16); foot.Children.Add(footer); Grid.SetRow(foot, 3); shell.Children.Add(foot);
        Content = shell; building = false; Render();
    }
    void Refresh() { if (!Dispatcher.CheckAccess()) { Dispatcher.Invoke(Refresh); return; } lastStorageAlertKey = null; if (OwnedWindows.Count == 0) Build(); }
    public void Render()
    {
        CaptureOffsets(); columnScrolls.Clear(); renderedPages.Clear(); pageButtons.Clear();
        board.Children.Clear(); cardsPanels.Clear(); VisibleTutorials = 0; RenderedCards = 0;
        foreach (var column in Columns.All)
        {
            var index = Array.IndexOf(Columns.All, column);
            var grid = new Grid(); grid.RowDefinitions.Add(new() { Height = GridLength.Auto }); grid.RowDefinitions.Add(new() { Height = new GridLength(1, GridUnitType.Star) }); grid.RowDefinitions.Add(new() { Height = GridLength.Auto });
            var title = new DockPanel { Margin = new Thickness(0, 0, 0, 12) };
            var count = Store.Cards(column).Count(); var countText = column == "doing" ? count + "/" + Store.Snapshot.WipLimit : count.ToString();
            var add = Ui.Button("+", (_, _) => CreateCard(column)); add.Padding = new Thickness(7, 1, 7, 1); add.MinHeight = 28; DockPanel.SetDock(add, Dock.Right); title.Children.Add(add);
            System.Windows.Automation.AutomationProperties.SetName(add, T("action.addCard", "Add card") + ": " + T("column." + column + ".title"));
            var counter = Ui.Text(countText, 11, Ui.Secondary); counter.VerticalAlignment = VerticalAlignment.Center; counter.Margin = new Thickness(8, 0, 10, 0); DockPanel.SetDock(counter, Dock.Right); title.Children.Add(counter);
            var captions = new StackPanel(); captions.Children.Add(Ui.Text(T("column." + column + ".title"), 16, Ui.Ink, true)); captions.Children.Add(Ui.Text(T("column." + column + ".subtitle"), 11, Ui.Secondary)); title.Children.Add(captions); grid.Children.Add(title);
            var stack = new StackPanel(); cardsPanels[column] = stack;
            var tutorial = new StackPanel(); tutorial.Children.Add(Ui.Text(T("column." + column + ".tutorial.title"), 12, Ui.Strong, true));
            for (var step = 1; step <= 3; step++) tutorial.Children.Add(Ui.Text(T("column." + column + ".tutorial.step" + step, "", ("limit", Store.Snapshot.WipLimit)), 11, Ui.Secondary));
            tutorial.Children.Add(Ui.Text(T("column." + column + ".tutorial.next", "", ("limit", Store.Snapshot.WipLimit)), 11, Ui.Strong));
            var help = Ui.Round(tutorial, Brushes.White, 9, new Thickness(12)); help.Margin = new Thickness(0, 0, 0, 13); stack.Children.Add(help); VisibleTutorials++;
            var matching = Store.Cards(column, query);
            var matchingCount = matching.Count();
            var pageCount = Math.Max(1, (matchingCount + CardsPerPage - 1) / CardsPerPage);
            var page = Math.Clamp(columnPages.GetValueOrDefault(column), 0, pageCount - 1);
            columnPages[column] = page; renderedPages[column] = page;
            foreach (var card in matching.Skip(page * CardsPerPage).Take(CardsPerPage)) { stack.Children.Add(CardView(card)); RenderedCards++; }
            var append = Ui.Button(T("action.addCard", "Add card"), (_, _) => CreateCard(column)); append.HorizontalContentAlignment = HorizontalAlignment.Left; append.Margin = new Thickness(0, 4, 0, 15); stack.Children.Add(append);
            var scroll = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Padding = new Thickness(0, 0, 2, 0), AllowDrop = true, Tag = column };
            var offset = scrollOffsets.GetValueOrDefault((column, page)); scroll.Loaded += (_, _) => scroll.ScrollToVerticalOffset(offset); columnScrolls[column] = scroll;
            scroll.DragOver += HandleDragOver; scroll.Drop += (_, e) => HandleDrop(e, column, null); Grid.SetRow(scroll, 1); grid.Children.Add(scroll);
            if (pageCount > 1)
            {
                var pagination = new StackPanel { Margin = new Thickness(0, 12, 0, 0) };
                pagination.Children.Add(Ui.Text(T("pagination.range", "{first} to {last} of {count} notes", ("first", page * CardsPerPage + 1), ("last", Math.Min((page + 1) * CardsPerPage, matchingCount)), ("count", matchingCount)), 10, Ui.Secondary));
                var navigation = new Grid(); navigation.ColumnDefinitions.Add(new() { Width = GridLength.Auto }); navigation.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) }); navigation.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
                var previous = PageButton(column, false, page > 0); navigation.Children.Add(previous);
                var pageLabel = Ui.Text(T("pagination.page", "Page {page} of {pages}", ("page", page + 1), ("pages", pageCount)), 11, Ui.Secondary); pageLabel.TextAlignment = TextAlignment.Center; pageLabel.VerticalAlignment = VerticalAlignment.Center; pageLabel.Margin = new Thickness(5, 0, 5, 0); Grid.SetColumn(pageLabel, 1); navigation.Children.Add(pageLabel);
                var next = PageButton(column, true, page + 1 < pageCount); Grid.SetColumn(next, 2); navigation.Children.Add(next); pagination.Children.Add(navigation);
                Grid.SetRow(pagination, 2); grid.Children.Add(pagination);
            }
            var wrapper = Ui.Round(grid, Ui.Column, 16); wrapper.Margin = new Thickness(index == 0 ? 0 : 8, 0, index == 3 ? 0 : 8, 0); Grid.SetColumn(wrapper, index); board.Children.Add(wrapper);
        }
        var saveError = SaveErrorDetail;
        retrySave.Visibility = saveError is null ? Visibility.Collapsed : Visibility.Visible;
        footer.Text = saveError is null ? T("board.autosaved", "Saved automatically") + " · " + T(Store.Snapshot.Cards.Count == 1 ? "board.count.one" : "board.count.other", "{count} cards", ("count", Store.Snapshot.Cards.Count)) : T("error.save", "Unable to save. {detail}", ("detail", saveError));
        footer.Foreground = saveError is null ? Ui.Secondary : Ui.Warning;
    }
    void CaptureOffsets() { foreach (var (column, scroll) in columnScrolls) if (scroll.IsLoaded) scrollOffsets[(column, renderedPages.GetValueOrDefault(column))] = scroll.VerticalOffset; }
    void ResetPagination() { columnScrolls.Clear(); renderedPages.Clear(); columnPages.Clear(); scrollOffsets.Clear(); }
    Button PageButton(string column, bool next, bool enabled)
    {
        var label = T(next ? "pagination.next" : "pagination.previous", next ? "Next" : "Previous");
        var button = Ui.Button(next ? "›" : "‹", (_, _) => ChangePage(column, next ? 1 : -1)); button.IsEnabled = enabled; button.ToolTip = label; button.Padding = new Thickness(9, 3, 9, 3); button.Margin = new Thickness(0); button.MinHeight = 30; button.FontSize = 18;
        System.Windows.Automation.AutomationProperties.SetName(button, label + ": " + T("column." + column + ".title"));
        System.Windows.Automation.AutomationProperties.SetAutomationId(button, "pagination-" + column + (next ? "-next" : "-previous"));
        pageButtons[(column, next)] = button;
        return button;
    }
    void ChangePage(string column, int delta)
    {
        var pageCount = Math.Max(1, (Store.Cards(column, query).Count() + CardsPerPage - 1) / CardsPerPage);
        var page = Math.Clamp(columnPages.GetValueOrDefault(column) + delta, 0, pageCount - 1);
        if (page == columnPages.GetValueOrDefault(column)) return;
        columnPages[column] = page; Render();
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
        {
            if (pageButtons.TryGetValue((column, delta > 0), out var button) && button.IsEnabled) button.Focus();
            else if (pageButtons.TryGetValue((column, delta <= 0), out button) && button.IsEnabled) button.Focus();
        }));
    }
    void RevealCard(Guid id)
    {
        if (Store.Find(id) is not Card card) return;
        var position = 0;
        foreach (var match in Store.Cards(card.Column, query))
        {
            if (match.Id == id)
            {
                var page = position / CardsPerPage;
                if (columnPages.GetValueOrDefault(card.Column) != page) { columnPages[card.Column] = page; Render(); }
                Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
                {
                    if (cardsPanels.TryGetValue(card.Column, out var panel))
                        foreach (var button in panel.Children.OfType<Button>()) if (button.Tag is Guid visible && visible == id) { button.BringIntoView(); break; }
                }));
                return;
            }
            position++;
        }
    }
    bool MoveCard(Guid id, string column, Guid? before = null) { if (!Store.Move(id, column, before)) return false; RevealCard(id); return true; }
    internal string? SaveErrorDetail => Store.SaveErrorKey is string key ? T(key) : Store.SaveError ?? (Preferences.ErrorKey is string preferenceKey ? T(preferenceKey) : Preferences.Error);
    static string Preview(string text, int maximum)
    {
        if (text.Length <= maximum) return text;
        var end = maximum;
        if (char.IsHighSurrogate(text[end - 1]) && char.IsLowSurrogate(text[end])) end--;
        return text[..end] + "…";
    }
    UIElement CardView(Card card)
    {
        var body = new StackPanel(); body.Children.Add(Ui.Text("━━                              ···", 10, Ui.Secondary));
        var title = Ui.Text(card.Title.Trim().Length == 0 ? T("card.untitled", "Untitled") : Preview(card.Title, 256), 15, Ui.Ink, true); title.MaxHeight = 90; title.TextTrimming = TextTrimming.CharacterEllipsis; body.Children.Add(title);
        if (card.Notes.Length > 0) { var notes = Ui.Text(Preview(card.Notes, 600), 12); notes.MaxHeight = 86; notes.TextTrimming = TextTrimming.CharacterEllipsis; body.Children.Add(notes); }
        body.Children.Add(Ui.Text(T("board.noteStyle", "Sticky notes"), 10, Ui.Secondary));
        var button = new Button { Content = Ui.Round(body, Ui.Paper(card.Column), 10, new Thickness(16)), Margin = new Thickness(0, 0, 0, 12), Padding = new Thickness(0), BorderThickness = new Thickness(0), Background = Brushes.Transparent, HorizontalContentAlignment = HorizontalAlignment.Stretch, AllowDrop = true, Cursor = Cursors.Hand, Tag = card.Id };
        var dragged = false;
        button.Click += (_, _) => { if (!dragged) OpenCard(card.Id); dragged = false; }; button.ToolTip = T("menu.editCard", "Edit card");
        System.Windows.Automation.AutomationProperties.SetName(button, title.Text + ", " + T("column." + card.Column + ".title"));
        Point start = default;
        button.PreviewMouseLeftButtonDown += (_, e) => { start = e.GetPosition(button); dragged = false; };
        button.PreviewKeyDown += (_, _) => dragged = false;
        button.PreviewMouseMove += (_, e) =>
        {
            var position = e.GetPosition(button);
            if (e.LeftButton == MouseButtonState.Pressed && (Math.Abs(position.X - start.X) >= SystemParameters.MinimumHorizontalDragDistance || Math.Abs(position.Y - start.Y) >= SystemParameters.MinimumVerticalDragDistance))
            { dragged = true; DragDrop.DoDragDrop(button, new DataObject("Kornucopia.Card", card.Id.ToString()), DragDropEffects.Move); e.Handled = true; }
        };
        button.DragOver += HandleDragOver; button.Drop += (_, e) => HandleDrop(e, card.Column, card.Id);
        var menu = new ContextMenu();
        AddMenu(menu, T("menu.editCard", "Edit card"), () => OpenCard(card.Id));
        var move = new MenuItem { Header = T("menu.moveTo", "Move to") };
        foreach (var destination in Columns.All.Where(c => c != card.Column)) { var item = new MenuItem { Header = T("column." + destination + ".title") }; item.Click += (_, _) => MoveCard(card.Id, destination); move.Items.Add(item); }
        menu.Items.Add(move);
        AddMenu(menu, T("menu.moveFirst", "Move to beginning"), () => MoveCard(card.Id, card.Column, Store.Cards(card.Column).First().Id));
        AddMenu(menu, T("menu.moveLast", "Move to end"), () => MoveCard(card.Id, card.Column));
        menu.Items.Add(new Separator()); AddMenu(menu, T("action.deleteCard", "Delete card"), () => Store.Delete(card.Id)); button.ContextMenu = menu;
        return button;
    }
    static void AddMenu(ContextMenu menu, string label, Action action) { var item = new MenuItem { Header = label }; item.Click += (_, _) => action(); menu.Items.Add(item); }
    void HandleDragOver(object sender, DragEventArgs e) { e.Effects = e.Data.GetDataPresent("Kornucopia.Card") ? DragDropEffects.Move : DragDropEffects.None; e.Handled = true; }
    void HandleDrop(DragEventArgs e, string column, Guid? before)
    {
        e.Effects = e.Data.GetData("Kornucopia.Card") is string value && Guid.TryParse(value, out var id) && MoveCard(id, column, before) ? DragDropEffects.Move : DragDropEffects.None; e.Handled = true;
    }
    public Guid? CreateCard(string column, bool edit = true)
    {
        var id = Store.Create(column); if (id is Guid created && edit) { query = ""; ResetPagination(); columnPages[column] = (Store.Cards(column).Count() - 1) / CardsPerPage; Build(); OpenCard(created); } return id;
    }
    public void OpenCard(Guid id)
    {
        if (Store.Find(id) is null) return;
        Preferences.Save(Preferences.Value with { EditingCardId = id });
        var editor = new CardEditor(this, id); editor.ShowDialog();
        if (!ClosingStarted) Preferences.Save(Preferences.Value with { EditingCardId = null });
        if (!ClosingStarted) { Build(); RevealCard(id); }
    }
    void OpenSettings() { new SettingsDialog(this).ShowDialog(); if (!ClosingStarted) Build(); }
    void ShowWip()
    {
        BlockedAttempts++;
        if (!SmokeMode) Ui.Alert(OwnedWindows.Cast<Window>().FirstOrDefault(window => window.IsActive) ?? this, T("wip.title", "Work in progress limit"), T("wip.body", "The current limit is {limit}. Finish a card and move it to Review. Keep new ideas in Backlog. You can change the limit in Settings.", ("limit", Store.Snapshot.WipLimit)), T("action.understood"));
    }
    void ShowStorageBlocked(string key)
    {
        if (!Dispatcher.CheckAccess()) { Dispatcher.Invoke(() => ShowStorageBlocked(key)); return; }
        StorageBlockedAttempts++;
        if (lastStorageAlertKey == key) return;
        lastStorageAlertKey = key;
        if (!SmokeMode) Ui.Alert(OwnedWindows.Cast<Window>().FirstOrDefault(window => window.IsActive) ?? this, T("storage.alertTitle", "Board protection"), T(key), T("action.understood"));
    }
    void Keyboard(object sender, KeyEventArgs e)
    {
        if (KeyboardModifiers() != ModifierKeys.Control && KeyboardModifiers() != (ModifierKeys.Control | ModifierKeys.Shift)) return;
        if (e.Key == Key.N && OwnedWindows.Count == 0) { CreateCard("backlog"); e.Handled = true; }
        if (e.Key == Key.F && OwnedWindows.Count == 0) { search.Focus(); search.SelectAll(); e.Handled = true; }
        if (e.Key == Key.Z) { if ((KeyboardModifiers() & ModifierKeys.Shift) != 0) Store.Redo(); else Store.Undo(); e.Handled = true; }
    }
    static ModifierKeys KeyboardModifiers() => System.Windows.Input.Keyboard.Modifiers;
    public bool SavePreferences()
    {
        var bounds = WindowState == WindowState.Normal ? new Rect(Left, Top, Width, Height) : RestoreBounds;
        return Preferences.Save(Preferences.Value with { Width = bounds.Width, Height = bounds.Height, Left = bounds.Left, Top = bounds.Top, Maximized = WindowState == WindowState.Maximized, Query = query });
    }
    void ClosingWindow(object? sender, CancelEventArgs e)
    {
        if (!PrepareForClosing()) { e.Cancel = true; return; }
        ClosingStarted = true;
    }
    internal bool PrepareForClosing()
    {
        if (!DraftClose.CheckOwned(this)) return false;
        var saved = Store.Flush(); var preferencesSaved = SavePreferences();
        if ((!saved || !preferencesSaved) && !SmokeMode)
        {
            var detail = SaveErrorDetail ?? "";
            if (!ConfirmUnsaved(detail)) return false;
        }
        return true;
    }
    bool ConfirmUnsaved(string detail)
    {
        return Ui.Confirm(this, T("error.terminationTitle"), T("error.terminationBody", "", ("detail", detail)), T("action.keepOpen"), T("action.quitAnyway"));
    }
}
