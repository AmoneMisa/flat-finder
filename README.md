# Flat Finder

Cross-platform flat & house search for **Romania, Ukraine, Kazakhstan and
Uzbekistan**, with a Flutter client, PostgreSQL-backed search, OpenStreetMap
places and normalized listings from multiple external sources.

> Kyrgyzstan is intentionally omitted for now.

## Architecture

```text
source
  -> fetch / parse
  -> normalize / enrich
  -> PostgreSQL
  -> optional Elasticsearch ranking
  -> public API
  -> Flutter / Personal Site
```

The backend is a modular Node.js application with a separate worker process:

```text
flat-finder/
├── backend/          Node 24 API, worker, migrations and domain modules
├── olx-fetcher/      Python + curl_cffi OLX sidecar
├── social-fetcher/   Facebook / Threads / LinkedIn public-source sidecar
├── olx-router/       OLX fetcher routing
├── elasticsearch/    Elasticsearch image + vendored ICU analysis plugin
└── app/              Flutter client
```

### Runtime ownership

- **API** serves searches and public/client endpoints. Normal listing search reads
  PostgreSQL; it does not execute marketplace crawlers.
- **Worker** owns recurring crawl dispatch, PostgreSQL queue execution,
  availability sweeps, social-housing scheduling and places refresh.
- **PostgreSQL** is the primary listing/search store and durable crawl queue.
- **Elasticsearch** is optional and is used for text ranking; PostgreSQL search
  remains available when Elasticsearch is unavailable.
- **Migrations** own database schema. API and worker refuse to start when the
  migration set is incomplete.

RabbitMQ and Redis are not part of the current architecture.

## Listing sources

| Source | Method | Notes |
| --- | --- | --- |
| **OLX** | Python `curl_cffi` sidecars behind `olx-router` | Fetches OLX pages with browser impersonation and feeds normalized work through the worker pipeline. |
| **Telegram** | Separate GramJS / MTProto worker | Public channels configured per country. |
| **Public social sources** | `social-fetcher` | Facebook / Threads / LinkedIn discovery where publicly readable. |
| **Custom URL** | Legacy isolated adapter | User-supplied HTTP(S) source; kept separate from normal PostgreSQL search and guarded as an external-fetch path. |

Telegram and other unstructured posts are normalized from free text before
storage. Source configuration lives primarily in `backend/src/countries.js` and
`backend/src/scrapers/*`.

Synthetic/demo listings are **never returned in production**. Mock generation is
kept only for development/test compatibility.

> External sites can change markup, APIs, anti-bot rules and Terms of Service.
> Check source requirements before operating scrapers at scale.

## Run the stack

Production and CI use **Node 24 LTS** for the backend.

The recommended local/deployment path is Docker Compose because it guarantees
migrations run before API and worker startup:

```bash
docker compose up -d
```

`flat-finder-migrate` is a one-shot service. Both `flat-finder-backend` and
`flat-finder-worker` depend on its successful completion.

For backend-only development with an already configured PostgreSQL instance:

```bash
cd backend
npm ci
npm run migrate
npm start
```

The API listens on port `4000` by default.

Quick check:

```bash
curl "http://localhost:4000/api/listings?countries=RO,UA,KZ,UZ&propertyType=flat&limit=5"
```

### Main public endpoints

- `GET /health`
- `GET /api/countries`
- `GET /api/rates`
- `GET /api/listings`
- `GET /api/listing/:source/:id`
- `POST /api/sources/validate`

Operational stats/manual refresh are not public client APIs. They live under
protected `/internal/*` routes and require a server-side internal key.

`GET /api/listings?refresh=1` keeps the existing client contract, but for normal
PostgreSQL search it only requests a new durable crawl generation; the worker
executes the crawl asynchronously.

If PostgreSQL search is unavailable, normal listing search returns an explicit
`503` degraded response instead of silently running crawlers in the HTTP
process.

## Database migrations

SQL migrations live in `backend/migrations/` and use ordered names such as:

```text
001_baseline_listings.sql
002_crawl_tasks.sql
003_search_indexes.sql
...
```

Run them manually with:

```bash
npm run migrate --prefix backend
```

The migration runner and startup readiness check share the same filename policy,
so a newly added valid migration automatically becomes required before runtime
startup.

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

## Filters

The public listing contract includes, among others:

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

Legacy in-memory filtering is retained only for the isolated custom-source path.
CI compares key filter semantics against PostgreSQL search to prevent the two
implementations from drifting.

## Configuration

Copy `sample.env` and set the values needed by your deployment. Important groups
include:

- PostgreSQL credentials
- `QUEUE_INTERNAL_KEY` and optional dedicated internal keys
- OLX / Telegram worker URLs
- AI worker configuration
- social-fetcher tuning
- bounded legacy custom-source cache size

The normal listing pipeline does not require Redis or RabbitMQ.

## Useful implementation paths

- `backend/src/app.js` — Express composition root
- `backend/src/server.js` — API process lifecycle
- `backend/src/worker.js` — recurring work and queue execution
- `backend/src/listing-routes.js` — public listing search orchestration
- `backend/src/postgres-search.js` — PostgreSQL listing search
- `backend/src/legacy-listing-filter.js` — isolated legacy filter implementation
- `backend/src/pgQueue.js` — durable PostgreSQL crawl queue operations
- `backend/src/migrate.js` — versioned migration runner
- `backend/src/scrapers/` — source adapters
- `backend/src/textparse.js` — free-text listing extraction
- `olx-fetcher/app.py` — OLX sidecar
- `app/lib/` — Flutter application
