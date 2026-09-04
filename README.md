# Flat Finder

Flutter client for Flat Finder — cross-platform flat & house search for
**Romania, Ukraine, Kazakhstan and Uzbekistan**.

> Kyrgyzstan is intentionally omitted for now.

The backend (API, worker, scrapers, migrations) has moved to the consolidated
[`whiteslove.me-backend-platform`](https://github.com/AmoneMisa/whiteslove.me-backend-platform)
repository under `apps/flats/`. This repo now contains only the Flutter client
and its own CI.

## Flutter app

Install Flutter, then from `app/`:

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

### Android emulator

The app can use `http://10.0.2.2:4000` for a backend running on the development
host. For a physical device, pass a reachable API address:

```bash
flutter run --dart-define=API_BASE=http://192.168.x.x:4000
```

### Windows desktop

```bash
flutter config --enable-windows-desktop
flutter run -d windows
```

### Release build

```powershell
./build-release.ps1
```

After publishing new APKs to the website's `public/files/`, update
`public/files/version.json` there (`version`, `versionCode` — the pubspec
build number after the `+`, and `apkUrl`) so installed apps see the update
prompt. See [update_service.dart](app/lib/services/update_service.dart).

### Automated release (GitHub Actions)

[`release-and-deploy.yml`](.github/workflows/release-and-deploy.yml) does the
above for you: run it manually from the Actions tab (workflow_dispatch) and it
will, in order —

1. Bump `app/pubspec.yaml`'s build number (the part after `+`) and commit it.
2. Build a signed release APK with the real production keystore.
3. Push that APK and an updated `version.json` straight to `Personal-Site`'s
   `master`, which triggers that repo's own `deploy.yml` and ships it live.

It runs on demand only — nothing here fires on every push — because a
release is a deliberate action, and step 3 pushes straight to the live site
with no review step in between.

Running it twice with no real changes in between is a no-op: a `last-released`
tag marks the commit the previous run shipped, and the workflow diffs
`app/lib`, `app/android`, `app/assets` and `app/pubspec.yaml` against it first
— if nothing there changed, it skips the build and deploy entirely instead of
reshipping the same code under a new build number.

One-time setup — add these as **repo secrets** on `AmoneMisa/flat-finder`
(Settings → Secrets and variables → Actions):

| Secret | What it is |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Your real release keystore (the `.jks` referenced by your local `app/android/key.properties`), base64-encoded: `certutil -encode key.jks key.b64` (Windows) or `base64 -w0 key.jks` (Linux/macOS/WSL) — paste the resulting text. |
| `ANDROID_KEYSTORE_PASSWORD` | That keystore's store password. |
| `ANDROID_KEY_ALIAS` | The key alias inside it (`flat-finder-upload` per `key.properties.example`, unless yours differs). |
| `ANDROID_KEY_PASSWORD` | That key's password. |
| `SITE_REPO_TOKEN` | A GitHub PAT (fine-grained, `Personal-Site` repo only, Contents: Read & write) letting this workflow push the APK there. `GITHUB_TOKEN` can't reach across repos. |

Using the wrong keystore here breaks in-place updates for everyone who
already has the app installed — Android refuses to install an update signed
with a different key than what's currently on the device, so double-check
this is the same `.jks` you've always released with.

## API contract

The app talks to the flats API's public listing search, which includes:

- country multi-select
- apartment / house
- sale / long-term rent / short-term rent
- owner / agency
- price and currency-aware ranges
- rooms, bedrooms, floor and area ranges
- city / district / metro
- amenities
- pets / children
- keyword search
- sort and pagination/cursor fields

## Useful implementation paths

- `app/lib/` — Flutter application
