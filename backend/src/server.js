import express from 'express';
import cors from 'cors';
import {canonicalCityName, COUNTRIES, COUNTRY_CODES,} from './countries.js';
import {cityLocations} from './locations.js';
import {getListings} from './scrapers/index.js';
import {fetchOlxOffer} from './scrapers/olx.js';
import {validateSource} from './scrapers/custom.js';
import {applyFilters} from './normalize.js';
import {getRates} from './fx.js';
import {readPhoto, writePhoto} from './photoCache.js';
import {getLastRun, refreshAll, startScheduler} from './scheduler.js';
import {closeDb, dbHealth, getAvailableListingLocations, getDbStats, initDb,} from './db.js';
import {closeElasticsearch, elasticsearchHealth, initElasticsearch, searchListingMatches,} from './elasticsearch.js';

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 4000;

// Metadata for the app: which countries/currencies/map centers exist.
app.get('/api/countries', async (_req, res) => {
    try {
        const result =
            await Promise.all(
                COUNTRY_CODES.map(
                    async (code) => {
                        const country =
                            COUNTRIES[code];

                        const locations =
                            cityLocations(
                                code,
                            );

                        const cities =
                            new Set(
                                country.cities ??
                                [],
                            );

                        /*
                         * Пока расширяем автоматически
                         * именно Украину.
                         *
                         * Остальные страны продолжают
                         * работать по существующему
                         * curated-списку.
                         */
                        if (code === 'UA') {
                            try {
                                const rows =
                                    await getAvailableListingLocations(
                                        code,
                                    );

                                for (
                                    const row
                                    of rows
                                    ) {
                                    const city =
                                        canonicalCityName(
                                            code,
                                            row.city,
                                        );

                                    if (!city) {
                                        continue;
                                    }

                                    cities.add(
                                        city,
                                    );

                                    if (
                                        !locations[city]
                                    ) {
                                        locations[city] = {
                                            districts: [],
                                            metro: [],
                                        };
                                    }

                                    const district =
                                        String(
                                            row.district ??
                                            '',
                                        ).trim();

                                    if (
                                        district &&
                                        !locations[
                                            city
                                            ].districts
                                            .includes(
                                                district,
                                            )
                                    ) {
                                        locations[
                                            city
                                            ].districts
                                            .push(
                                                district,
                                            );
                                    }
                                }
                            } catch (err) {
                                /*
                                 * Ошибка Postgres metadata
                                 * не должна ломать загрузку
                                 * Flat Finder.
                                 *
                                 * В этом случае UI просто
                                 * получит старый static list.
                                 */
                                console.warn(
                                    `[locations] ` +
                                    `${code} dynamic locations failed: ` +
                                    `${err?.message ?? err}`,
                                );
                            }
                        }

                        for (
                            const location
                            of Object.values(
                            locations,
                        )
                            ) {
                            location.districts =
                                [
                                    ...new Set(
                                        location
                                            .districts ??
                                        [],
                                    ),
                                ].sort(
                                    (a, b) =>
                                        a.localeCompare(
                                            b,
                                            'uk',
                                        ),
                                );

                            location.metro =
                                [
                                    ...new Set(
                                        location
                                            .metro ??
                                        [],
                                    ),
                                ].sort(
                                    (a, b) =>
                                        a.localeCompare(
                                            b,
                                            'uk',
                                        ),
                                );
                        }

                        return {
                            code:
                            country.code,

                            name:
                            country.name,

                            currency:
                            country.currency,

                            center:
                            country.center,

                            cities:
                                [...cities]
                                    .sort(
                                        (a, b) =>
                                            a.localeCompare(
                                                b,
                                                'uk',
                                            ),
                                    ),

                            locations,
                        };
                    },
                ),
            );

        res.json(
            result,
        );
    } catch (err) {
        res
            .status(500)
            .json({
                error:
                    err?.message ??
                    String(err),
            });
    }
});

const VALID_SOURCES = ['olx', 'telegram'];

