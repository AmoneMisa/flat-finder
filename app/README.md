# Flat Finder — mobile app

A Flutter (Android) client for the Flat Finder rental-listing aggregator. Searches, filters, and maps rental/sale listings scraped from OLX, Telegram, and user-added custom sources across Romania, Ukraine, Kazakhstan, and Uzbekistan, backed by the Node API in [`../backend`](../backend).

This app is mobile-only. It is never built or deployed server-side — always build and install it locally.

## Features

- **Search & filter** — keyword search, and a categorized filter sheet covering location (country/city/district/metro/microdistrict/quarter/local area, plus max distance from metro or a chosen landmark kind), sources, property type/deal type/agency/audience, price (range, tolerance, currency, price-per-m²), size (rooms, bedrooms, floor, building height, year, area), amenities (~20 toggles: parking, elevator, AC, dishwasher, TV, microwave, euro layout, etc.), tenant conditions and costs (pets/children/room-share, no-elevator/no-deposit/no-commission, commission % range), and sort/timing (posted-within, 9 sort modes).
- **Map view** — listing pins, freeform area drawing to filter by a drawn polygon, and a colored district/microdistrict/quarter/local-area overlay matching the website's map (same palette, same real administrative boundaries), with show/hide toggles per layer.
- **Listing detail** — full photo gallery, a grouped spec table (every field the backend returns), on-demand description translation, "reload from source" for a fresh scrape, share (a real `https://whiteslove.me/flat-finder?adv=<id>` link that opens the app directly if installed, the browser otherwise), and a price-vs-market-median indicator with 6-tone coloring matching the website.
- **Favorites** — saved listings, organized into country → city folders.
- **History** — recently viewed listings, newest first.
- **Presets** — save, rename, delete, and share a named filter combination.
- **Statistics** — a bar/line-chart sheet summarizing the current search (deal-type breakdown, price bands, geography, activity).
- **Deep linking** — `flatfinder://search?...`, `flatfinder://listing?id=<publicId>`, and the universal `https://whiteslove.me/flat-finder` link all open directly into the app.
- **Custom sources** — users can add their own Telegram channel / subreddit / listing page / RSS feed as an extra source, with live validation before it's saved.
- **Settings** — language (EN/RU), display currency, and theme (light / dark / dark-blue, all built from the website's own brand color tokens).

## Requirements

- Flutter SDK (stable channel — the app needs `intl ^0.20.2`, which requires a Flutter version recent enough to bundle that; if `flutter pub get` complains about `intl` version pinning, run `flutter upgrade` first).
- Android SDK + `cmdline-tools` (for `flutter build apk`); accept licenses once with `flutter doctor --android-licenses`.

## Building

```bash
cd app
flutter pub get
flutter build apk --release --split-per-abi
```

`--split-per-abi` produces three smaller per-architecture APKs instead of one large universal one, in `build/app/outputs/flutter-apk/`:

| File | Use for |
|---|---|
| `app-arm64-v8a-release.apk` | Essentially all Android phones from the last ~8 years — install this one |
| `app-armeabi-v7a-release.apk` | Older 32-bit ARM devices |
| `app-x86_64-release.apk` | x86 emulators |

Drop `--split-per-abi` for a single universal APK instead.

Every release build should bump the build number in `pubspec.yaml`'s `version: 1.0.0+N` line — Android may not cleanly replace an installed app over an unchanged version code, which can silently leave a stale build running.

## Backend connection

`ApiService._defaultBaseUrl()` picks the backend automatically:

- **Release builds** (`flutter build apk --release`) default to `https://whiteslove.me/flat-api` — the production backend, reached through an nginx proxy on whiteslove.me's existing HTTPS vhost. (It does **not** hit the backend's own `185.5.206.229:8082` directly — plain HTTP on a non-standard port gets silently dropped by some mobile carriers; 443 on an established domain isn't.)
- **Debug builds** default to `http://10.0.2.2:4000` on Android (the emulator's loopback to the host machine) or `http://localhost:4000` elsewhere.
- Either can be overridden: `flutter run --dart-define=API_BASE=http://192.168.x.x:4000`.

## Architecture

```
lib/
  models/       Listing, Filters, Country/CityLocations, DistrictZone/MapZones,
                SearchStatistics, MoneyAmount, MarketComparison
  services/     ApiService — all backend HTTP calls
  state/        AppState (search/paging/reload), SettingsState (lang/currency/
                theme, incl. BrandColors), FavoritesState, HistoryState,
                PresetsState — all ChangeNotifiers, persisted via
                SharedPreferences
  screens/      HomeScreen, ListingDetailScreen, FavoritesScreen,
                HistoryScreen, SettingsScreen
  widgets/      FilterSheet, MapView, ListingCard, StatsSheet
  utils/        format.dart (labels/formatting), price_tone.dart (6-tone
                price-vs-median coloring), share_link.dart (deep-link
                build/parse), sort.dart (client-side ordering)
  l10n/         strings.dart — hand-rolled EN/RU string table (no .arb/gen-l10n)
```

State flows through `provider`: screens/widgets read `ChangeNotifier`s via `context.watch`/`context.read`; nothing talks to `ApiService` directly except the state classes (and `MapView`/`StatsSheet`, which own a scoped `ApiService` for their map-zones/stats calls).

### Pagination

`AppState.search()` fetches the first page; `AppState.loadMore()` (triggered on scroll) fetches the next page via the backend's opaque `cursor`/`nextCursor` and appends, de-duplicating by `source:id`. The results count in the summary bar (`state.total`) is the backend's **total matching count**, refreshed on every page fetch — not "how many are loaded so far" — so it stays accurate as you scroll and won't jump around.

### Rate limiting

Manual reloads ("Reload all", "Reload this listing") and the translation endpoint are flood-protected server-side (HTTP 429). `ApiService` throws `RateLimitException(retryAfterMs)` on 429, parsed from the response body or the `Retry-After` header; `AppState` surfaces this as a cooldown the UI disables the reload button for.

### Deep linking (`utils/share_link.dart`)

Three link shapes all resolve inside the app (see `home_screen.dart`'s `_applyLink`):
- `flatfinder://search?...` — a shared search (same shape as `Filters.toQueryParams()`).
- `flatfinder://listing?id=<publicId>` — a specific listing, app-only.
- `https://whiteslove.me/flat-finder?adv=<publicId>` — the same listing link the website itself generates; opens the site in a browser if the app isn't installed, or the app directly if it is (Android App Links, via the `autoVerify` intent-filter in `AndroidManifest.xml` and `assetlinks.json` on the site). Opening a listing this way retries up to 5 times over ~7.5s, since a just-scraped listing may not be indexed yet.

`publicId` is the listings table's stable BIGSERIAL id (not the source-specific `id`), used because a listing's `source`+`id` pair isn't stable enough to share.

## Known gaps

- **Location name translation**: city/district/metro names come from the backend as plain strings in whatever language the source used (e.g. "Andijan", "Bukhara") — the website localizes these via a large translation table inside `@whiteslove/parsing-lexicon` (`geography-display.js`) that hasn't been ported to Dart. Everything else in the UI is fully localized (EN/RU); this is specifically proper-noun geography data.
- **Release signing**: release builds are currently signed with the Android debug keystore (no dedicated release `signingConfig` exists yet). This also means the site's `assetlinks.json` (for Android App Link verification) is pinned to one machine's debug-signing fingerprint — set up a real release keystore and update `assetlinks.json` accordingly before wider distribution.
