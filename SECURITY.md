# Security Policy

## Reporting a vulnerability

Please report security problems privately through GitHub's private vulnerability
reporting: open the repository's **Security** tab and click **Report a vulnerability**
([direct link](https://github.com/djctwo/dojix/security/advisories/new)). Do not open a
public issue for a security problem.

Include what you found, the steps or a small file that reproduces it, and the Dojix
version (*Dojix > About Dojix*). Never include real trades, account numbers, broker
statements or API keys; a made-up example is enough. You will get an answer in the
advisory, and a fix is published as a new release.

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | Yes |
| Older | No |

## Security model

What Dojix protects:

- **The journal on disk.** The database is always encrypted (AES-256-GCM), and so are
  trade screenshots. The decrypted journal exists only in memory; no plaintext copy or
  write-ahead log is ever written. Files are created readable by your user
  account only, and each save is flushed to the disk (`F_FULLFSYNC`, then the folder)
  before it counts as done. On one Mac, only one running copy of Dojix uses the data
  folder at a time, provided the folder supports file locks (a normal local folder does).
  If the lock can't be taken (for example in an unwritable folder or on some network
  volumes), Dojix opens anyway, and a copy running on another Mac that shares the folder
  is not detected.
- **The key.** With App Lock off, the journal key is stored in your macOS Keychain. With
  App Lock on, it is stored only sealed with your password (PBKDF2-SHA256, 600,000
  iterations), so the journal can't be decrypted without the password, even by someone
  who copies the files. Dojix locks on the idle time you choose, sleep, screen lock, user
  switch, hide and minimize; if that happens while a password is still being checked, it
  locks as soon as the check finishes. Wrong passwords are throttled wherever the password
  is asked for (lock screen and Settings); if the Keychain won't return the wrong-password
  count, no password is checked until it can be read (the count is never reset by that).
  When the key changes, the old key stays stored
  (wrapped with the password) until the journal opens with the new key and every journal
  copy and screenshot Dojix finds has been re-encrypted; a folder it can't list counts as
  not done yet.
- **Rollback.** Every save is numbered inside the encrypted file and in the Keychain. An
  older copy of the journal put back on disk is never opened silently, as long as macOS
  lets Dojix update its Keychain record (if macOS asks about Dojix's Keychain items, for
  example after an update, choose Always Allow). Dojix never shows a dialog for this
  record: if it can't be read, or a save can't update it (the Keychain is locked at that
  moment, or access was allowed only once), Dojix keeps working, and a copy at least as
  new as the last number it could store opens without the warning.
- **Backups.** Password-protected backups use AES-256-GCM with PBKDF2-SHA256 (600,000
  iterations). Every restore is validated (schema and every row) before anything is
  replaced.
- **Network.** Dojix works offline. Optional features use your own API keys (kept in the
  Keychain), are off by default and use HTTPS only. AI analysis sends summary statistics,
  never individual trades or notes, and only when you click *Run Analysis*. There is no
  telemetry.

What it does not protect against:

- **A running, unlocked Dojix.** While the journal is unlocked it is decrypted in memory.
  Malware running as your user, or anyone using your unlocked Mac, can see it. Lock Dojix
  (or turn on App Lock with a short idle time) when you step away.
- **App Lock off.** Without App Lock, anyone who can use your logged-in macOS account can
  open the journal, because the key is in your login Keychain.
- **Files you export.** Backups without a password, and CSV and PDF exports, are not
  encrypted. Preferences such as the watchlist, trading checklist and display settings
  are kept in Dojix's ordinary preferences file, which is not encrypted.
- **Forgotten passwords.** There is no recovery. A forgotten App Lock password means
  erasing the local data and restoring a backup; a forgotten backup password means that
  backup can't be opened.
- **Unsigned builds.** Release builds are not signed with an Apple Developer ID or
  notarized, so macOS can't confirm who built them. Download Dojix only from this
  repository's Releases page, compare the `.sha256` file published with each release, or
  build it from source.
