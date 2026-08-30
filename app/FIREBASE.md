# Mobile apartment push configuration

Apartment push notifications are owned by Flat Finder end to end. The Flutter
app stores presets locally and mirrors only enabled notification presets to
`PUT /api/mobile-subscriptions` using an anonymous locally generated device ID.
The Flat Finder backend scans those filters and delivers matching new listings
through FCM.

No Firebase service-account credential belongs in the app. The backend reads the
base64-encoded service-account JSON from `FIREBASE_SERVICE_ACCOUNT_B64` in the
normal Flat Finder runtime `.env`.

## Recommended Windows release build

From the repository root run:

```powershell
.\build-release.ps1
```

The script reads the current version from `app/pubspec.yaml`, injects Flat
Finder's public Firebase Android client options, builds split release APKs and
copies them to the repository-level `release/` directory with stable names such
as:

```text
FlatFinder-v1.0.0+38-arm64-v8a.apk
FlatFinder-v1.0.0+38-armeabi-v7a.apk
FlatFinder-v1.0.0+38-x86_64.apk
```

Use `./build-release.ps1 -Universal` when one universal APK is preferred. The
public Firebase values can be overridden with `FIREBASE_API_KEY`,
`FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, and `FIREBASE_PROJECT_ID`
environment variables or matching script parameters. The backend service-account
credential is never read by this script and must remain server-side.

## Manual build

The Android app needs only the public Firebase client options. Supply them as
Dart defines when building or running the app:

```bash
flutter build apk --release --split-per-abi \
  --dart-define=FIREBASE_API_KEY="$FIREBASE_API_KEY" \
  --dart-define=FIREBASE_APP_ID="$FIREBASE_APP_ID" \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="$FIREBASE_MESSAGING_SENDER_ID" \
  --dart-define=FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID"
```

The same defines can be passed to `flutter run` for a debug device build. When
one of these values is absent the application remains usable, but notification
toggles report that push transport is not configured instead of silently
registering a broken subscription.

Android 13+ notification permission is requested only after the user explicitly
enables notifications for a preset or turns on the notification master switch.
A notification tap carries the listing `publicId` and opens the existing listing
detail flow.
