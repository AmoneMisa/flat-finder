# Flat Finder

Cross-platform (Android + desktop) flat & house search for **Romania, Ukraine,
Kazakhstan, Uzbekistan**, with an OpenStreetMap map and filters (apartment/house,
owner/agency, price range, keyword, country). Each listing card shows **auto-derived
tags** (furnished, renovated, parking, owner/agency, rooms, …) parsed from the
listing description.

> Kyrgyzstan is intentionally omitted for now.

```
flat-finder/
├── backend/     Node.js scraper API (runs today, Node 24)
└── app/         Flutter client (Android + Windows/macOS/Linux desktop)
```

## How data works

Each country aggregates **multiple sources in parallel**, all normalized to one
schema and merged/de-duplicated:

| Source | Method | Notes |
|--------|--------|-------|
| **OLX** (olx.ro/.ua/.kz/.uz) | Internal JSON API | Primary source, works out of the box |
| **Reddit** | Public JSON API / OAuth | Set `REDDIT_CLIENT_ID` + `REDDIT_CLIENT_SECRET` env — anonymous access is often blocked |
| **Telegram** | `t.me/s/<channel>` web preview | Public **channels** only (private groups aren't readable); configure real channels |
| **Threads** | Best-effort inline JSON | Meta has no public read API — usually returns nothing without the official Graph API |

Free-text sources (Reddit/Telegram/Threads) have no structured price/rooms, so
those are parsed from the post text; they have no coordinates so they appear in
the **list** but not on the map.

If **all** sources for a country come back empty (blocked/rate-limited), that
country falls back to generated **demo data** and the app shows an amber banner
naming it. So the app is always usable.

> ⚠️ Scraping note: these sites' HTML/APIs can change and their Terms of Service
> may restrict scraping. Sources, category IDs, subreddits and Telegram channels
> are centralized in `backend/src/countries.js` and `backend/src/scrapers/*`.
> Use responsibly and check each site's ToS before running at scale.

### Enabling / configuring sources

- **Reddit**: create a "script" app at https://www.reddit.com/prefs/apps and run
  the backend with `REDDIT_CLIENT_ID=... REDDIT_CLIENT_SECRET=... npm start`.
- **Telegram**: put real public channel usernames in `telegramChannels` per
  country in `backend/src/countries.js` (the defaults are placeholders).
- **Threads**: plug the official Threads/Instagram Graph API into
  `backend/src/scrapers/threads.js`.

---

## 1. Run the backend

Requires Node.js 18+ (tested on Node 24).

```bash
cd backend
npm install
npm start          # http://localhost:4000
```

Quick check:

```bash
curl "http://localhost:4000/api/listings?countries=RO,UA,KZ,UZ&propertyType=flat&limit=5"
```

Endpoints:
- `GET /api/countries` — list of supported countries + map centers
- `GET /api/listings?countries=RO,UA&propertyType=flat|house|any&agency=owner|agency|any&priceMin=&priceMax=&query=`

---

## 2. Run the Flutter app

Flutter is **not installed yet** on this machine. Install it first:
https://docs.flutter.dev/get-started/install

Then generate the native platform folders (android/, windows/, etc.) into the
existing `app/` directory — this keeps the `lib/` and `pubspec.yaml` already
written here:

```bash
cd app
flutter create .                # generates android/, windows/, ... in place
flutter pub get
```

### Android (emulator)

The app auto-detects the Android emulator and talks to the host at
`http://10.0.2.2:4000`. Android blocks plain HTTP by default, so enable
cleartext for local dev — in `app/android/app/src/main/AndroidManifest.xml`
add to the `<application>` tag:

```xml
<application
    android:usesCleartextTraffic="true"
    ... >
```

Also make sure INTERNET permission is present (in the same manifest):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Then:

```bash
flutter run                     # with an emulator/device connected
# or build an APK:
flutter build apk --release
```

For a **physical Android phone**, point the app at your PC's LAN IP:

```bash
flutter run --dart-define=API_BASE=http://192.168.x.x:4000
```

### Desktop (Windows)

```bash
flutter config --enable-windows-desktop
flutter run -d windows
```

(Uses `http://localhost:4000` automatically.)

---

## Filters implemented

- **Country** multi-select (RO / UA / KZ / UZ)
- **Property type**: Any / Apartment (full flat) / House
- **Seller**: Any / Private owner / Real-estate agency
- **Price**: min & max
- **Keyword** search
- **Map view** (OpenStreetMap) with price pins — orange = agency, green = owner
- **List view** with photos, price, rooms, area, city

## Tuning the scrapers

- `backend/src/countries.js` — per-country sources list, OLX hosts + real-estate
  root category IDs, subreddits, Telegram channels, map centers, search terms.
- `backend/src/scrapers/olx.js` — OLX API request + field parsing.
- `backend/src/scrapers/reddit.js` — Reddit search (+ optional OAuth).
- `backend/src/scrapers/telegram.js` — public Telegram channel parsing.
- `backend/src/scrapers/threads.js` — Threads best-effort adapter.
- `backend/src/tags.js` — keyword → card-tag rules (EN/RO/RU/UA).
- `backend/src/textparse.js` — price/rooms/area extraction from free text.
- `backend/src/mock.js` — demo data generator used as fallback.
