# QuotaBar

QuotaBar is a small, read-only macOS menu bar app that shows the remaining subscription quota exposed by Claude Code, Codex CLI, and Grok Build.

The menu bar shows all three providers at once. Each provider displays only the windows it actually returns, such as `5h` and `W`; missing windows are never estimated.

## Requirements

- macOS 14 or later
- Claude Code installed and signed in with a Claude subscription
- Codex CLI or the ChatGPT desktop app installed and signed in
- Grok Build installed and signed in with a Grok subscription

QuotaBar reuses the official clients' existing OAuth sessions. It does not accept API keys or provide its own login screen.

## Build and run

```sh
./Scripts/package.sh
open outputs/QuotaBar.zip
```

Unzip `QuotaBar.zip`, move `QuotaBar.app` to Applications if desired, and open it. The app has no Dock icon. Click its menu bar text to see reset times, refresh manually, or quit. Values refresh automatically every five minutes.

## Verify

```sh
swift test
QUOTABAR_LIVE_TESTS=1 swift test
```

Live tests require all three clients to be signed in. The packaged app measured 40,512 KB RSS after refreshing all providers, with no persistent child process, on the development Mac.

## Privacy

- OAuth tokens are kept in memory only and are never logged or cached by QuotaBar.
- The local cache contains only quota percentages and timestamps.
- Claude usage is read with the Claude Code Keychain credential.
- Codex and Grok usage are read through their official local client protocols.
- No browser automation, embedded browser, analytics, or usage history is included.
