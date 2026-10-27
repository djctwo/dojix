# Dojix (open-source edition)

Native macOS trade journal for forex traders. Swift 6 + SwiftUI, GRDB (SQLite),
XcodeGen (`project.yml`). GPL-3.0 (copyright holder in NOTICE). This file is public.

## Hard rules
- **No secrets in the repo.** No API keys, tokens, certificates or key material, in any
  form (plain, base64, XOR-masked byte arrays). Online features use a key the *user*
  enters, stored in the Keychain, off by default; no request may bill the maintainer.
- **No billing or licensing code.** No paywalls, tiers, trials, license keys, feature
  gates or "upgrade" text. Every feature is available to everyone.
- **No auto-updater pointing at a private server.** Releases go through GitHub.
  Pushing a tag `v<MARKETING_VERSION>` runs the `release` job in `.github/workflows/macos.yml`,
  which builds the unsigned Release app and attaches `Dojix-macOS-unsigned.zip` (+ `.sha256`)
  to a GitHub Release (notes: `docs/release-notes/<tag>.md` if present).
- **No real data.** Demo and test data must be clearly fictional (sample trades carry the
  comment "Sample (fictional)"). Never commit real trades, account numbers, broker
  statements, personal paths or names.
- **No code from outside contributors** (single copyright holder; see CONTRIBUTING.md).
- **AI privacy:** only aggregated statistics go to the AI provider, only with the user's
  own key, only after they click Run Analysis, and the UI must say so.

## Never touch a real install while developing
Data, preferences and Keychain items are keyed as follows:
- Database + screenshots: `Configuration.dataDirectory` =
  `$DOJIX_DATA_DIR` if set (Debug builds only), else `~/Library/Application Support/Dojix`
  for the official bundle ID `com.dojix.app`, else
  `~/Library/Application Support/Dojix-<bundle id>`.
- Keychain service: the bundle ID (`$DOJIX_KEYCHAIN_SERVICE` overrides it for
  non-official Debug builds only).
- MT5 folders: `$DOJIX_MT5_DIR` overrides the watched folder (Debug builds only).
- Release builds ignore all three overrides and carry no `get-task-allow`.

Debug builds default to `com.dojix.app.dev`. For any local run of tests, UI tests or the
app, use a throwaway bundle ID and scratch folders, e.g.
`DOJIX_BUNDLE_ID=com.dojix.app.test` plus `TEST_RUNNER_DOJIX_DATA_DIR=/tmp/x`
`TEST_RUNNER_DOJIX_MT5_DIR=/tmp/y`. Never build or run with `com.dojix.app` on a
machine where Dojix is really used.

## Run / test
```bash
brew install xcodegen
xcodegen generate
S=$(mktemp -d)
TEST_RUNNER_DOJIX_DATA_DIR=$S/data TEST_RUNNER_DOJIX_MT5_DIR=$S/mt5 \
  xcodebuild test -project Dojix.xcodeproj -scheme Dojix -only-testing:DojixTests \
  -derivedDataPath build/dd DOJIX_BUNDLE_ID=com.dojix.app.test
```
UI tests (`DojixUITests`) and any app launch / screenshots run on GitHub's macOS runner
(`ui-tests` job in `.github/workflows/macos.yml`), not on a Mac where Dojix is really
used. They keep app data under `DOJIX_UITEST_ROOT` (never `NSTemporaryDirectory()` of the
sandboxed test runner: pointing the app into another app's container makes macOS show
"wants to access data from other apps"). Ad-hoc signed rebuilds can trigger Keychain
prompts; pass a fresh `TEST_RUNNER_DOJIX_KEYCHAIN_SERVICE=com.dojix.app.test.<n>` per
build and delete those items afterwards (`security delete-generic-password -s <service>`).

## Architecture
- MVVM with a services layer: Views -> ViewModels (`@Observable`) -> Services -> GRDB.
- `AppState.shared` is the one app-wide state object (one database per process).
- Every imported trade passes through `Trade.sanitizedForStorage()` in `TradeRepository`.
- Ticketless imports get a stable content-derived ticket (`GenericCSVParser.contentTicket`)
  so re-importing never duplicates.
- The journal lives in memory only (`DatabaseManager`, a GRDB `DatabaseQueue` loaded with
  `sqlite3_deserialize`). After every commit it is serialized, AES-256-GCM sealed and
  atomically written to `Dojix.sqlite` (0600, `OwnerOnlyFile`: random temp name,
  O_EXCL|O_NOFOLLOW, F_FULLFSYNC, rename, folder sync, so a save is on disk before its
  generation is recorded); no plaintext database, WAL or copy is ever written.
  `replaceContents` (restore) saves before notifying observers and puts the previous
  contents back in memory if the swap or the save fails.
  Nothing is read until `load(key:)`. A save that fails while opening (full disk) is not
  fatal; `AppState.openJournal` sets a file aside only when it doesn't decrypt or isn't a
  database (`isDamagedJournal`), never on a read/I-O error. `rekey`, `replaceContents`
  and `unload` each check "loaded" inside one turn of the database queue, and `saveNow`
  throws when the journal is closed, so nothing reports a save that didn't happen.
