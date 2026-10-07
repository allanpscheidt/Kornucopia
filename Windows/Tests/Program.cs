using System.Text.Json;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Text;
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
    var many = new BoardStore(Path.Combine(root, "many")); for (var i = 0; i < 1201; i++) many.Create(); Check(many.Snapshot.Cards.Count == 1201 && new BoardStore(many.DirectoryPath).Snapshot.Cards.Count == 1201, "Many cards within the safety budget");
    var damaged = new BoardStore(Path.Combine(root, "damaged")); var damagedId = damaged.Create()!.Value; damaged.Update(damagedId, title: "Previous valid state"); var recoverExpected = damaged.Snapshot; damaged.Update(damagedId, title: "Latest state"); var bad = "{damaged"; File.WriteAllText(damaged.DocumentPath, bad); var recovered = new BoardStore(damaged.DirectoryPath); Check(recovered.RecoveryKey == "recovery.backup" && recovered.Snapshot.Cards.SequenceEqual(recoverExpected.Cards) && File.ReadAllText(Directory.GetFiles(damaged.DirectoryPath, "*.corrupt-*.json").Single()) == bad, "Corruption recovery preserves original bytes");
    var nullCard = new BoardStore(Path.Combine(root, "null-card")); nullCard.Create("done"); nullCard.SetTitle("Fixture board"); File.WriteAllText(nullCard.DocumentPath, "{\"schemaVersion\":1,\"cards\":[null],\"boardTitle\":\"fixture\",\"wipLimit\":2}"); var nullRecovered = new BoardStore(nullCard.DirectoryPath); Check(nullRecovered.RecoveryKey == "recovery.backup" && nullRecovered.Snapshot.Cards.Count == 1 && Directory.GetFiles(nullCard.DirectoryPath, "*.corrupt-*.json").Length == 1, "Null card recovers valid backup without a crash");
    var blocked = Path.Combine(root, "file-instead-of-directory"); File.WriteAllText(blocked, "fixture"); var failure = new BoardStore(blocked); failure.Create(); Check(failure.SaveError is not null && failure.Snapshot.Cards.Count == 1 && !failure.Flush(), "Save failures keep cards in memory");

    var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    string Folder(string name) { var path = Path.Combine(root, name); Directory.CreateDirectory(path); return path; }
    byte[] Encode(BoardSnapshot value) => JsonSerializer.SerializeToUtf8Bytes(value, options);
    BoardStore Fixture(string name, BoardSnapshot value) { var directory = Folder(name); File.WriteAllBytes(Path.Combine(directory, "board.json"), Encode(value)); return new BoardStore(directory); }
    BoardSnapshot CardsFixture(int count, string notes = "") => new() { Cards = Enumerable.Range(0, count).Select(_ => new Card { Notes = notes }).ToArray() };
    void RejectFixture(string name, byte[] bytes, string key)
    {
        var directory = Folder(name); var primaryPath = Path.Combine(directory, "board.json"); File.WriteAllBytes(primaryPath, bytes);
        var valid = Encode(new BoardSnapshot { BoardTitle = "Preserved valid backup", Cards = [new Card { Title = "Safe fixture" }] }); File.WriteAllBytes(Path.Combine(directory, "board.backup.json"), valid);
        var rejected = new BoardStore(directory);
        var quarantine = Directory.GetFiles(directory, "*.corrupt-*.json").Single();
        Check(rejected.RecoveryKey == "recovery.backup" && rejected.RecoveryErrorKey == key && rejected.Snapshot.BoardTitle == "Preserved valid backup" && File.ReadAllBytes(quarantine).SequenceEqual(bytes), name + ": bounded refusal recovers backup and preserves exact source");
        var again = new BoardStore(directory); Check(again.Snapshot.BoardTitle == "Preserved valid backup" && Directory.GetFiles(directory, "*.corrupt-*.json").Length == 1 && again.Flush(), name + ": repeated startup does not repeat quarantine");
    }
    RejectFixture("too-many-cards", Encode(CardsFixture(BoardBudget.CardCount + 1)), "error.storageCardCount");
    RejectFixture("board-title-bytes", Encode(new BoardSnapshot { BoardTitle = new string('x', BoardBudget.BoardTitleBytes + 1) }), "error.storageFieldSize");
    RejectFixture("unicode-title-bytes", Encode(new BoardSnapshot { Cards = [new Card { Title = new string('日', 1366) }] }), "error.storageFieldSize");
    RejectFixture("notes-bytes", Encode(CardsFixture(1, new string('n', BoardBudget.CardNotesBytes + 1))), "error.storageFieldSize");
    RejectFixture("aggregate-text", Encode(CardsFixture(33, new string('n', BoardBudget.CardNotesBytes))), "error.storageTextBudget");
    RejectFixture("unknown-deep-json", Encoding.UTF8.GetBytes("{\"unknown\":" + new string('[', 40) + "0" + new string(']', 40) + "}"), "error.storageStructure");
    RejectFixture("unknown-token-work", Encoding.UTF8.GetBytes("{\"unknown\":[" + string.Join(',', Enumerable.Repeat("0", BoardBudget.JsonTokens)) + "]}"), "error.storageStructure");
    var sparse = Folder("sparse-oversized"); var sparsePath = Path.Combine(sparse, "board.json"); var sparseLength = OperatingSystem.IsWindows() ? 64L * 1024 * 1024 : 4L * 1024 * 1024 * 1024;
    using (var file = new FileStream(sparsePath, FileMode.CreateNew)) file.SetLength(sparseLength);
    File.WriteAllBytes(Path.Combine(sparse, "board.backup.json"), Encode(new BoardSnapshot { BoardTitle = "Sparse backup" }));
    var watch = Stopwatch.StartNew(); var sparseStore = new BoardStore(sparse); var sparseCopy = Directory.GetFiles(sparse, "*.corrupt-*.json").Single();
    Check(watch.Elapsed < TimeSpan.FromSeconds(5) && sparseStore.RecoveryErrorKey == "error.storageFileSize" && sparseStore.Snapshot.BoardTitle == "Sparse backup" && new FileInfo(sparseCopy).Length == sparseLength, "Oversized sparse file is rejected before allocation and renamed without reading its contents");

    var capped = Fixture("card-count-mutation", CardsFixture(BoardBudget.CardCount)); var cappedBytes = File.ReadAllBytes(capped.DocumentPath); var capWarnings = 0; capped.StorageBlocked += _ => capWarnings++;
    Check(capped.Create() is null && capWarnings == 1 && !capped.CanUndo && capped.Snapshot.Cards.Count == BoardBudget.CardCount && File.ReadAllBytes(capped.DocumentPath).SequenceEqual(cappedBytes), "Rejected create at card budget changes neither data nor history");
    var literal = Fixture("literal-mutations", new BoardSnapshot { Cards = [new Card { Title = "Original literal" }] }); var literalId = literal.Snapshot.Cards[0].Id;
    Check(!literal.Update(literalId, title: new string('x', BoardBudget.CardTitleBytes + 1)) && !literal.Update(literalId, notes: new string('n', BoardBudget.CardNotesBytes + 1)) && !literal.SetTitle(new string('x', BoardBudget.BoardTitleBytes + 1)) && literal.Find(literalId)?.Title == "Original literal" && !literal.CanUndo, "Oversized mutation fields preserve literal snapshot and undo history");
    var aggregate = Fixture("aggregate-mutation", CardsFixture(32, new string('n', BoardBudget.CardNotesBytes)));
    Check(!aggregate.Update(aggregate.Snapshot.Cards[0].Id, title: "x") && aggregate.StorageErrorKey == "error.storageTextBudget" && new BoardStore(aggregate.DirectoryPath).Snapshot.Cards.SequenceEqual(aggregate.Snapshot.Cards), "Aggregate text budget is enforced on mutation and the accepted board reopens");
    var escaped = Fixture("escaped-file-budget", CardsFixture(10, new string('\u0001', BoardBudget.CardNotesBytes))); var escapedId = escaped.Create()!.Value; var escapedBefore = File.ReadAllBytes(escaped.DocumentPath);
    Check(!escaped.Update(escapedId, notes: new string('\u0001', BoardBudget.CardNotesBytes)) && escaped.StorageErrorKey == "error.storageFileSize" && escaped.Find(escapedId)?.Notes == "" && File.ReadAllBytes(escaped.DocumentPath).SequenceEqual(escapedBefore) && new BoardStore(escaped.DirectoryPath).Snapshot.Cards.SequenceEqual(escaped.Snapshot.Cards), "Escaped serialized JSON budget prevents saving an irreopenable board");

    var changed = Fixture("external-change", CardsFixture(1)); var foreign = Encode(changed.Snapshot with { BoardTitle = "External legitimate state" }); File.WriteAllBytes(changed.DocumentPath, foreign);
    Check(changed.Update(changed.Snapshot.Cards[0].Id, title: "Unsaved local change") && changed.SaveErrorKey == "error.storageChanged" && !changed.Flush() && File.ReadAllBytes(changed.DocumentPath).SequenceEqual(foreign) && Directory.GetFiles(changed.DirectoryPath, "*.corrupt-*.json").Length == 0, "Externally changed valid board is neither overwritten nor quarantined");
    var removedPrimary = Fixture("external-removal", CardsFixture(1)); File.Delete(removedPrimary.DocumentPath);
    Check(!removedPrimary.Flush() && removedPrimary.SaveErrorKey == "error.storageChanged" && !File.Exists(removedPrimary.DocumentPath), "Externally removed known board is not recreated silently");
    var changedBackup = Fixture("external-backup-change", CardsFixture(1)); changedBackup.Create(); var foreignBackup = Encode(changedBackup.Snapshot with { BoardTitle = "External backup literal" }); File.WriteAllBytes(changedBackup.BackupPath, foreignBackup);
    Check(!changedBackup.Flush() && changedBackup.SaveErrorKey == "error.storageChanged" && File.ReadAllBytes(changedBackup.BackupPath).SequenceEqual(foreignBackup), "Externally changed valid backup is preserved without overwrite");
    var removedBackup = Fixture("external-backup-removal", CardsFixture(1)); removedBackup.Create(); File.Delete(removedBackup.BackupPath);
    Check(!removedBackup.Flush() && removedBackup.SaveErrorKey == "error.storageChanged" && !File.Exists(removedBackup.BackupPath), "Externally removed known backup is not recreated silently");
    var badBackup = Fixture("invalid-backup", CardsFixture(1)); var backupBadBytes = Encoding.UTF8.GetBytes("{\"unknown\":" + new string('[', 40) + "0" + new string(']', 40) + "}"); File.WriteAllBytes(badBackup.BackupPath, backupBadBytes); var backupOnly = new BoardStore(badBackup.DirectoryPath);
    Check(backupOnly.Snapshot.Cards.Count == 1 && backupOnly.RecoveryErrorKey == "error.storageStructure" && File.ReadAllBytes(Directory.GetFiles(badBackup.DirectoryPath, "*.corrupt-*.json").Single()).SequenceEqual(backupBadBytes), "Invalid backup is inspected and preserved even when primary is valid");

    var outside = Path.Combine(root, "outside-target.json"); var outsideBytes = Encode(new BoardSnapshot { BoardTitle = "Outside private fixture", Cards = [new Card()] }); File.WriteAllBytes(outside, outsideBytes);
    var symbolic = Folder("symbolic-alias"); File.CreateSymbolicLink(Path.Combine(symbolic, "board.json"), outside); var symbolicStore = new BoardStore(symbolic);
    Check(symbolicStore.Snapshot.Cards.Count == 0 && symbolicStore.RecoveryErrorKey == "error.storageFileType" && new FileInfo(Directory.GetFiles(symbolic, "*.corrupt-*.json").Single()).LinkTarget is not null && symbolicStore.Create() is not null && File.ReadAllBytes(outside).SequenceEqual(outsideBytes), "Symbolic alias is quarantined as an entry without reading or changing its target");
    var hard = Folder("hard-alias"); var hardPath = Path.Combine(hard, "board.json"); NativeTests.HardLink(hardPath, outside); var hardStore = new BoardStore(hard);
    Check(hardStore.Snapshot.Cards.Count == 0 && hardStore.RecoveryErrorKey == "error.storageFileType" && hardStore.Create() is not null && File.ReadAllBytes(outside).SequenceEqual(outsideBytes), "Hard-link alias is preserved without modifying the other user's bytes");
    var directoryAlias = Folder("nonregular-directory"); var reservedDirectory = Path.Combine(directoryAlias, "board.json"); Directory.CreateDirectory(reservedDirectory); var marker = Path.Combine(reservedDirectory, "preserve.txt"); File.WriteAllText(marker, "owned fixture"); var directoryStore = new BoardStore(directoryAlias);
    Check(directoryStore.Create() is not null && !directoryStore.Flush() && directoryStore.SaveErrorKey == "error.storageFileType" && File.ReadAllText(marker) == "owned fixture" && Directory.Exists(reservedDirectory), "Directory at reserved file path is neither read nor renamed or overwritten");
    var realRoot = Folder("root-link-target"); var linkedRoot = Path.Combine(root, "linked-data-root"); File.WriteAllBytes(Path.Combine(realRoot, "board.json"), outsideBytes); Directory.CreateSymbolicLink(linkedRoot, realRoot); var rootLinkStore = new BoardStore(linkedRoot);
    Check(rootLinkStore.Snapshot.Cards.Count == 0 && !rootLinkStore.Flush() && rootLinkStore.SaveErrorKey == "error.storageFileType" && File.ReadAllBytes(Path.Combine(realRoot, "board.json")).SequenceEqual(outsideBytes), "A symbolic data root cannot redirect reads, quarantine or writes");
    if (!OperatingSystem.IsWindows())
    {
        var fifoDirectory = Folder("nonregular-fifo"); var fifoPath = Path.Combine(fifoDirectory, "board.json"); NativeTests.Fifo(fifoPath); watch.Restart(); var fifoStore = new BoardStore(fifoDirectory);
        Check(watch.Elapsed < TimeSpan.FromSeconds(2) && !fifoStore.Flush() && fifoStore.SaveErrorKey == "error.storageFileType" && File.Exists(fifoPath), "FIFO is rejected without blocking or replacing the nonregular entry");
    }

    var prefsDirectory = Folder("preferences-budget"); var prefsPath = Path.Combine(prefsDirectory, "preferences.json"); using (var file = new FileStream(prefsPath, FileMode.CreateNew)) file.SetLength(128 * 1024);
    var oversizedPrefs = new PreferenceStore(prefsDirectory); oversizedPrefs.Load(); Check(oversizedPrefs.ErrorKey == "error.preferencesBudget" && Directory.GetFiles(prefsDirectory, "preferences.json.corrupt-*").Length == 1 && oversizedPrefs.Save(new Preferences()), "Preferences use a separate small byte budget and preserve rejected bytes");
    var originalPrefs = oversizedPrefs.Value;
    Check(!oversizedPrefs.Save(originalPrefs with { Query = new string('日', 1366) }) && oversizedPrefs.Value == originalPrefs && oversizedPrefs.ErrorKey == "error.preferencesBudget", "Oversized query does not mutate persistent preference state");
    var foreignPrefs = JsonSerializer.SerializeToUtf8Bytes(new Preferences { Language = "ja", Query = "External literal query" }); File.WriteAllBytes(prefsPath, foreignPrefs);
    Check(!oversizedPrefs.Save(new Preferences { Language = "fr" }) && oversizedPrefs.ErrorKey == "error.preferencesChanged" && File.ReadAllBytes(prefsPath).SequenceEqual(foreignPrefs), "Externally changed valid preferences are not overwritten");
    var prefsAliasDirectory = Folder("preferences-alias"); var prefsAlias = Path.Combine(prefsAliasDirectory, "preferences.json"); File.CreateSymbolicLink(prefsAlias, outside); var aliasPrefs = new PreferenceStore(prefsAliasDirectory); aliasPrefs.Load();
    Check(aliasPrefs.ErrorKey == "error.preferencesBudget" && aliasPrefs.Save(new Preferences()) && File.ReadAllBytes(outside).SequenceEqual(outsideBytes), "Preferences reject aliases without reading or changing targets");
    var deepPrefsDirectory = Folder("preferences-depth"); File.WriteAllText(Path.Combine(deepPrefsDirectory, "preferences.json"), "{\"Unknown\":" + new string('[', 12) + "0" + new string(']', 12) + "}"); var deepPrefs = new PreferenceStore(deepPrefsDirectory); deepPrefs.Load();
    Check(deepPrefs.ErrorKey == "error.preferencesBudget" && Directory.GetFiles(deepPrefsDirectory, "preferences.json.corrupt-*").Length == 1, "Preferences also bound unknown JSON structure work");
    var tokenPrefsDirectory = Folder("preferences-work"); File.WriteAllText(Path.Combine(tokenPrefsDirectory, "preferences.json"), "{\"Unknown\":[" + string.Join(',', Enumerable.Repeat("0", 600)) + "]}"); var tokenPrefs = new PreferenceStore(tokenPrefsDirectory); tokenPrefs.Load();
    Check(tokenPrefs.ErrorKey == "error.preferencesBudget" && Directory.GetFiles(tokenPrefsDirectory, "preferences.json.corrupt-*").Length == 1, "Preferences cap tokens even within a small file byte budget");
    var removedPrefsDirectory = Folder("preferences-removal"); var removedPrefs = new PreferenceStore(removedPrefsDirectory); Check(removedPrefs.Save(new Preferences()), "Valid preference fixture saves"); File.Delete(Path.Combine(removedPrefsDirectory, "preferences.json"));
    Check(!removedPrefs.Save(new Preferences { Language = "ja" }) && removedPrefs.ErrorKey == "error.preferencesChanged" && !File.Exists(Path.Combine(removedPrefsDirectory, "preferences.json")), "Known preferences removed externally are not silently recreated");

    var malformedDirectory = Folder("malformed-utf8"); var prefix = Encoding.UTF8.GetBytes("{\"cards\":[{\"column\":\""); var suffix = Encoding.UTF8.GetBytes("\"}]}"); File.WriteAllBytes(Path.Combine(malformedDirectory, "board.json"), prefix.Concat(new byte[] { 255 }).Concat(suffix).ToArray()); File.WriteAllBytes(Path.Combine(malformedDirectory, "board.backup.json"), Encode(new BoardSnapshot { BoardTitle = "UTF8 backup" })); var malformed = new BoardStore(malformedDirectory);
    Check(malformed.Snapshot.BoardTitle == "UTF8 backup" && malformed.RecoveryKey == "recovery.backup" && Directory.GetFiles(malformedDirectory, "*.corrupt-*.json").Length == 1, "Invalid encoded JSON strings cannot crash board startup");
    var bothDirectory = Folder("both-rejected"); var primaryRejected = Encode(CardsFixture(BoardBudget.CardCount + 1)); var backupRejected = Encode(new BoardSnapshot { BoardTitle = new string('x', BoardBudget.BoardTitleBytes + 1) }); File.WriteAllBytes(Path.Combine(bothDirectory, "board.json"), primaryRejected); File.WriteAllBytes(Path.Combine(bothDirectory, "board.backup.json"), backupRejected); var both = new BoardStore(bothDirectory); var bothPreserved = Directory.GetFiles(bothDirectory, "*.corrupt-*.json"); var bothAgain = new BoardStore(bothDirectory);
    Check(both.RecoveryKey == "recovery.both" && bothPreserved.Length == 2 && bothPreserved.Any(path => File.ReadAllBytes(path).SequenceEqual(primaryRejected)) && bothPreserved.Any(path => File.ReadAllBytes(path).SequenceEqual(backupRejected)) && bothAgain.Create() is not null && Directory.GetFiles(bothDirectory, "*.corrupt-*.json").Length == 2, "Rejected primary and backup remain preserved across repeated startup and new autosave");
    var growingDirectory = Folder("growing-source"); var growingPath = Path.Combine(growingDirectory, "board.json"); File.WriteAllText(growingPath, "{\"unknown\":\"" + new string('x', 15 * 1024 * 1024) + "\"}"); using var writing = new ManualResetEventSlim();
    var writer = Task.Run(() =>
    {
        using var stream = new FileStream(growingPath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
        var chunk = new byte[256 * 1024]; Array.Fill(chunk, (byte)'x');
        for (var index = 0; index < 32; index++) { stream.Write(chunk); stream.Flush(); if (index == 0) writing.Set(); Thread.Sleep(1); }
    });
    writing.Wait(); watch.Restart(); var growing = new BoardStore(growingDirectory); writer.GetAwaiter().GetResult();
    Check(watch.Elapsed < TimeSpan.FromSeconds(10) && growing.RecoveryKey is not null && growing.Snapshot.Cards.Count == 0 && (File.Exists(growingPath) || Directory.GetFiles(growingDirectory, "*.corrupt-*.json").Length == 1), "Concurrent growth is refused with bounded reading and recoverable source preservation");
    var boardRoot = Path.Combine(root, "replaced-board-root"); var rootOwnedBoard = new BoardStore(boardRoot); rootOwnedBoard.Create(); var retainedBoardRoot = boardRoot + "-retained"; Directory.Move(boardRoot, retainedBoardRoot); Directory.CreateDirectory(boardRoot);
    var foreignInvalid = Encoding.UTF8.GetBytes("{external-invalid-json"); File.WriteAllBytes(Path.Combine(boardRoot, "board.json"), foreignInvalid);
    var boardRootSafe = !rootOwnedBoard.Flush() && rootOwnedBoard.SaveErrorKey == "error.storageChanged" && File.ReadAllBytes(Path.Combine(boardRoot, "board.json")).SequenceEqual(foreignInvalid) && Directory.GetFiles(boardRoot, "*.corrupt-*").Length == 0 && File.Exists(Path.Combine(retainedBoardRoot, "board.json"));
    var prefsRoot = Folder("replaced-preferences-root"); var rootOwnedPreferences = new PreferenceStore(prefsRoot); rootOwnedPreferences.Load(); rootOwnedPreferences.Save(new Preferences { Query = "Original session literal" }); Directory.Move(prefsRoot, prefsRoot + "-retained"); Directory.CreateDirectory(prefsRoot); File.WriteAllBytes(Path.Combine(prefsRoot, "preferences.json"), foreignInvalid);
    Check(boardRootSafe && !rootOwnedPreferences.Save(new Preferences { Language = "ja" }) && rootOwnedPreferences.ErrorKey == "error.preferencesChanged" && File.ReadAllBytes(Path.Combine(prefsRoot, "preferences.json")).SequenceEqual(foreignInvalid) && Directory.GetFiles(prefsRoot, "*.corrupt-*").Length == 0 && File.Exists(Path.Combine(prefsRoot + "-retained", "preferences.json")), "Replacing the real data directory cannot quarantine or overwrite another directory's board or preferences");
    Console.WriteLine($"PASS: {passed} checks; isolated temporary data only.");
}
finally { Directory.Delete(root, true); }

static class NativeTests
{
    public static void HardLink(string path, string target)
    {
        if (OperatingSystem.IsWindows() ? !CreateHardLink(path, target, IntPtr.Zero) : Link(target, path) != 0) throw new IOException("Unable to create isolated hard-link fixture.");
    }
    public static void Fifo(string path) { if (MkFifo(path, 0x180) != 0) throw new IOException("Unable to create isolated FIFO fixture."); }
    [DllImport("kernel32.dll", EntryPoint = "CreateHardLinkW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] static extern bool CreateHardLink(string path, string target, IntPtr security);
    [DllImport("libc", EntryPoint = "link", SetLastError = true)] static extern int Link(string target, string path);
    [DllImport("libc", EntryPoint = "mkfifo", SetLastError = true)] static extern int MkFifo(string path, uint mode);
}
