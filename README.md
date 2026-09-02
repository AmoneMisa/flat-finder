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
