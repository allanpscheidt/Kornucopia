using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Kornucopia.Core;

namespace Kornucopia.Windows;

internal static class Smoke
{
    public static async Task Run(MainWindow main, string output)
    {
        Directory.CreateDirectory(output);
        var checks = new List<string>();
        void Check(bool value, string name) { if (!value) throw new InvalidOperationException(name); checks.Add(name); }
        var id = main.CreateCard("backlog", false) ?? throw new InvalidOperationException("create");
        var editor = new CardEditor(main, id); editor.Show(); await Task.Delay(120);
        editor.TitleInput.Text = "Studio sample"; editor.NotesInput.Text = "Fictional task for the application smoke test.";
        editor.ColumnInput.SelectedValue = "review";
        Check(main.Store.Find(id)?.Title == "Studio sample" && main.Store.Find(id)?.Notes.Contains("Fictional") == true && main.Store.Find(id)?.Column == "review", "Native editor fields autosave and move");
        editor.Close();
        var a = main.CreateCard("doing", false)!.Value; var b = main.CreateCard("doing", false)!.Value;
        var c = main.CreateCard("backlog", false)!.Value; main.Store.Update(c, title: "Next idea");
        Check(!main.Store.Move(c, "doing") && main.Store.DoingCount == 2 && main.BlockedAttempts == 1, "WIP blocks entry through the shared move path");
        Check(main.Store.SetWip(3) && main.Store.Move(c, "doing") && main.Store.DoingCount == 3, "Configurable WIP accepts a third card");
        Check(main.Store.Move(c, "doing", a) && main.Store.Cards("doing").First().Id == c, "Reorder before a destination card");
        Check(main.Store.Undo() && main.Store.Redo(), "Undo and redo");
        main.Store.Move(b, "done"); main.Store.Update(a, title: "In production"); main.Store.Update(b, title: "Completed sample");
        var removed = main.CreateCard("backlog", false)!.Value;
        Check(main.Store.Delete(removed) && main.Store.Find(removed) is null, "Delete card");
        Check(main.Store.Flush(), "Atomic board save");
        var reopened = new BoardStore(main.Store.DirectoryPath);
        Check(reopened.Snapshot.Cards.SequenceEqual(main.Store.Snapshot.Cards) && reopened.Snapshot.WipLimit == 3, "Reopen preserves all card fields, order and WIP");
        var scrollingFixtures = Enumerable.Range(0, 12).Select(_ => main.CreateCard("backlog", false)!.Value).ToArray();
        await Task.Delay(120); main.UpdateLayout();
        ScrollViewer BacklogViewport() => Descendants<ScrollViewer>(main).Where(view => view.AllowDrop).OrderBy(view => view.TransformToAncestor(main).Transform(new Point()).X).First();
        var viewport = BacklogViewport(); viewport.ScrollToVerticalOffset(250); await Task.Delay(120);
        var previousOffset = viewport.VerticalOffset; Check(previousOffset > 100, "Long column scrolls through native viewport");
        main.Build(); await Task.Delay(120); main.UpdateLayout();
        Check(Math.Abs(BacklogViewport().VerticalOffset - previousOffset) < 1, "UI reconstruction preserves the visible scroll position");
        foreach (var fixture in scrollingFixtures) main.Store.Delete(fixture);
        await PagingStress(main, output, Check);
        foreach (var language in Locale.Supported)
        {
            Check(main.Preferences.Save(main.Preferences.Value with { Language = language }), "Persistent language preference: " + language);
            main.Locale.Set(language); main.UpdateLayout(); await Task.Delay(180);
            var settings = new SettingsDialog(main); settings.Show(); await Task.Delay(100);
            var languagePicker = Descendants<ComboBox>(settings).First(control => AutomationProperties.GetName(control) == main.Locale.T("settings.language"));
            Check(settings.Title == main.Locale.T("settings.title") && Equals(languagePicker.SelectedValue, language) && Descendants<Button>(settings).Any(button => Equals(button.Content, main.Locale.T("action.done"))), "Native settings labels and language picker: " + language);
            settings.Close();
            var localizedConfirmation = false;
            _ = main.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() =>
            {
                var dialog = Application.Current.Windows.Cast<Window>().Last(window => window.Owner == main);
                var buttons = Descendants<Button>(dialog).ToArray();
                var cancel = buttons.FirstOrDefault(button => Equals(button.Content, main.Locale.T("action.cancel")));
                localizedConfirmation = cancel is not null && buttons.Any(button => Equals(button.Content, main.Locale.T("action.deleteCard")));
                if (cancel is not null) cancel.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); else dialog.Close();
            }));
            var accepted = Ui.Confirm(main, main.Locale.T("action.deleteCard"), main.Locale.T("card.deleteConfirmation").Replace("⌘Z", "Ctrl+Z"), main.Locale.T("action.cancel"), main.Locale.T("action.deleteCard"));
            Check(localizedConfirmation && !accepted && main.Store.Find(id) is not null, "Native delete confirmation uses the chosen language and Cancel preserves the card: " + language);
            Check(main.VisibleTutorials == 4 && main.RenderedCards == 4, "Visible columns and tutorials: " + language);
            Check(!main.Locale.T("column.doing.tutorial.step1", "", ("limit", 3)).Contains("{limit}"), "Tutorial placeholder: " + language);
            Capture(main, Path.Combine(output, language + ".png"));
        }
        Check(main.SavePreferences(), "Session preferences save");
        File.WriteAllText(Path.Combine(output, "smoke-report.json"), JsonSerializer.Serialize(new
        {
            passed = true, version = typeof(MainWindow).Assembly.GetName().Version?.ToString(3), checks, languages = Locale.Supported,
            operatingSystem = Environment.OSVersion.VersionString,
            scope = "Owned WPF window, native editor controls, board commands, bounded column pagination, global search and model persistence. Mouse drag gestures are not simulated. No desktop screenshot or personal data is read.",
            dataIsolation = "Fresh dedicated smoke directory; never the normal LocalAppData board."
        }, new JsonSerializerOptions { WriteIndented = true }));
    }
    static async Task PagingStress(MainWindow owner, string output, Action<bool, string> check)
    {
        var directory = Path.Combine(output, "paging-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var fixtures = new List<Card>();
        foreach (var (column, count) in new[] { ("backlog", 1205), ("doing", 2), ("review", 1101), ("done", 1001) })
            for (var index = 0; index < count; index++)
                fixtures.Add(new Card { Column = column, Color = Columns.Color(column), Title = column + " synthetic " + index.ToString("D4"), Notes = column == "backlog" && index == 1204 ? "rare-off-page-match" : column == "backlog" && index == 1 ? new string('L', 200000) : "Synthetic note." });
        File.WriteAllBytes(Path.Combine(directory, "board.json"), JsonSerializer.SerializeToUtf8Bytes(new BoardSnapshot { Cards = fixtures.AsReadOnly() }, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }));
        var store = new BoardStore(directory);
        var preferences = new PreferenceStore(directory); preferences.Load();
        var window = new MainWindow(store, preferences, new Locale("en"), true) { Owner = owner };
        window.Show();
        try
        {
            async Task Settle() { await Task.Delay(80); window.UpdateLayout(); }
            ScrollViewer Viewport(string column) => Descendants<ScrollViewer>(window).Single(view => Equals(view.Tag, column));
            Button[] Visible(string column) => Descendants<Button>(Viewport(column)).Where(button => button.Tag is Guid).ToArray();
            Button? Pager(string column, bool next) => Descendants<Button>(window).SingleOrDefault(button => AutomationProperties.GetAutomationId(button) == "pagination-" + column + (next ? "-next" : "-previous"));
            void Bound()
            {
                foreach (var column in Columns.All) check(Visible(column).Length <= MainWindow.CardsPerPage, "At most 100 materialized card controls: " + column);
                check(Descendants<Button>(window).Count(button => button.Tag is Guid) == window.RenderedCards && window.RenderedCards <= 4 * MainWindow.CardsPerPage, "Total card controls agree with the bounded rendered count");
            }
            async Task ClickPage(string column, bool next)
            {
                var button = Pager(column, next) ?? throw new InvalidOperationException("Pagination button missing.");
                check(button.IsEnabled, "Requested page is available: " + column);
                button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); await Settle();
            }
            void MoveFromMenu(Button card, string column)
            {
                var move = card.ContextMenu.Items.OfType<MenuItem>().Single(item => Equals(item.Header, window.Locale.T("menu.moveTo")));
                var destination = move.Items.OfType<MenuItem>().Single(item => Equals(item.Header, window.Locale.T("column." + column + ".title")));
                destination.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
            }
            await Settle();
            check(store.Snapshot.Cards.Count == 3309 && store.SaveError is null, "Thousands of synthetic notes load without truncating the board");
            Bound();
            check(Visible("backlog").Length == 100 && Visible("review").Length == 100 && Visible("done").Length == 100 && Visible("doing").Length == 2, "Large columns materialize their first page only");
            check(Descendants<TextBlock>(Viewport("backlog")).Where(text => text.Text.StartsWith("LLLL", StringComparison.Ordinal)).All(text => text.Text.Length <= 601) && store.Cards("backlog").ElementAt(1).Notes.Length == 200000, "Long note previews remain bounded while stored text stays complete");
            Viewport("backlog").ScrollToVerticalOffset(250); await Settle();
            var offset = Viewport("backlog").VerticalOffset;
            check(offset > 100, "A page with 100 notes has an independent native scroll viewport");
            await ClickPage("backlog", true);
            check((Guid)Visible("backlog")[0].Tag == store.Cards("backlog").ElementAt(100).Id && Viewport("backlog").VerticalOffset == 0, "Next page uses global order and starts at its own scroll position");
            await ClickPage("backlog", false);
            check(Math.Abs(Viewport("backlog").VerticalOffset - offset) < 1, "Returning to a page restores that page's scroll position");
            window.Build(); await Settle();
            check(Math.Abs(Viewport("backlog").VerticalOffset - offset) < 1, "Reconstruction preserves pagination and page scroll");
            foreach (var column in new[] { "backlog", "review", "done" })
            {
                var seen = new List<Guid>();
                var page = 0;
                while (true)
                {
                    var ids = Visible(column).Select(button => (Guid)button.Tag).ToArray();
                    check(ids.SequenceEqual(store.Cards(column).Skip(page * MainWindow.CardsPerPage).Take(MainWindow.CardsPerPage).Select(card => card.Id)), "Page preserves global order: " + column + " " + (page + 1));
                    seen.AddRange(ids);
                    if (Pager(column, true)?.IsEnabled != true) break;
                    await ClickPage(column, true); page++;
                }
                check(seen.SequenceEqual(store.Cards(column).Select(card => card.Id)), "Every stored note remains reachable across pages: " + column);
            }
            check(Visible("backlog").Length == 5 && Visible("review").Length == 1 && Visible("done").Length == 1, "Last pages show the remaining notes without duplicates");
            var deleted = (Guid)Visible("done")[0].Tag;
            check(store.Delete(deleted), "Delete the only note on a last page"); await Settle();
            check(Visible("done").Length == 100 && (Guid)Visible("done")[^1].Tag == store.Cards("done").Last().Id && Pager("done", true)?.IsEnabled == false, "Deleting a last page clamps to the preceding populated page");
            var search = Descendants<TextBox>(window).Single(input => AutomationProperties.GetName(input) == window.Locale.T("board.search"));
            var rare = store.Cards("backlog").Single(card => card.Notes == "rare-off-page-match").Id;
            search.Text = "rare-off-page-match"; await Settle();
            check(window.RenderedCards == 1 && (Guid)Visible("backlog").Single().Tag == rare, "Global search reaches notes beyond the current page");
            search.Text = ""; await Settle();
            check((Guid)Visible("backlog")[0].Tag == store.Cards("backlog").First().Id && Viewport("backlog").VerticalOffset == 0, "Clearing search restarts pages without changing stored order");
            await ClickPage("backlog", true);
            var reordered = (Guid)Visible("backlog")[0].Tag;
            var top = Visible("backlog")[0].ContextMenu.Items.OfType<MenuItem>().Single(item => Equals(item.Header, window.Locale.T("menu.moveFirst")));
            top.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); await Settle();
            check(store.Cards("backlog").First().Id == reordered && (Guid)Visible("backlog")[0].Tag == reordered, "Context reorder moves a later-page note to the global first position and reveals it");
            var bottom = Visible("backlog")[0].ContextMenu.Items.OfType<MenuItem>().Single(item => Equals(item.Header, window.Locale.T("menu.moveLast")));
            bottom.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); await Settle();
            check(store.Cards("backlog").Last().Id == reordered && (Guid)Visible("backlog")[^1].Tag == reordered, "Context reorder to the global end reveals the last page");
            var before = store.Snapshot.Cards.ToArray();
            MoveFromMenu(Visible("backlog")[^1], "doing"); await Settle();
            check(window.BlockedAttempts == 1 && store.DoingCount == 2 && store.Snapshot.Cards.SequenceEqual(before), "WIP blocks a move from a later page without changing data or order");
            MoveFromMenu(Visible("doing")[0], "review"); await Settle();
            MoveFromMenu(Visible("backlog")[^1], "doing"); await Settle();
            check(store.Find(reordered)?.Column == "doing" && store.DoingCount == 2 && Visible("doing").Any(button => (Guid)button.Tag == reordered), "Moving after a completed stage frees WIP and reveals the destination note");
            Bound();
            var edited = store.Cards("backlog").First();
            var editor = new CardEditor(window, edited.Id) { Tag = edited.Id }; editor.Show(); await Settle();
            editor.TitleInput.Text = new string('A', 4097);
            check(editor.TitleInput.Text.Length == 4097 && store.Find(edited.Id)?.Title == edited.Title && window.StorageBlockedAttempts > 0, "Storage rejection preserves the typed draft and the last valid snapshot");
            async Task<bool> CancelDraftPrompt(Action close)
            {
                var labeled = false;
                _ = window.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() =>
                {
                    var dialog = Application.Current.Windows.Cast<Window>().Last(child => child.Owner == editor);
                    var buttons = Descendants<Button>(dialog).ToArray();
                    var keep = buttons.SingleOrDefault(button => Equals(button.Content, window.Locale.T("action.keepOpen")));
                    labeled = keep is not null && buttons.Any(button => Equals(button.Content, window.Locale.T("action.copyAndClose")));
                    if (keep is not null) keep.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); else dialog.Close();
                }));
                close(); await Settle(); return labeled;
            }
            check(await CancelDraftPrompt(window.Close) && window.IsVisible && editor.IsVisible && !window.ClosingStarted && editor.TitleInput.Text.Length == 4097, "Owner close checks pending child drafts before WPF can bypass child Closing");
            var sessionAccepted = true;
            check(await CancelDraftPrompt(() => sessionAccepted = window.PrepareForClosing()) && !sessionAccepted && editor.TitleInput.Text.Length == 4097, "SessionEnding shares the cancellable pending draft guard without ending the OS session");
            editor.NotesInput.Text = "Accepted synthetic notes while a title draft is pending.";
            check(editor.TitleInput.Text.Length == 4097 && store.Find(edited.Id)?.Title == edited.Title && store.Find(edited.Id)?.Notes == editor.NotesInput.Text, "Saving another field preserves a rejected editor draft");
            editor.TitleInput.Text = edited.Title; editor.Close(); await Settle();
            foreach (var language in Locale.Supported)
            {
                window.Locale.Set(language); await Settle();
                var next = Pager("backlog", true)!;
                check(Equals(next.ToolTip, window.Locale.T("pagination.next")) && !window.Locale.T("pagination.page", "", ("page", 1), ("pages", 13)).Contains('{'), "Pagination controls and placeholders translate: " + language);
            }
            check(new BoardStore(directory).Snapshot.Cards.SequenceEqual(store.Snapshot.Cards), "Pagination, search and UI commands preserve full persisted data");
        }
        finally
        {
            // A failed assertion must not leave a synthetic rejected draft in a modal cleanup prompt.
            foreach (var editor in window.OwnedWindows.Cast<Window>().OfType<CardEditor>().ToArray())
            {
                if (editor.Tag is Guid id && store.Find(id) is Card card)
                {
                    editor.TitleInput.Text = card.Title;
                    editor.NotesInput.Text = card.Notes;
                }
                editor.Close();
            }
            window.Close();
        }
    }
    static IEnumerable<T> Descendants<T>(DependencyObject parent) where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            if (child is T match) yield return match;
            foreach (var nested in Descendants<T>(child)) yield return nested;
        }
    }
    static void Capture(Window window, string path)
    {
        window.UpdateLayout();
        var dpi = VisualTreeHelper.GetDpi(window);
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth * dpi.DpiScaleX), (int)Math.Ceiling(window.ActualHeight * dpi.DpiScaleY), 96 * dpi.DpiScaleX, 96 * dpi.DpiScaleY, PixelFormats.Pbgra32);
        bitmap.Render(window);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path); encoder.Save(stream);
    }
}
