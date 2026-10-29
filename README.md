# QR to Telegram

A SwiftUI iPhone app (iOS 17+) that scans a Telegram bot QR code, previews its `/start` command, and sends it from the signed-in personal account through official Telegram TDLib.

For example, `https://t.me/somebot?start=7-1793284285-FxxN8uYXaVmu` becomes `/start 7-1793284285-FxxN8uYXaVmu`. The destination must match the username compiled into the app. Both `https://t.me/<bot>?start=<value>` and `tg://resolve?domain=<bot>&start=<value>` are supported. Other links and arbitrary QR text are rejected.

## Run on an iPhone

1. Open `QRBot.xcodeproj` in Xcode 16 or newer. Let Swift Package Manager download TDLib (a large binary download is required the first time).
2. In `QRBot/AppConfiguration.swift`, replace `REPLACE_WITH_BOT_USERNAME` with the real bot username, without `@`. The app refuses to scan/send until configured. `somebot` in the example is not assumed to be your destination.
3. Select the QRBot target → Signing & Capabilities, choose your development team, and set a unique bundle identifier. Connect your iPhone and select it as the run destination. Enable Developer Mode if required by iOS.
4. Ensure the iPhone has a device passcode. Build and run.
5. Obtain your application's `api_id` and `api_hash` at [Telegram API development tools](https://my.telegram.org/apps). Enter them in the app and tap **Save securely**. They disappear from the form immediately and cannot be revealed/exported by the app.
6. Tap **Unlock Telegram**, authenticate with Face ID/Touch ID/passcode, and sign in with the account owner's phone number. Enter Telegram's login code and, if requested, the two-step password or email verification code. Never put these secrets in source control.
7. Tap **Scan QR code**, allow camera access, review the extracted value, and tap **Send to bot**. The app authenticates the device owner again before sending. You can also enter the link manually if the camera is unavailable.

Telegram does not issue personal access tokens for this workflow. The API ID/hash identify your application; phone authentication creates an authorized personal-account session. A BotFather token authenticates a bot and cannot replace this personal account login. This app uses TDLib's `sendBotStartMessage`, the official equivalent of opening a bot start link. It does not scrape Telegram Web sessions or use a forwarding server.

## Credential and session protection

- API credentials and a random 256-bit TDLib database encryption key live in an access-controlled iOS Keychain item. The item uses `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`, `.userPresence`, and no iCloud synchronization. Removing the device passcode invalidates access to these secrets.
- The authorized Telegram session stays in TDLib's encrypted database. Its directory uses complete iOS file protection and is excluded from backup. Message/chat/file caches and secret chats are disabled. No Telegram media is requested or downloaded.
- Saved credentials have no display, copy, or export flow. Login fields clear after submission and when backgrounded. The app does not persist QR values or put secrets in preferences, analytics, the clipboard, or logs. TDLib logging is disabled, and error messages omit Telegram's raw response text.
- App content is covered while inactive. Backgrounding closes TDLib and locks the account; unlocking again requires Keychain authentication. Credentials necessarily exist in app memory while used. Swift and TDLib do not guarantee immediate erasure of every memory copy.
- **Sign out and erase account**, while connected, signs out through Telegram and removes the local session and Keychain item. **Erase local account**, while locked, removes only local data; revoke the remote session in Telegram → Settings → Devices if needed. iOS can retain Keychain items after app uninstall, so use the erase action before uninstalling if removal is wanted.

“Cannot read after saving” means the app does not reveal stored values through its UI. No usable Telegram credential can be made mathematically unreadable to the app that uses it. A compromised/jailbroken device or someone controlling a development build may inspect runtime memory. Use a signed Release build for regular use.

## Dependencies

The messaging engine is [official TDLib](https://core.telegram.org/tdlib/). The XCFramework is a community-built distribution from [Swiftgram/TDLibFramework](https://github.com/Swiftgram/TDLibFramework), not a Telegram-issued SDK binary. `Dependencies/TDLibFramework/Package.swift` pins distribution `1.8.69-ea3f69ce` and its SHA-256 checksum, taken from the upstream distribution manifest. Xcode verifies the checksum. You can replace this binary target with your own build of official TDLib if required. The small C bridge declares TDLib's supported 1.8 JSON interface; it will need migration before TDLib 2.0.

The app handles existing-account phone/code/password and email/code authentication. Other authorization states are shown as unsupported; account registration and paid SMS authentication flows are not implemented. Network failures are surfaced without automatically retrying sends. A send that times out may already have reached Telegram: check the bot chat before retrying. Queued messages are labeled as queued until TDLib reports delivery success/failure. Backgrounding clears the local preview/status; it does not retract a request already submitted to Telegram.

## Verification

In the implementation environment, the parser tests passed (30 cases across five test functions), and all app Swift sources compiled to an arm64 iOS object with warnings treated as errors. The Xcode project and Info.plist passed syntax validation. Full linking and on-device testing remain unverified: the environment could not download the TDLib binary because GitHub hostname resolution was blocked, and simulator access was unavailable.

Run parser tests without downloading TDLib:

```sh
swift test --disable-sandbox
```

Build the iOS app after TDLib has downloaded:

```sh
xcodebuild -project QRBot.xcodeproj -scheme QRBot \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

On a physical iPhone, verify passcode/biometric authentication, relaunch/unlock, background locking, camera permission denial/retry, a real bot QR, an incorrect bot QR, offline sending, and account erasure. Camera, Keychain access controls, and Telegram sign-in need device testing; the parser tests do not cover them.