- One running copy per data folder: `InstanceLock` (`flock` on `Dojix.lock`); a second
  copy shows "Dojix is already open" and opens nothing. Only on one Mac and where the
  folder supports `flock`: if the lock can't be opened/taken (`.unavailable`) Dojix opens
  anyway. "Quit & Relaunch" (`DatabaseFailedView`) releases the lock first
  (`releaseDataFolderForRelaunch`, only while the journal is closed).
- Rollback protection: the sealed journal has an authenticated header ("DJXJ", epoch =
  random ID of the line of saves, generation, save time). `SaveGenerationStore` keeps the
  last save's stamp + SHA-256 of the file in the Keychain (account
  `journal_save_generation`). `load` throws `OlderJournalError` for any other file (older,
  other epoch, same generation but different bytes); `AppState.olderJournal` then shows
  `OlderJournalView`, which opens it only with the App Lock password (or a confirmation
  with App Lock off) and starts a new epoch; the count never goes down. Journals sealed
  before this (bare AES-GCM box) and plaintext ones count as generation 0. A failed
  Keychain write is logged, never fatal (the record then lags, and a file newer than it
  in the same epoch is accepted; an unreadable record accepts any file). The record is
  written without allowing a dialog (`KeychainSecretStore(allowsUserInteraction: false)`:
  an `LAContext` with `interactionNotAllowed`); a write the Keychain refuses is skipped.
  Tested: the flag is set and add/update work on an unlocked keychain
  (`RereviewFixTests`); not verified against a locked file-based keychain.
- The key (`DatabaseKeyVault`) is a bare Keychain item with App Lock off; with App Lock on
  it is stored only wrapped with a PBKDF2-SHA256 (600,000 iterations) key from the lock
  password, so the lock protects the data. A key is never regenerated over an
  unreadable one. Key rotation (`KeyRotation`): once `beginRotation` stored [new, old],
  the change counts as made (`Outcome.finishesOnNextUnlock` when files still need the old
  key); `finishRotation` runs only when every stray copy/screenshot was re-sealed and
  `Dojix.sqlite` opens with the new key; a folder that can't be listed counts as pending.
  If the Keychain accepts [new, old] but can't read it back (`unconfirmed`), nothing else
  is done and the outcome is `finishesOnNextUnlock`. A pending rotation is finished before
  the key changes again (`beginRotation`/`storePlain` refuse with `rotationPending`).
  Screenshot writes take the key of the moment under `ScreenshotManager`'s file lock, and
  the re-seal takes its file list under that lock. The legacy App Lock hash
  (`app_lock_hash`) is read through the vault like the key: only errSecItemNotFound means
  "none", any other error fails closed.
  `AppState.isAppLockOn` is kept in memory (never a Keychain read when locking); a lock
  requested while App Lock is being enabled or an unlock is running happens when it ends
  (`AppState+KeyOperations`: `beginDeferringLocks`); Disable changes the Keychain only if
  no lock happened during its password check. Unlock, Enable, Change Password and Disable
  count as key operations; "Erase Everything" waits for them (`waitForKeyOperations`) and
  the lock screen disables "Forgot Password?" while unlocking. One at a time: Enable,
  Change Password and Disable refuse (`AppLockChangeError.busy`) while any key operation
  runs, and a second unlock is refused (`isUnlocking`) while one runs (from another
  window). An unlock that finds no wrapped key and no legacy hash opens as a launch with
  App Lock off would (`isAppLockOn = false`), so a failed Enable never leaves a lock
  screen that rejects every password. `UnlockThrottle` (shared
  by the lock screen, older-journal screen and Settings) backs off wrong passwords and
  fails closed: a read error on its count or wait (anything but errSecItemNotFound) =
  locked out (`unreadableMessage`), and `recordFailure` then writes nothing.
  Locking (`AppState.lock()`) saves, wipes the in-memory copy and key, and closes
  sheets and modal panels (`LockCover`). `AutoLockMonitor` locks on sleep,
  screen lock, user switch, hide, minimize and, via `IdleLockTimer` (injected clock,
  common run-loop modes), after the "Lock when idle" time (`IdleLockSetting`, default 15).
- Plaintext left by older builds (`Dojix.sqlite` + `-wal`, `.pre-restore-backup`,
  `.unreadable-*`, plain screenshot JPEGs) is encrypted at the first launch/unlock;
  "Erase all local data" deletes every one of them.
- Backups (`BackupService.writeBackup`) are plain SQLite or, with a password,
  `BackupEncryption` ("DJXB" | version | PBKDF2 iterations | salt, header bound as AES-GCM
  AAD; 600,000 iterations; 1,000...10,000,000 accepted when reading). Dojix 1.x "DOJX"
  backups (`ExportEncryption`, 100,000 iterations) are read only; the app has no writer
  for them. Password rule for App Lock and backups: `PasswordRules`.
- Restores never copy the backup file over the journal: `BackupService.validatedContents`
  decrypts it if needed, opens it in memory, checks schema/migrations/every row
  (`Trade.storageViolations`), and replaces the rows in one transaction.
- Network calls go through `SecureSession.make()` (HTTPS, system trust, no caching).

## Conventions
- Swift 6 strict concurrency; async/await; no force unwraps without a proving comment.
- `Logger` (os.log), never `print`, never log keys or trade data.
- All SQL through repositories with bound arguments.
- New fixes come with a test that fails without the fix.
