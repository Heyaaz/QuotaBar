# QuotaBar

QuotaBar is a small, read-only macOS menu bar app that shows the remaining subscription quota exposed by Claude Code, Codex CLI, and Grok Build.

The menu bar shows all three providers at once, identified by their logos. Each provider displays only the windows it actually returns, such as `5h` and `W`; missing windows are never estimated. If a refresh fails, the last successful value remains visible and the details popover marks it as stale.

## Features

- Refreshes Claude, Codex, and Grok quota every five minutes using existing OAuth sessions
- Sends a native notification when a quota first crosses 20% or 5% remaining
- Offers full and lowest-only menu bar display modes
- Can launch automatically at login through the gear menu

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

Unzip `QuotaBar.zip`, move `QuotaBar.app` to Applications if desired, and open it. The app has no Dock icon. Click its menu bar text to see reset times, refresh manually, or quit. The gear menu controls launch at login and menu bar display mode.

## Verify

```sh
swift test
QUOTABAR_LIVE_TESTS=1 swift test
```

Live tests require all three clients to be signed in. The packaged app measured 42,544 KB RSS after refreshing all providers, with no persistent child process, on the development Mac.

## Privacy

- OAuth tokens are kept in memory only and are never logged or cached by QuotaBar.
- The local cache contains only quota percentages and timestamps.
- Claude usage is read with the Claude Code Keychain credential.
- Codex and Grok usage are read through their official local client protocols.
- No browser automation, embedded browser, analytics, or usage history is included.

Claude, OpenAI, and xAI logos are trademarks of their respective owners and are used only to identify the corresponding service.
