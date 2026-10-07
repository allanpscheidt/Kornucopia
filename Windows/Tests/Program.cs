using System.Text.Json;
using Kornucopia.Core;
using Kornucopia.Windows;

var root = Path.Combine(Path.GetTempPath(), "kornucopia-core-test-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
int passed = 0;
void Check(bool value, string name) { if (!value) throw new InvalidOperationException(name); passed++; Console.WriteLine("PASS " + name); }
try
{
    var store = new BoardStore(Path.Combine(root, "board"));
    var locale = new Locale("auto"); var preservedTitle = "User title: ação 日本語"; store.SetTitle(preservedTitle);
    foreach (var language in Locale.Supported) { locale.Set(language); Check(locale.Language == language && locale.T("column.doing.title") != "column.doing.title" && !locale.T("column.doing.tutorial.step1", "", ("limit", 3)).Contains("{limit}") && store.Snapshot.BoardTitle == preservedTitle, "Locale and untouched user text: " + language); }
    var a = store.Create()!.Value; var b = store.Create()!.Value; var c = store.Create()!.Value;
    Check(store.Update(a, title: "Teste ação", notes: "Accents and 日本語\nSecond line") && store.Cards("backlog", "acao").Single().Id == a, "Unicode fields and accent-insensitive search");
    Check(store.Move(c, "backlog", a) && store.Cards("backlog").First().Id == c, "Reorder before card");
    Check(store.Move(c, "backlog") && store.Cards("backlog").Last().Id == c, "Reorder to end");
    Check(store.Move(a, "doing") && store.Move(b, "doing"), "Default WIP accepts two");
    var warnings = 0; store.WipBlocked += () => warnings++;
    Check(!store.Move(c, "doing") && !store.Update(c, column: "doing") && store.Create("doing") is null && warnings == 3 && store.DoingCount == 2, "WIP enforced for move, editor and create");
    Check(store.SetWip(3) && store.Move(c, "doing") && !store.SetWip(2), "Configurable WIP and safe reduction");
    Check(store.Move(b, "review") && store.Find(b)?.Color == "purple" && store.Move(c, "done") && store.Find(c)?.Color == "green", "Exclusive column colors");
    var before = store.Snapshot; Check(store.Delete(a) && store.Undo() && store.Snapshot.Cards.SequenceEqual(before.Cards) && store.Redo() && store.Find(a) is null, "Delete and undo/redo");
    Check(store.Flush() && File.Exists(store.BackupPath) && new BoardStore(store.DirectoryPath).Snapshot.Cards.SequenceEqual(store.Snapshot.Cards), "Atomic autosave, backup and reopen");
    var preferences = new PreferenceStore(store.DirectoryPath); Check(preferences.Save(new Preferences { Language = "ja", EditingCardId = b, Query = "sample" }), "Separate language/session preferences");
    var loadedPreferences = new PreferenceStore(store.DirectoryPath); loadedPreferences.Load(); Check(loadedPreferences.Value.Language == "ja" && loadedPreferences.Value.EditingCardId == b, "Reopen session preferences");
    var preferencePath = Path.Combine(store.DirectoryPath, "preferences.json"); File.WriteAllText(preferencePath, "{\"Language\":null,\"Query\":null}"); var invalidPreferences = new PreferenceStore(store.DirectoryPath); invalidPreferences.Load(); Check(invalidPreferences.Value.Language == "auto" && Directory.GetFiles(store.DirectoryPath, "preferences.json.corrupt-*").Length == 1, "Null preference fields preserve original file and use defaults");
    using (var json = JsonDocument.Parse(File.ReadAllBytes(store.DocumentPath)))
        Check(json.RootElement.GetProperty("cards")[0].GetProperty("createdAt").ValueKind == JsonValueKind.Number && json.RootElement.GetProperty("schemaVersion").GetInt32() == 1, "Swift schema and numeric epoch dates");
    var history = new BoardStore(Path.Combine(root, "history")); for (var i = 0; i < 120; i++) history.Create("done"); var undos = 0; while (history.Undo()) undos++; Check(undos == 100 && history.Snapshot.Cards.Count == 20, "Undo history bounded to 100");
    var many = new BoardStore(Path.Combine(root, "many")); for (var i = 0; i < 1201; i++) many.Create(); Check(many.Snapshot.Cards.Count == 1201 && new BoardStore(many.DirectoryPath).Snapshot.Cards.Count == 1201, "No artificial card count limit");
    var damaged = new BoardStore(Path.Combine(root, "damaged")); var damagedId = damaged.Create()!.Value; damaged.Update(damagedId, title: "Previous valid state"); var recoverExpected = damaged.Snapshot; damaged.Update(damagedId, title: "Latest state"); var bad = "{damaged"; File.WriteAllText(damaged.DocumentPath, bad); var recovered = new BoardStore(damaged.DirectoryPath); Check(recovered.RecoveryKey == "recovery.backup" && recovered.Snapshot.Cards.SequenceEqual(recoverExpected.Cards) && File.ReadAllText(Directory.GetFiles(damaged.DirectoryPath, "*.corrupt-*.json").Single()) == bad, "Corruption recovery preserves original bytes");
    var nullCard = new BoardStore(Path.Combine(root, "null-card")); nullCard.Create("done"); nullCard.SetTitle("Fixture board"); File.WriteAllText(nullCard.DocumentPath, "{\"schemaVersion\":1,\"cards\":[null],\"boardTitle\":\"fixture\",\"wipLimit\":2}"); var nullRecovered = new BoardStore(nullCard.DirectoryPath); Check(nullRecovered.RecoveryKey == "recovery.backup" && nullRecovered.Snapshot.Cards.Count == 1 && Directory.GetFiles(nullCard.DirectoryPath, "*.corrupt-*.json").Length == 1, "Null card recovers valid backup without a crash");
    var blocked = Path.Combine(root, "file-instead-of-directory"); File.WriteAllText(blocked, "fixture"); var failure = new BoardStore(blocked); failure.Create(); Check(failure.SaveError is not null && failure.Snapshot.Cards.Count == 1 && !failure.Flush(), "Save failures keep cards in memory");
    Console.WriteLine($"PASS: {passed} checks; isolated temporary data only.");
}
finally { Directory.Delete(root, true); }
