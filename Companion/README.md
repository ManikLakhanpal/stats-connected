# Stats Companion (iOS)

Read-only iPhone client for the [System Stats](https://www.system-stats.com) account used by the Stats macOS Remote module.

## Requirements

- Xcode 15+
- iOS 17+
- Stats on each Mac signed into System Stats with remote monitoring enabled

## Open

```bash
open Companion/StatsCompanion.xcodeproj
```

Build and run the **StatsCompanion** scheme on a simulator or device.

## Sign in

1. Tap **Sign in** and complete authorization in Safari.
2. The app polls `oauth.system-stats.com` using the same device-code flow as the Mac app (`client_id=stats`).
3. Tokens are stored in the iOS Keychain.

## Architecture

- REST: `api.system-stats.com/v1/machine`, `/host`, `/group`, `/account`
- Live CPU/RAM: SSE `GET /v1/machine/{id}/sse`

No changes to the macOS Stats app are required.
