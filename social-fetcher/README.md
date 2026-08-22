# Social fetcher

Internal public-data fetcher for Facebook, Threads and LinkedIn.

## Boundaries

- Public pages only.
- No account login, cookies, session tokens or stored credentials.
- No CAPTCHA solving or anti-bot challenge bypass.
- Facebook does not request comments/reactor lists or member lists.
- LinkedIn job search uses the public `jobs-guest` HTML endpoints.
- Explicit LinkedIn page/post/profile URLs are fetched only when publicly reachable; auth-wall responses are returned as `restricted: true` rather than bypassed.
- Target URLs are host-allowlisted to prevent SSRF.

## API

### Health

```http
GET /health
```

### Generic fetch

```http
POST /fetch
Content-Type: application/json
```

Facebook page or public group:

```json
{
  "source": "facebook",
  "target": "https://www.facebook.com/groups/123456789/",
  "limit": 50
}
```

Threads public profile:

```json
{
  "source": "threads",
  "username": "example",
  "limit": 50
}
```

LinkedIn public jobs:

```json
{
  "source": "linkedin",
  "mode": "jobs",
  "keywords": "frontend developer",
  "location": "Tashkent, Uzbekistan",
  "limit": 50,
  "details": false
}
```

LinkedIn explicit public URL:

```json
{
  "source": "linkedin",
  "mode": "public",
  "url": "https://www.linkedin.com/posts/..."
}
```

The backend exposes the same operation internally at `POST /internal/social/fetch` and requires `X-Queue-Key`, using `SOCIAL_INTERNAL_KEY` or `QUEUE_INTERNAL_KEY`.

## Environment

- `SOCIAL_MAX_ITEMS` — hard result cap, default `100`.
- `SOCIAL_HTTP_TIMEOUT` — HTTP timeout in seconds, default `30`.
- `SOCIAL_BROWSER_TIMEOUT_MS` — Playwright navigation timeout, default `45000`.
- `SOCIAL_BROWSER_CONCURRENCY` — concurrent Chromium sessions, default `1`.
- `THREADS_SCROLLS` — maximum public profile scroll passes, default `8`.
- `LINKEDIN_MAX_DETAIL_FETCHES` — maximum job detail requests when `details=true`, default `15`.
- `SOCIAL_IMPERSONATE` — curl_cffi browser fingerprint label, default `chrome124`.
