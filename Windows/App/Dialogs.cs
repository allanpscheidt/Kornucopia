using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Runtime.InteropServices;
using Kornucopia.Core;

namespace Kornucopia.Windows;

public sealed class CardEditor : Window
{
    readonly MainWindow main;
    readonly Guid id;
    public TextBox TitleInput { get; }
    public TextBox NotesInput { get; }
    public ComboBox ColumnInput { get; }
    readonly TextBlock saveStatus;
    bool syncing;
    bool titleDraft, notesDraft;
    public CardEditor(MainWindow main, Guid id)
    {
        this.main = main; this.id = id; Owner = main; Title = main.Locale.T("menu.editCard"); Width = 590; SizeToContent = SizeToContent.Height; ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterOwner; Background = Ui.Canvas; FontFamily = main.FontFamily;
        var card = main.Store.Find(id) ?? throw new ArgumentException("Card missing.");
        var panel = new StackPanel { Margin = new Thickness(24) }; panel.Children.Add(Ui.Text(main.Locale.T("menu.editCard"), 24, Ui.Strong, true));
        panel.Children.Add(Ui.Text(main.Locale.T("card.title"), 12, Ui.Secondary, true)); TitleInput = Ui.Input(card.Title, main.Locale.T("card.title")); panel.Children.Add(TitleInput);
        panel.Children.Add(Label(main.Locale.T("card.notes"))); NotesInput = Ui.Input(card.Notes, main.Locale.T("card.notes"), true); NotesInput.Height = 180; panel.Children.Add(NotesInput);
        panel.Children.Add(Label(main.Locale.T("card.column"))); ColumnInput = new ComboBox { Padding = new Thickness(8), Margin = new Thickness(0, 0, 0, 14), ItemsSource = Columns.All.Select(c => new ColumnOption(c, main.Locale.T("column." + c + ".title"))).ToList(), DisplayMemberPath = "Title", SelectedValuePath = "Id", SelectedValue = card.Column }; panel.Children.Add(ColumnInput);
        System.Windows.Automation.AutomationProperties.SetName(ColumnInput, main.Locale.T("card.column"));
        panel.Children.Add(Ui.Text(main.Locale.T("card.colorAutomatic"), 11, Ui.Secondary)); saveStatus = Ui.Text("", 11, Ui.Strong); panel.Children.Add(saveStatus);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 16, 0, 0) };
        actions.Children.Add(Ui.Button(main.Locale.T("action.deleteCard"), (_, _) =>
        {
            if (main.SmokeMode || Ui.Confirm(this, main.Locale.T("action.deleteCard"), main.Locale.T("card.deleteConfirmation").Replace("⌘Z", "Ctrl+Z"), main.Locale.T("action.cancel"), main.Locale.T("action.deleteCard"))) main.Store.Delete(id);
        }));
        var done = Ui.Button(main.Locale.T("action.done"), (_, _) => Close(), true); done.IsDefault = true; actions.Children.Add(done); panel.Children.Add(actions);
        MaxHeight = SystemParameters.WorkArea.Height;
        Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MaxHeight = Math.Max(320, SystemParameters.WorkArea.Height - 60) };
        TitleInput.TextChanged += (_, _) => { if (!syncing) { titleDraft = true; titleDraft = !main.Store.Update(id, title: TitleInput.Text); Sync(); } };
        NotesInput.TextChanged += (_, _) => { if (!syncing) { notesDraft = true; notesDraft = !main.Store.Update(id, notes: NotesInput.Text); Sync(); } };
        ColumnInput.SelectionChanged += (_, _) => { if (!syncing && ColumnInput.SelectedValue is string column) { main.Store.Update(id, column: column); Sync(); } };
        main.Store.Changed += Sync;
        Closing += (_, e) => { if (!ConfirmPendingDraft()) e.Cancel = true; };
        Closed += (_, _) => main.Store.Changed -= Sync;
        Loaded += (_, _) => { TitleInput.Focus(); TitleInput.CaretIndex = TitleInput.Text.Length; };
        Sync();
        PreviewKeyDown += (_, e) =>
        {
            if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Z) { main.Store.Undo(); e.Handled = true; }
            else if (Keyboard.Modifiers == (ModifierKeys.Control | ModifierKeys.Shift) && e.Key == Key.Z) { main.Store.Redo(); e.Handled = true; }
            else if (e.Key == Key.Escape) { Close(); e.Handled = true; }
        };
    }
    static TextBlock Label(string label) { var text = Ui.Text(label, 12, Ui.Secondary, true); text.Margin = new Thickness(0, 17, 0, 7); return text; }
    public bool HasPendingDraft => titleDraft || notesDraft;
    public bool ConfirmPendingDraft()
    {
        if (!HasPendingDraft || main.Store.Find(id) is null) return true;
        if (!DraftClose.CopyOrKeep(this, main, TitleInput.Text + "\n\n" + NotesInput.Text)) return false;
        titleDraft = false; notesDraft = false; return true;
    }
    void Sync()
    {
        var card = main.Store.Find(id); if (card is null) { Close(); return; }
        syncing = true;
        if (!titleDraft && TitleInput.Text != card.Title) TitleInput.Text = card.Title;
        if (!notesDraft && NotesInput.Text != card.Notes) NotesInput.Text = card.Notes;
        if (!Equals(ColumnInput.SelectedValue, card.Column)) ColumnInput.SelectedValue = card.Column;
        var error = main.SaveErrorDetail;
        saveStatus.Text = titleDraft || notesDraft ? main.Locale.T("error.unsavedDraft") : error is null ? main.Locale.T("card.autosaved") : main.Locale.T("error.save", "", ("detail", error));
        saveStatus.Foreground = error is null && !titleDraft && !notesDraft ? Ui.Strong : Ui.Warning;
        syncing = false;
    }
    sealed record ColumnOption(string Id, string Title);
}

