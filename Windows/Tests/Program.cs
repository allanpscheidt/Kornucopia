using System.Text.Json;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Text;
using System.Security.AccessControl;
using System.Security.Principal;
using Kornucopia.Core;
using Kornucopia.Windows;

var root = Path.Combine(Path.GetTempPath(), "kornucopia-core-test-" + Guid.NewGuid().ToString("N"));
PrivateFolder(root);
void PrivateFolder(string path)
{
    Directory.CreateDirectory(path);
    if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    else
    {
        using var token = WindowsIdentity.GetCurrent(); var user = token.User!;
        var security = new DirectorySecurity(); security.SetOwner(user); security.SetAccessRuleProtection(true, false);
        foreach (var sid in new[] { user, new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null) })
            security.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        new DirectoryInfo(path).SetAccessControl(security);
    }
}
int passed = 0;
void Check(bool value, string name) { if (!value) throw new InvalidOperationException(name); passed++; Console.WriteLine("PASS " + name); }
try
{
    var nestedRoot = Path.Combine(root, "missing-parent", "missing-root");
    var nestedStore = new BoardStore(nestedRoot); var nestedCard = nestedStore.Create();
    var nestedPreferences = new PreferenceStore(Path.Combine(root, "missing-preferences-parent", "missing-preferences-root")); nestedPreferences.Load();
    Check(nestedStore.RecoveryKey is null && nestedStore.SaveError is null && nestedCard is Guid && nestedStore.Flush() && new BoardStore(nestedRoot).Find(nestedCard.Value) is not null && nestedPreferences.Error is null && nestedPreferences.Save(new Preferences { Language = "ja", Query = "Nested private fixture" }), "Two missing private path components are created, loaded and persisted for board and preferences");
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
    string Folder(string name) { var path = Path.Combine(root, name); PrivateFolder(path); return path; }
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
    var realRoot = Folder("root-link-target"); var linkedRoot = Path.Combine(root, "linked-data-root"); File.WriteAllBytes(Path.Combine(realRoot, "board.json"), outsideBytes); NativeTests.DirectorySymbolicLink(linkedRoot, realRoot); var rootLinkStore = new BoardStore(linkedRoot);
    Check(rootLinkStore.Snapshot.Cards.Count == 0 && !rootLinkStore.Flush() && rootLinkStore.SaveErrorKey == "error.storageUnsafeRoot" && File.ReadAllBytes(Path.Combine(realRoot, "board.json")).SequenceEqual(outsideBytes), "A symbolic data root cannot redirect reads, quarantine or writes");
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
    var boardRoot = Path.Combine(root, "replaced-board-root"); var rootOwnedBoard = new BoardStore(boardRoot); rootOwnedBoard.Create(); var retainedBoardRoot = boardRoot + "-retained"; Directory.Move(boardRoot, retainedBoardRoot); PrivateFolder(boardRoot);
    var foreignInvalid = Encoding.UTF8.GetBytes("{external-invalid-json"); File.WriteAllBytes(Path.Combine(boardRoot, "board.json"), foreignInvalid);
    var boardRootSafe = !rootOwnedBoard.Flush() && rootOwnedBoard.SaveErrorKey == "error.storageChanged" && File.ReadAllBytes(Path.Combine(boardRoot, "board.json")).SequenceEqual(foreignInvalid) && Directory.GetFiles(boardRoot, "*.corrupt-*").Length == 0 && File.Exists(Path.Combine(retainedBoardRoot, "board.json"));
    var prefsRoot = Folder("replaced-preferences-root"); var rootOwnedPreferences = new PreferenceStore(prefsRoot); rootOwnedPreferences.Load(); rootOwnedPreferences.Save(new Preferences { Query = "Original session literal" }); Directory.Move(prefsRoot, prefsRoot + "-retained"); PrivateFolder(prefsRoot); File.WriteAllBytes(Path.Combine(prefsRoot, "preferences.json"), foreignInvalid);
    Check(boardRootSafe && !rootOwnedPreferences.Save(new Preferences { Language = "ja" }) && rootOwnedPreferences.ErrorKey == "error.preferencesChanged" && File.ReadAllBytes(Path.Combine(prefsRoot, "preferences.json")).SequenceEqual(foreignInvalid) && Directory.GetFiles(prefsRoot, "*.corrupt-*").Length == 0 && File.Exists(Path.Combine(prefsRoot + "-retained", "preferences.json")), "Replacing the real data directory cannot quarantine or overwrite another directory's board or preferences");
    var parentTarget = Folder("private-parent-target"); var parentChild = Path.Combine(parentTarget, "data"); PrivateFolder(parentChild);
    File.WriteAllBytes(Path.Combine(parentChild, "board.json"), outsideBytes); File.WriteAllBytes(Path.Combine(parentChild, "preferences.json"), foreignPrefs);
    var parentLink = Path.Combine(root, "parent-link"); NativeTests.DirectoryLink(parentLink, parentTarget);
    var redirected = new BoardStore(Path.Combine(parentLink, "data")); var redirectedPreferences = new PreferenceStore(Path.Combine(parentLink, "data")); redirectedPreferences.Load();
    Check(redirected.RecoveryKey == "recovery.unsafeRoot" && redirected.Snapshot.Cards.Count == 0 && redirected.SaveErrorKey == "error.storageUnsafeRoot" && !redirected.Flush() && redirectedPreferences.Value.Query == "" && redirectedPreferences.ErrorKey == "error.storageUnsafeRoot" && !redirectedPreferences.Save(new Preferences()) && Directory.GetFiles(parentChild).Length == 2 && File.ReadAllBytes(Path.Combine(parentChild, "board.json")).SequenceEqual(outsideBytes), "Linked or junction ancestor is refused before board/preferences reads, backup, temp or quarantine");
    var writableAncestor = Folder("untrusted-ancestor"); var privateChild = Path.Combine(writableAncestor, "data"); PrivateFolder(privateChild); File.WriteAllBytes(Path.Combine(privateChild, "board.json"), outsideBytes);
    if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(writableAncestor, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute | UnixFileMode.GroupWrite | UnixFileMode.OtherWrite);
    else
    {
        var info = new DirectoryInfo(writableAncestor); var security = info.GetAccessControl(); security.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.WorldSid, null), FileSystemRights.DeleteSubdirectoriesAndFiles, AccessControlType.Allow)); info.SetAccessControl(security);
    }
    var ancestralAccess = new BoardStore(privateChild);
    Check(ancestralAccess.RecoveryKey == "recovery.unsafeRoot" && ancestralAccess.Snapshot.Cards.Count == 0 && !ancestralAccess.Flush() && Directory.GetFiles(privateChild).Length == 1 && File.ReadAllBytes(Path.Combine(privateChild, "board.json")).SequenceEqual(outsideBytes), "An ancestor that permits foreign replacement is refused before opening private child data");
    var publicRoot = Folder("untrusted-access-root"); File.WriteAllBytes(Path.Combine(publicRoot, "board.json"), outsideBytes); File.WriteAllBytes(Path.Combine(publicRoot, "preferences.json"), foreignPrefs);
    if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(publicRoot, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute | UnixFileMode.GroupRead | UnixFileMode.OtherRead | UnixFileMode.OtherWrite);
    else
    {
        var info = new DirectoryInfo(publicRoot); var security = info.GetAccessControl();
        security.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.WorldSid, null), FileSystemRights.ReadAndExecute | FileSystemRights.Write, InheritanceFlags.None, PropagationFlags.None, AccessControlType.Allow)); info.SetAccessControl(security);
    }
    var publicBoard = new BoardStore(publicRoot); var publicPreferences = new PreferenceStore(publicRoot); publicPreferences.Load();
    Check(publicBoard.RecoveryKey == "recovery.unsafeRoot" && publicBoard.Snapshot.Cards.Count == 0 && !publicBoard.Flush() && publicPreferences.ErrorKey == "error.storageUnsafeRoot" && !publicPreferences.Save(new Preferences()) && Directory.GetFiles(publicRoot).Length == 2 && File.ReadAllBytes(Path.Combine(publicRoot, "board.json")).SequenceEqual(outsideBytes), "Storage accessible to an untrusted principal is refused without reading, changing permissions or preserving data elsewhere");
    if (OperatingSystem.IsWindows())
    {
        var unsafeLeafRoot = Folder("unsafe-leaf-acl"); var unsafeLeaf = Path.Combine(unsafeLeafRoot, "board.json"); File.WriteAllBytes(unsafeLeaf, outsideBytes);
        var info = new FileInfo(unsafeLeaf); var security = info.GetAccessControl(); security.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.WorldSid, null), FileSystemRights.Read, AccessControlType.Allow)); info.SetAccessControl(security);
        var unsafeLeafStore = new BoardStore(unsafeLeafRoot);
        Check(unsafeLeafStore.RecoveryKey == "recovery.unsafeRoot" && unsafeLeafStore.Snapshot.Cards.Count == 0 && !unsafeLeafStore.Flush() && Directory.GetFiles(unsafeLeafRoot).Length == 1 && File.ReadAllBytes(unsafeLeaf).SequenceEqual(outsideBytes), "Existing Windows leaf with a public DACL is refused by handle before reading and is not quarantined");
        var publicPreference = Path.Combine(unsafeLeafRoot, "preferences.json"); File.WriteAllBytes(publicPreference, foreignPrefs); var preferenceInfo = new FileInfo(publicPreference); var preferenceSecurity = preferenceInfo.GetAccessControl(); preferenceSecurity.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.WorldSid, null), FileSystemRights.Read, AccessControlType.Allow)); preferenceInfo.SetAccessControl(preferenceSecurity);
        var unsafeLeafPreferences = new PreferenceStore(unsafeLeafRoot); unsafeLeafPreferences.Load();
        Check(unsafeLeafPreferences.ErrorKey == "error.storageUnsafeRoot" && unsafeLeafPreferences.Value.Query == "" && !unsafeLeafPreferences.Save(new Preferences()) && Directory.GetFiles(unsafeLeafRoot).Length == 2 && File.ReadAllBytes(publicPreference).SequenceEqual(foreignPrefs), "Public Windows preference leaf is refused before reading and retained without chmod or quarantine");
    }
    else
    {
        var normalImport = Folder("private-root-import"); var importPath = Path.Combine(normalImport, "board.json"); File.WriteAllBytes(importPath, outsideBytes); File.SetUnixFileMode(importPath, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.GroupRead | UnixFileMode.OtherRead);
        var imported = new BoardStore(normalImport); var importedCard = imported.Snapshot.Cards[0].Id;
        Check(imported.Snapshot.BoardTitle == "Outside private fixture" && imported.Update(importedCard, title: "Accepted private import") && imported.SaveError is null && new BoardStore(normalImport).Find(importedCard)?.Title == "Accepted private import" && File.GetUnixFileMode(imported.DocumentPath) == (UnixFileMode.UserRead | UnixFileMode.UserWrite), "Regular imported leaf under a private root loads, backs up and becomes a private atomic replacement");
    }
    void ExposeLeaf(string path)
    {
        if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.OtherWrite);
        else { var info = new FileInfo(path); var security = info.GetAccessControl(); security.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.WorldSid, null), FileSystemRights.Read, AccessControlType.Allow)); info.SetAccessControl(security); }
    }
    var deniedPrimaryRoot = Folder("unsafe-primary-invalid-backup"); var deniedPrimaryPath = Path.Combine(deniedPrimaryRoot, "board.json"); File.WriteAllBytes(deniedPrimaryPath, outsideBytes); ExposeLeaf(deniedPrimaryPath);
    var deniedBackupPath = Path.Combine(deniedPrimaryRoot, "board.backup.json"); var deniedBackupBytes = Encoding.UTF8.GetBytes("{invalid-backup"); File.WriteAllBytes(deniedBackupPath, deniedBackupBytes);
    var deniedPrimary = new BoardStore(deniedPrimaryRoot);
    Check(deniedPrimary.RecoveryKey == "recovery.unsafeRoot" && deniedPrimary.RecoveryErrorKey == "error.storageUnsafeRoot" && deniedPrimary.Snapshot.Cards.Count == 0 && Directory.GetFiles(deniedPrimaryRoot).Length == 2 && File.ReadAllBytes(deniedBackupPath).SequenceEqual(deniedBackupBytes), "Unsafe primary stops startup before an invalid backup is inspected or quarantined");
    var partialRoot = Folder("unsafe-backup-partial-load"); var partialPrimaryPath = Path.Combine(partialRoot, "board.json"); var partialPrimary = Encode(new BoardSnapshot { BoardTitle = "Legitimate primary retained", Cards = [new Card()] }); File.WriteAllBytes(partialPrimaryPath, partialPrimary);
    var partialBackupPath = Path.Combine(partialRoot, "board.backup.json"); File.WriteAllBytes(partialBackupPath, outsideBytes); ExposeLeaf(partialBackupPath); var partial = new BoardStore(partialRoot);
    File.Delete(partialBackupPath); File.WriteAllBytes(partialBackupPath, outsideBytes);
    partial.Create();
    Check(partial.RecoveryKey == "recovery.unsafeRoot" && !partial.Flush() && partial.SaveErrorKey == "error.storageUnsafeRoot" && File.ReadAllBytes(partialPrimaryPath).SequenceEqual(partialPrimary) && Directory.GetFiles(partialRoot, "*.corrupt-*").Length == 0 && new BoardStore(partialRoot).Snapshot.BoardTitle == "Legitimate primary retained", "Fixing an unsafe backup does not let the refused instance overwrite a primary it never displayed");
    PrivateFolder(publicRoot);
    Check(!publicBoard.Flush() && !publicPreferences.Save(new Preferences { Query = "Unloaded session" }) && publicBoard.SaveErrorKey == "error.storageUnsafeRoot" && publicPreferences.ErrorKey == "error.storageUnsafeRoot" && File.ReadAllBytes(Path.Combine(publicRoot, "board.json")).SequenceEqual(outsideBytes) && File.ReadAllBytes(Path.Combine(publicRoot, "preferences.json")).SequenceEqual(foreignPrefs) && new BoardStore(publicRoot).Snapshot.BoardTitle == "Outside private fixture", "Refused startup remains write-blocked after permissions are corrected until a new load");
    if (OperatingSystem.IsWindows())
    {
        var pinnedAliasRoot = Folder("pin-preservation-entry"); var pinnedAliasPath = Path.Combine(pinnedAliasRoot, "board.json"); NativeTests.HardLink(pinnedAliasPath, outside);
        bool entryPinned;
        using (var deleteHandle = NativeTests.HoldDeleteHandle(pinnedAliasPath))
        {
            var pinnedAlias = new BoardStore(pinnedAliasRoot);
            entryPinned = pinnedAlias.Snapshot.Cards.Count == 0 && pinnedAlias.SaveError is not null && !pinnedAlias.Flush() && File.Exists(pinnedAliasPath) && Directory.GetFiles(pinnedAliasRoot).Length == 1;
        }
        Check(entryPinned && File.ReadAllBytes(outside).SequenceEqual(outsideBytes), "A preexisting DELETE handle prevents preservation from opening and renaming an aliased entry");
    }
    var swappingRoot = Folder("leaf-swap"); var swappingPath = Path.Combine(swappingRoot, "board.json"); var benignBytes = Encode(new BoardSnapshot { BoardTitle = "Benign race fixture", Cards = [new Card()] });
    using var swappingStop = new CancellationTokenSource();
    var swapping = Task.Run(() =>
    {
        var ownTemp = Path.Combine(swappingRoot, "attack-fixture.tmp");
        while (!swappingStop.IsCancellationRequested)
        {
            try { File.WriteAllBytes(ownTemp, benignBytes); File.Move(ownTemp, swappingPath, true); File.Delete(swappingPath); File.CreateSymbolicLink(swappingPath, outside); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    });
    var disclosed = false;
    try
    {
        for (var i = 0; i < 48; i++)
        {
            var concurrent = new BoardStore(swappingRoot); disclosed |= concurrent.Snapshot.BoardTitle == "Outside private fixture"; concurrent.Create();
            var concurrentBackup = Path.Combine(swappingRoot, "board.backup.json");
            try { if (File.Exists(concurrentBackup)) disclosed |= File.ReadAllBytes(concurrentBackup).SequenceEqual(outsideBytes); }
            catch (IOException) { }
        }
    }
    finally { swappingStop.Cancel(); swapping.GetAwaiter().GetResult(); }
    Check(!disclosed && File.ReadAllBytes(outside).SequenceEqual(outsideBytes), "Concurrent leaf swaps never decode a linked private board or copy its bytes into a backup");
    var switchedRoot = Folder("root-switch-link"); var switchedStore = new BoardStore(switchedRoot); switchedStore.Create(); Directory.Move(switchedRoot, switchedRoot + "-retained"); NativeTests.DirectoryLink(switchedRoot, parentChild);
    Check(!switchedStore.Flush() && switchedStore.SaveErrorKey == "error.storageUnsafeRoot" && File.ReadAllBytes(Path.Combine(parentChild, "board.json")).SequenceEqual(outsideBytes) && Directory.GetFiles(parentChild).Length == 2, "Replacing a loaded root with a link or junction cannot access or mutate the target");
    NativeTests.RemoveDirectoryLinks(root);
    Check(File.ReadAllBytes(Path.Combine(parentChild, "board.json")).SequenceEqual(outsideBytes) && File.ReadAllBytes(Path.Combine(realRoot, "board.json")).SequenceEqual(outsideBytes) && Directory.GetFiles(parentChild).Length == 2, "Removing fixture links deletes only their entries and preserves every target");
    Console.WriteLine($"PASS: {passed} checks; isolated temporary data only.");
}
finally { NativeTests.RemoveDirectoryLinks(root); Directory.Delete(root, true); }

static class NativeTests
{
    static readonly List<string> directoryLinks = [];
    public static void DirectorySymbolicLink(string path, string target)
    {
        Directory.CreateSymbolicLink(path, target); directoryLinks.Add(Path.GetFullPath(path)); ValidateDirectoryLink(path, target);
    }
    static void ValidateDirectoryLink(string path, string target)
    {
        // LinkTarget reads the reparse payload itself, without resolving the target.
        var link = new DirectoryInfo(path); var immediateTarget = link.LinkTarget;
        var resolvedTarget = link.ResolveLinkTarget(false)?.FullName;
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0 || immediateTarget is null || !Path.GetFullPath(immediateTarget).Equals(Path.GetFullPath(target), comparison) || resolvedTarget is null || !resolvedTarget.Equals(Path.GetFullPath(target), comparison) || !Directory.Exists(path))
            throw new IOException("The isolated directory link does not point to its intended fixture.");
    }
    public static void RemoveDirectoryLinks(string root)
    {
        var prefix = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)) + Path.DirectorySeparatorChar;
        for (var index = directoryLinks.Count - 1; index >= 0; index--)
        {
            var path = directoryLinks[index];
            if (!path.StartsWith(prefix, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0)
                throw new IOException("The isolated fixture link changed before cleanup.");
            // Recursive Directory.Delete treats junctions as volume mount points.
            // Delete the link entry directly, before walking any real fixture data.
            if (OperatingSystem.IsWindows()) Directory.Delete(path, false);
            else File.Delete(path);
            directoryLinks.RemoveAt(index);
        }
    }
    public static void HardLink(string path, string target)
    {
        if (OperatingSystem.IsWindows() ? !CreateHardLink(path, target, IntPtr.Zero) : Link(target, path) != 0) throw new IOException("Unable to create isolated hard-link fixture.");
    }
    public static Microsoft.Win32.SafeHandles.SafeFileHandle HoldDeleteHandle(string path)
    {
        var handle = CreateFile(path, 0x10080, 7, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero);
        if (handle.IsInvalid) { handle.Dispose(); throw new IOException("Unable to pin isolated preservation fixture."); }
        return handle;
    }
    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)] static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    public static void DirectoryLink(string path, string target)
    {
        if (!OperatingSystem.IsWindows()) { DirectorySymbolicLink(path, target); return; }
        var start = new ProcessStartInfo("cmd.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "/d", "/c", "mklink", "/J", path, target }) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new IOException("Unable to create isolated junction fixture.");
        process.WaitForExit(); if (process.ExitCode != 0) throw new IOException("Unable to create isolated junction fixture.");
        directoryLinks.Add(Path.GetFullPath(path)); ValidateDirectoryLink(path, target);
    }
    public static void Fifo(string path) { if (MkFifo(path, 0x180) != 0) throw new IOException("Unable to create isolated FIFO fixture."); }
    [DllImport("kernel32.dll", EntryPoint = "CreateHardLinkW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] static extern bool CreateHardLink(string path, string target, IntPtr security);
    [DllImport("libc", EntryPoint = "link", SetLastError = true)] static extern int Link(string target, string path);
    [DllImport("libc", EntryPoint = "mkfifo", SetLastError = true)] static extern int MkFifo(string path, uint mode);
}
