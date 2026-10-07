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
            passed = true, version = "1.0.1", checks, languages = Locale.Supported,
            operatingSystem = Environment.OSVersion.VersionString,
            scope = "Owned WPF window, native editor controls, board commands and model persistence. Mouse drag gestures are not simulated. No desktop screenshot or personal data is read.",
            dataIsolation = "Fresh dedicated smoke directory; never the normal LocalAppData board."
        }, new JsonSerializerOptions { WriteIndented = true }));
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