public sealed class SettingsDialog : Window
{
    readonly MainWindow main;
    TextBox title = new(), limit = new();
    TextBlock error = new();
    bool syncing;
    bool titleDraft;
    public SettingsDialog(MainWindow main)
    {
        this.main = main; Owner = main; Width = 570; SizeToContent = SizeToContent.Height; ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterOwner; Background = Ui.Canvas; FontFamily = main.FontFamily;
        Build(); main.Store.Changed += Sync; main.Locale.Changed += Build;
        Closed += (_, _) => { main.Store.Changed -= Sync; main.Locale.Changed -= Build; };
        Closing += (_, e) => { if (!ConfirmPendingDraft()) e.Cancel = true; };
        PreviewKeyDown += (_, e) =>
        {
            if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Z) { main.Store.Undo(); e.Handled = true; }
            else if (Keyboard.Modifiers == (ModifierKeys.Control | ModifierKeys.Shift) && e.Key == Key.Z) { main.Store.Redo(); e.Handled = true; }
            else if (e.Key == Key.Escape) { Close(); e.Handled = true; }
        };
    }
    void Build()
    {
        var pendingTitle = titleDraft ? title.Text : main.Store.Snapshot.BoardTitle;
        syncing = true; Title = main.Locale.T("settings.title");
        var panel = new StackPanel { Margin = new Thickness(28) }; panel.Children.Add(Ui.Text(Title, 24, Ui.Strong, true));
        panel.Children.Add(Ui.Text(main.Locale.T("settings.boardName"), 12, Ui.Secondary, true)); title = Ui.Input(pendingTitle, main.Locale.T("settings.boardName")); panel.Children.Add(title);
        panel.Children.Add(Label(main.Locale.T("settings.language")));
        var languages = new[] { new LanguageOption("auto", main.Locale.T("settings.systemLanguage", "System: {language}", ("language", Locale.NativeNames[Array.IndexOf(Locale.Supported, Locale.SystemLanguage)]))) }.Concat(Locale.Supported.Select((id, i) => new LanguageOption(id, Locale.NativeNames[i]))).ToList();
        var language = new ComboBox { ItemsSource = languages, DisplayMemberPath = "Title", SelectedValuePath = "Id", SelectedValue = main.Preferences.Value.Language, Padding = new Thickness(8) }; panel.Children.Add(language);
        System.Windows.Automation.AutomationProperties.SetName(language, main.Locale.T("settings.language"));
        panel.Children.Add(Label(main.Locale.T("settings.wipTitle"), 17)); panel.Children.Add(Ui.Text(main.Locale.T("settings.wipDescription"), 13, Ui.Secondary));
        panel.Children.Add(Label(main.Locale.T("settings.wipMaximum"))); limit = Ui.Input(main.Store.Snapshot.WipLimit.ToString(), main.Locale.T("settings.wipMaximum")); panel.Children.Add(limit);
        error = Ui.Text(titleDraft ? main.Locale.T("error.unsavedDraft") : "", 11, Ui.Warning); panel.Children.Add(error);
        panel.Children.Add(Ui.Text(main.Locale.T("settings.storageLimits"), 11, Ui.Secondary));
        if (main.SaveErrorDetail is string preferenceError) panel.Children.Add(Ui.Text(main.Locale.T("error.save", "", ("detail", preferenceError)), 11, Ui.Warning));
        panel.Children.Add(Ui.Round(Ui.Text(main.Locale.T("settings.wipTip"), 12, Ui.Strong), Ui.Column, 10));
        var done = Ui.Button(main.Locale.T("action.done"), (_, _) => Close(), true); done.IsDefault = true; done.Margin = new Thickness(0, 20, 0, 0); panel.Children.Add(done);
        MaxHeight = SystemParameters.WorkArea.Height;
        Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MaxHeight = Math.Max(320, SystemParameters.WorkArea.Height - 60) }; syncing = false;
        title.TextChanged += (_, _) => { if (!syncing) { titleDraft = true; titleDraft = !main.Store.SetTitle(title.Text); error.Text = titleDraft ? main.Locale.T("error.unsavedDraft") : ""; } };
        limit.TextChanged += (_, _) =>
        {
            if (syncing) return;
            var minimum = Math.Max(1, main.Store.DoingCount);
            error.Text = int.TryParse(limit.Text, out var value) && main.Store.SetWip(value) ? titleDraft ? main.Locale.T("error.unsavedDraft") : "" : main.Locale.T("settings.invalidLimit", "Use an integer from {limit}.", ("limit", minimum));
        };
        language.SelectionChanged += (_, _) =>
        {
            if (syncing || language.SelectedValue is not string selected) return;
            main.Preferences.Save(main.Preferences.Value with { Language = selected }); main.SavePreferences(); main.Locale.Set(selected);
        };
    }
    static TextBlock Label(string label, double size = 12) { var text = Ui.Text(label, size, Ui.Secondary, true); text.Margin = new Thickness(0, 20, 0, 7); return text; }
    public bool HasPendingDraft => titleDraft;
    public bool ConfirmPendingDraft()
    {
        if (!titleDraft) return true;
        if (!DraftClose.CopyOrKeep(this, main, title.Text)) return false;
        titleDraft = false; return true;
    }
    void Sync()
    {
        syncing = true;
        if (!titleDraft && title.Text.Trim() != main.Store.Snapshot.BoardTitle) title.Text = main.Store.Snapshot.BoardTitle;
        if (int.TryParse(limit.Text, out var value) && value != main.Store.Snapshot.WipLimit) limit.Text = main.Store.Snapshot.WipLimit.ToString();
        syncing = false;
    }
    sealed record LanguageOption(string Id, string Title);
}

static class DraftClose
{
    public static bool CheckOwned(MainWindow main)
    {
        foreach (var child in main.OwnedWindows.Cast<Window>().ToArray())
            if (child is CardEditor card && !card.ConfirmPendingDraft() || child is SettingsDialog settings && !settings.ConfirmPendingDraft() || child is MainWindow nested && !CheckOwned(nested)) return false;
        return true;
    }
    public static bool CopyOrKeep(Window window, MainWindow main, string draft)
    {
        if (!Ui.Confirm(window, main.Locale.T("error.unsavedDraft"), main.Locale.T("error.unsavedDraftBody"), main.Locale.T("action.keepOpen"), main.Locale.T("action.copyAndClose"))) return false;
        try { Clipboard.SetText(draft); return true; }
        catch (Exception e) when (e is ExternalException or ArgumentException) { Ui.Alert(window, main.Locale.T("error.unsavedDraft"), main.Locale.T("error.copyDraft"), main.Locale.T("action.understood")); return false; }
    }
}