// Lightweight in-memory, per-IP flood protection for the *manual reload*
// endpoints only (a normal cached search is never rate-limited). It just stops
// one client from repeatedly triggering an expensive force-scrape. Keyed by
// bucket + IP; on limit it responds 429 and returns false so the caller bails.
const rlBuckets = new Map(); // `${bucket}:${ip}` -> last epoch ms
function checkRate(req, res, bucket, windowMs) {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const key = `${bucket}:${ip}`;
  const now = Date.now();
  const wait = (rlBuckets.get(key) || 0) + windowMs - now;
  if (wait > 0) {
    res.set('Retry-After', String(Math.ceil(wait / 1000)));
    res.status(429).json({ error: 'Too many reload requests', retryAfterMs: wait });
    return false;
  }
  rlBuckets.set(key, now);
  return true;
}

function parseFilters(q) {
  const num = (v) => (v == null || v === '' ? null : Number(v));
  const bool = (v) => (v === 'true' || v === '1' ? true : null);
  const sources = String(q.sources || '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => VALID_SOURCES.includes(s));
  // User-added custom source URLs (comma-separated), deduped and capped.
  const customSources = [
    ...new Set(
      String(q.customSources || '')
        .split(',')
        .map((s) => s.trim())
        .filter((s) => /^https?:\/\//i.test(s)),
    ),
  ].slice(0, 10);
  return {
    customSources,
    propertyType: ['flat', 'house', 'any'].includes(q.propertyType) ? q.propertyType : 'any',
    dealType: ['sale', 'longRent', 'shortRent', 'any'].includes(q.dealType) ? q.dealType : 'any',
    agency: ['owner', 'agency', 'any'].includes(q.agency) ? q.agency : 'any',
    audience: ['women', 'men', 'family', 'any'].includes(q.audience) ? q.audience : 'any',
    priceMin: num(q.priceMin),
    priceMax: num(q.priceMax),
    priceTolerance: num(q.priceTolerance), // allow results up to priceMax + this
    priceCurrency: q.priceCurrency ? String(q.priceCurrency).toUpperCase() : null,

    roomsMin: num(q.roomsMin),
    roomsMax: num(q.roomsMax),
    bedroomsMin: num(q.bedroomsMin),
    bedroomsMax: num(q.bedroomsMax),
    areaMin: num(q.areaMin),
    areaMax: num(q.areaMax),
    // Price per square metre, expressed in priceCurrency like priceMin/priceMax.
    pricePerSqmMin: num(q.pricePerSqmMin),
    pricePerSqmMax: num(q.pricePerSqmMax),
    floorMin: num(q.floorMin),
    floorMax: num(q.floorMax),
    totalFloorsMin: num(q.totalFloorsMin),
    totalFloorsMax: num(q.totalFloorsMax),
    yearMin: num(q.yearMin),
    yearMax: num(q.yearMax),
    newBuilding: bool(q.newBuilding),
    city: q.city ? String(q.city) : '',
    district: q.district ? String(q.district) : '',
    metro: q.metro ? String(q.metro) : '',
    query: q.query ? String(q.query) : '',
    // Exact lookup used by share links. It is applied to the already warmed
    // country snapshot, so a shared listing can be restored even when it is not
    // part of the first paginated result set.
    listingId: q.listingId ? String(q.listingId) : '',
    // Tenant conditions (only "require allowed" / "room only" are meaningful).
    pets: bool(q.pets),
    children: bool(q.children),
    roomOnly: bool(q.roomOnly),
    maxAgeDays: num(q.maxAgeDays), // "posted within N days" freshness cap
    sources, // empty array = all sources
    offset: num(q.offset) ?? 0,
    limit: Math.min(num(q.limit) ?? 40, 60),
  };
}

function listingSearchKey(listing) {
  return [
    String(
        listing.source || '',
    ).toLowerCase(),

    String(
        listing.country || '',
    ).toUpperCase(),

    String(
        listing.id,
    ),
  ].join(':');
}

function compareListingsByDate(a, b) {
  const ta =
      a.createdAt
          ? Date.parse(
              a.createdAt,
          )
          : NaN;

  const tb =
      b.createdAt
          ? Date.parse(
              b.createdAt,
          )
          : NaN;

  const va =
      Number.isNaN(ta)
          ? -Infinity
          : ta;

  const vb =
      Number.isNaN(tb)
          ? -Infinity
          : tb;

  return vb - va;
}

// Main search endpoint. Accepts a comma-separated list of country codes.
// GET /api/listings?countries=RO,UA&propertyType=flat&agency=owner&priceMin=&priceMax=&query=
app.get('/api/listings', async (req, res) => {
  const force =
      req.query.refresh === '1' ||
      req.query.refresh === 'true';

  if (
      force &&
      !checkRate(
          req,
          res,
          'reloadAll',
          8000,
      )
  ) {
    return;
  }

  const filters =
      parseFilters(
          req.query,
      );

  const requested =
      String(
          req.query.countries ||
          COUNTRY_CODES.join(','),
      )
          .split(',')
          .map(
              (value) =>
                  value
                      .trim()
                      .toUpperCase(),
          )
          .filter(
              (country) =>
                  COUNTRY_CODES.includes(
                      country,
                  ),
          );

  const codes =
      requested.length
          ? requested
          : COUNTRY_CODES;

  /*
   * Локализованные названия города.
   */
  if (filters.city) {
    const forms =
        new Set([
          filters.city,
        ]);

    for (
        const code
        of codes
        ) {
      for (
          const alias
          of (
          COUNTRIES[code]
              ?.cityAliases
              ?.[filters.city] ??
          []
      )
          ) {
        forms.add(
            alias,
        );
      }
    }

    filters.cityAliases =
        [...forms];
  }

  try {
    /*
     * Поиск и получение snapshot можно
     * запускать параллельно.
     */
    let searchError =
        null;

    const searchPromise =
        filters.query
            ? searchListingMatches(
                filters.query,
                {
                  countries:
                  codes,

                  sources:
                  filters.sources,
                },
            ).catch(
                (err) => {
                  searchError =
                      err?.message ??
                      String(err);

                  console.warn(
                      `[elasticsearch] ` +
                      `search fallback: ` +
                      `${searchError}`,
                  );

                  return null;
                },
            )
            : Promise.resolve(
                null,
            );

    const [
      results,
      searchMatches,
    ] =
        await Promise.all([
          Promise.all(
              codes.map(
                  (code) =>
                      getListings(
                          code,
                          filters,
                          {
                            force,
                          },
                      ),
              ),
          ),

          searchPromise,
        ]);

    const degraded = [];

    const sourceCounts = {};

    const sourceErrors = [];

    let warming =
        false;

    let listings =
        [];

    results.forEach(
        (result, index) => {
          if (
              result.degraded
          ) {
            degraded.push(
                codes[index],
            );
          }

          if (
              result.warming
          ) {
            warming =
                true;
          }

          for (
              const [
                name,
                count,
              ]
              of Object.entries(
              result.sourceCounts ??
              {},
          )
              ) {
            sourceCounts[name] =
                (
                    sourceCounts[name] ??
                    0
                ) + count;
          }

          if (
              Array.isArray(
                  result.sourceErrors,
              )
          ) {
            sourceErrors.push(
                ...result.sourceErrors,
            );
          }

          listings =
              listings.concat(
                  result.listings,
              );
        },
    );

    /*
     * FX для обычных price filters.
     */
    let fxRates =
        null;

    try {
      fxRates =
          (
              await getRates()
          ).rates;
    } catch {
      /*
       * FX недоступен —
       * остаётся старое поведение.
       */
    }

    /*
     * Если Elasticsearch успешно
     * отработал query, applyFilters
     * больше НЕ должен повторно
     * делать hay.includes().
     *
     * Если ES недоступен —
     * оставляем original filters,
     * поэтому старый includes()
     * автоматически становится fallback.
     */
    const memoryFilters =
        searchMatches
            ? {
              ...filters,

              query:
                  '',
            }
            : filters;

    listings =
        applyFilters(
            listings,
            memoryFilters,
            fxRates,
        );

    /*
     * ES определяет:
     *
     * 1. какие объявления совпали;
     * 2. порядок relevance.
     */
    if (searchMatches) {
      listings =
          listings.filter(
              (listing) =>
                  searchMatches
                      .rank
                      .has(
                          listingSearchKey(
                              listing,
                          ),
                      ),
          );

      listings.sort(
          (a, b) => {
            const keyA =
                listingSearchKey(
                    a,
                );

            const keyB =
                listingSearchKey(
                    b,
                );

            const rankA =
                searchMatches
                    .rank
                    .get(
                        keyA,
                    );

            const rankB =
                searchMatches
                    .rank
                    .get(
                        keyB,
                    );

            if (
                rankA !==
                rankB
            ) {
              return (
                  rankA -
                  rankB
              );
            }

            /*
             * Одинаковая relevance —
             * свежее объявление выше.
             */
            return compareListingsByDate(
                a,
                b,
            );
          },
      );
    } else {
      /*
       * Без query либо если ES
       * недоступен — старое поведение.
       */
      listings.sort(
          compareListingsByDate,
      );
    }

    const count =
        listings.length;

    const offset =
        Math.max(
            0,
            filters.offset ||
            0,
        );

    const page =
        listings.slice(
            offset,
            offset +
            filters.limit,
        );

    res.json({
      count,

      degradedCountries:
      degraded,

      sourceCounts,

      sourceErrors,

      warming,

      filters,

      /*
       * Удобно для проверки,
       * какой search path реально
       * использовался.
       */
      searchEngine:
          filters.query
              ? (
                  searchMatches
                      ? 'elasticsearch'
                      : 'fallback'
              )
              : null,

      searchIndexedMatches:
          searchMatches
              ?.total ??
          null,

      searchTruncated:
          searchMatches
              ?.truncated ??
          false,

      listings:
      page,
    });
  } catch (err) {
    res
        .status(500)
        .json({
          error:
              err?.message ??
              String(err),
        });
  }
});

// "Reload this listing": re-fetch a single offer fresh from its source so the
// user can refresh a stale card (price/photos/availability). Flood-protected.
// Only OLX exposes a per-offer endpoint; other sources return 400.
// GET /api/listing/:source/:id?country=RO
app.get('/api/listing/:source/:id', async (req, res) => {
  if (!checkRate(req, res, 'reloadOne', 1500)) return;
  const source = String(req.params.source).toLowerCase();
  const id = String(req.params.id);
  const code = String(req.query.country || '').toUpperCase();
  const country = COUNTRIES[code];
  if (!country) return res.status(400).json({ error: 'Unknown country' });
  if (source !== 'olx') {
    return res.status(400).json({ error: 'Reload not supported for this source' });
  }
  try {
    const listing = await fetchOlxOffer(country, id);
    if (!listing) return res.status(404).json({ error: 'Listing no longer available' });
    res.json({ listing });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// Validate a user-submitted custom source URL before they add it. Fetches the
// page server-side (SSRF-guarded) and reports how many listings it could read.
// POST /api/sources/validate  { url, country? }
app.post('/api/sources/validate', async (req, res) => {
  const url = String(req.body?.url || '').trim();
  if (!url) return res.status(400).json({ ok: false, error: 'Missing url' });
  const code = String(req.body?.country || 'RO').toUpperCase();
  const country = COUNTRIES[code] ?? COUNTRIES[COUNTRY_CODES[0]];
  const result = await validateSource(url, country);
  res.json(result);
});

// Exchange rates (relative to USD) for client-side price normalization.
app.get('/api/rates', async (_req, res) => {
  try {
    const { base, rates, at } = await getRates();
    res.json({ base, rates, fetchedAt: new Date(at).toISOString() });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Proxy a Telegram post photo through to the (internal-only) MTProto worker.
// Telegram listings carry a relative `/api/tg-photo/<channel>/<id>` photo URL;
// the app loads it from here, and we fetch the bytes from the worker on demand.
// GET /api/tg-photo/:channel/:id
const TG_WORKER_URL = process.env.TG_WORKER_URL || '';
app.get('/api/tg-photo/:channel/:id', async (req, res) => {
  if (!TG_WORKER_URL) return res.status(404).end();
  const { channel, id } = req.params;
  // The channel is a Telegram username and id a message number; validate both so
  // we only ever build a well-formed worker URL from them.
  if (!/^[A-Za-z0-9_]{3,64}$/.test(channel) || !/^\d+$/.test(id)) {
    return res.status(400).end();
  }
  // Serve from the on-disk cache when we already have these bytes: the worker
  // round-trip (backend -> MTProto -> Telegram) is slow enough that social
  // preview crawlers abandon the image fetch.
  const cached = await readPhoto(channel, id);
  if (cached) {
    res.setHeader('Content-Type', cached.contentType);
    res.setHeader('Cache-Control', 'public, max-age=604800, immutable');
    res.setHeader('X-Photo-Cache', 'hit');
    return res.send(cached.buffer);
  }

  try {
    const params = new URLSearchParams({ channel, id });
    const r = await fetch(`${TG_WORKER_URL}/photo?${params}`, {
      signal: AbortSignal.timeout(20_000),
    });
    if (!r.ok) return res.status(r.status === 404 ? 404 : 502).end();
    const buf = Buffer.from(await r.arrayBuffer());
    const contentType = r.headers.get('content-type') || 'image/jpeg';
    res.setHeader('Content-Type', contentType);
    // Photos for a given post never change, so let the app / any CDN cache hard.
    res.setHeader('Cache-Control', 'public, max-age=604800, immutable');
    res.setHeader('X-Photo-Cache', 'miss');
    res.send(buf);
    // Populate the cache after responding so the client never waits on disk.
    void writePhoto(channel, id, buf, contentType);
  } catch (err) {
    res.status(502).end();
  }
});

app.get('/health', async (_req, res) => {
  let postgres = false;
  let elasticsearch = false;
  let elasticsearchStatus = null;

  try {
    await dbHealth();
    postgres = true;
  } catch {}

  try {
    const health =
        await elasticsearchHealth();

    elasticsearch =
        health.ok === true;

    elasticsearchStatus =
        health.status ?? null;
  } catch {}

  /*
   * Пока выдача ещё работает через
   * Redis/Postgres pipeline, ES не делаем
   * причиной падения всего backend.
   */
  const ok =
      postgres;

  res
      .status(
          ok ? 200 : 503,
      )
      .json({
        ok,

        postgres,

        elasticsearch,

        elasticsearchStatus,
      });
});

app.get('/api/db-stats', async (_req, res) => {
  try {
    const rows =
        await getDbStats();

    res.json({
      ok: true,
      rows,
    });
  } catch (err) {
    res.status(500).json({
      ok: false,
      error:
          err?.message ??
          String(err),
    });
  }
});

// Status of the background refresher (last run stats).
app.get('/api/refresh', (_req, res) => res.json({ lastRun: getLastRun() }));

// Trigger an immediate refresh of all countries (handy for testing / on-demand).
app.post('/api/refresh', async (_req, res) => {
  const result = await refreshAll('manual');
  res.json({ ok: true, result });
});

async function start() {
  await initDb();

  /*
   * ES пока является дополнительным
   * search layer.
   *
   * Если он временно недоступен,
   * существующий Flat Finder продолжает
   * работать.
   */
  try {
    await initElasticsearch();
  } catch (err) {
    console.warn(
        '[elasticsearch] startup failed:',
        err?.message ??
        String(err),
    );
  }

  const server =
      app.listen(
          PORT,
          () => {
            console.log(
                `flat-finder backend listening ` +
                `on http://localhost:${PORT}`,
            );

            console.log(
                `countries: ` +
                `${COUNTRY_CODES.join(', ')}`,
            );

            startScheduler();
          },
      );

  async function shutdown(
      signal,
  ) {
    console.log(
        `[server] ${signal}, shutting down`,
    );

    server.close(
        async () => {
          try {
            await Promise.allSettled([
              closeElasticsearch(),
              closeDb(),
            ]);
          } finally {
            process.exit(0);
          }
        },
    );

    setTimeout(
        () =>
            process.exit(1),
        10_000,
    ).unref();
  }

  process.once(
      'SIGTERM',
      () =>
          void shutdown(
              'SIGTERM',
          ),
  );

  process.once(
      'SIGINT',
      () =>
          void shutdown(
              'SIGINT',
          ),
  );
}

start().catch((err) => {
  console.error(
      '[server] startup failed:',
      err,
  );

  process.exit(1);
});