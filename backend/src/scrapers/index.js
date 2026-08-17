// Source registry + in-memory TTL cache.
//
// Each country runs several sources in parallel (see COUNTRIES[code].sources).
// Results are merged and de-duplicated. If every source for a country yields
// nothing (all blocked/empty), we fall back to generated demo data so the
// client never sees an empty screen for that country.

import {createHash} from 'node:crypto';
import {COUNTRIES} from '../countries.js';
import {scrapeOlx} from './olx.js';
import {scrapeTelegram} from './telegram.js';
import {scrapeCustom} from './custom.js';
import {generateMock} from '../mock.js';
import {cacheGet, cacheSet} from '../cache.js';
import {geocodeListings} from '../geocode.js';
import {aiFingerprint, aiWorkerEnabled, scheduleAiExtraction,} from '../ai-worker.js';
import {markMissingAfterCompleteCrawl, upsertListings,} from '../db.js';
import {
  deleteListingDocuments,
  indexListings,
} from '../elasticsearch.js';

const SOURCES = {
  olx: scrapeOlx,
  telegram: scrapeTelegram,
};

// How long a cached entry is considered "fresh" (served without a re-scrape).
const CACHE_TTL_MS = 5 * 60 * 1000;
// How long a stale entry is still kept and served (while a refresh runs in the
// background). This is the Redis retention window for each key.
const STALE_TTL_MS = 60 * 60 * 1000;
// While a scrape is in progress, partial snapshots are written to the cache no
// more often than this so the UI count/results climb as chunks arrive without
// hammering Redis. The final complete snapshot is always written.
const PARTIAL_WRITE_MS = Number(process.env.PARTIAL_WRITE_MS) || 1200;
// De-dupe concurrent background refreshes of the same key.
const inFlight = new Map(); // key -> Promise

// Hard backstop so a single misbehaving source can never stall the whole
// country response past the proxy timeout. Sources have their own (tighter)
// internal budgets; this only fires in pathological cases and yields whatever
// the source returned before the deadline (empty on timeout).
// Must sit above telegram's own budget (TG_BUDGET_MS ~12s) plus one in-flight
// page fetch (~8s), so telegram returns its partial set on the budget rather
// than being killed here and discarded entirely (which showed as demo data).
const SOURCE_DEADLINE_MS = Number(process.env.SOURCE_DEADLINE_MS) || 24000;

function withDeadline(promise, ms, onTimeout) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => resolve(onTimeout), ms);
    promise.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      },
    );
  });
}

function cacheKey(countryCode, filters) {
  return [
    // Bump this when the snapshot shape/semantics change so Redis cannot serve
    // an older cache whose rows were already narrowed by a UI filter.
    // v8 reparses rows with the ambiguity-aware Tashkent area/district model.
    'full-feed-v8',
    countryCode,
    // UI filters are deliberately absent. Like the vacancy store, this cache
    // is one complete country snapshot; /api/listings filters and paginates it
    // in memory. Changing a select must never launch a new scrape or mutate the
    // meaning of rows stored under a different filter combination.
    'all-sources',
    (filters.customSources ?? []).join('+') || '',
  ].join('|');
}

// Scrapers populate the shared snapshot and therefore must never receive the
// user's current search filters. Those filters are applied only after the
// cached snapshots have been merged in server.js. Keeping custom source URLs is
// intentional: they define the contents of a snapshot rather than a view of it.
function snapshotFilters(filters) {
  return {
    ...filters,
    propertyType: 'any',
    dealType: 'any',
    agency: 'any',
    priceMin: null,
    priceMax: null,
    priceTolerance: null,
    roomsMin: null,
    roomsMax: null,
    bedroomsMin: null,
    bedroomsMax: null,
    floorMin: null,
    floorMax: null,
    yearMin: null,
    yearMax: null,
    audience: 'any',
    city: '',
    cityAliases: [],
    district: '',
    metro: '',
    query: '',
    pets: null,
    children: null,
    roomOnly: null,
    maxAgeDays: null,
    sources: [],
    offset: 0,
    limit: 50,
  };
}

// Content fingerprint: identical reposts (same text/photo across channels or a
// channel reposting itself) get different message ids, so id-dedup alone misses
// them. Hash the normalized title+description; for near-empty text fall back to
// the structured key so we don't collapse distinct short posts (spec §27).
function contentFingerprint(l) {
  const text = `${l.title || ''} ${l.description || ''}`
    .toLowerCase()
    .replace(/https?:\/\/\S+/g, '')
    .replace(/[^a-zа-яёіїґ0-9]+/g, '')
    .slice(0, 600);
  if (text.length >= 40) return `t:${createHash('sha1').update(text).digest('hex')}`;
  return `k:${[l.price, l.currency, l.rooms, l.areaSqm, l.district, l.city].join('|').toLowerCase()}`;
}

function dedupe(listings) {
  const seenId = new Set();
  const seenContent = new Set();
  const out = [];

  for (const listing of listings) {
    const id = [
      listing.source,
      listing.country ?? '',
      listing.id,
    ].join(':');

    // Для всех источников ID всегда первичен.
    if (seenId.has(id)) {
      continue;
    }

    const fingerprint =
        contentFingerprint(listing);

    /*
     * OLX:
     *
     * разные OLX id = разные объявления.
     *
     * Content fingerprint НЕ должен удалять
     * второе OLX объявление.
     *
     * Но сам fingerprint сохраняем в
     * seenContent, чтобы Telegram-репост
     * того же объявления всё ещё можно
     * было удалить.
     */
    if (
        listing.source !== 'olx' &&
        seenContent.has(fingerprint)
    ) {
      continue;
    }

    seenId.add(id);
    seenContent.add(fingerprint);

    out.push(listing);
  }

  return out;
}

function listingKey(listing) {
  return `${listing.source}:${listing.id}`;
}

function apartmentAiInput(listing) {
  const rawText = `${listing.title || ''}\n${listing.description || ''}`.trim();
  const dealMap = { longRent: 'rent', shortRent: 'daily_rent', sale: 'sale' };
  const knownFacts = {
    dealType: dealMap[listing.dealType] ?? null,
    propertyType: listing.propertyType === 'house' ? 'house' : 'apartment',
    rooms: listing.rooms ?? null,
    bedrooms: listing.bedrooms ?? null,
    areaM2: listing.areaSqm ?? null,
    floor: listing.floor ?? null,
    floorsTotal: listing.totalFloors ?? null,
    district: listing.district ?? null,
    kvartal: listing.area ?? listing.kvartal ?? null,
    newBuilding: listing.newBuilding ?? null,
    balcony: listing.balcony ?? null,
    airConditioner: listing.airConditioner ?? null,
    gas: listing.gas ?? null,
    bathrooms: listing.bathrooms ?? null,
    furnished: listing.furnished ?? null,
    petsAllowed: listing.petsAllowed ?? null,
    childrenAllowed: listing.childrenAllowed ?? null,
    communalSeparated: listing.communalSeparated ?? null,
    depositRequired: listing.deposit ?? null,
    depositAmount: listing.depositAmount ?? null,
    commissionRequired: listing.commission ?? null,
    commissionPercent: listing.commissionPercent ?? null,
    priceAmount: listing.price ?? null,
    priceCurrency: listing.currency ?? null,
    negotiable: listing.negotiable ?? null,
    parking: listing.parking ?? null,
    elevator: listing.elevator ?? null,
    heating: listing.heating ?? null,
    hotWater: listing.hotWater ?? null,
    internet: listing.internet ?? null,
    smokingAllowed: listing.smokingAllowed ?? null,
  };
  return {
    rawText,
    knownFacts,
    fingerprint: aiFingerprint('apartment', rawText, knownFacts),
  };
}

function mergeApartmentAi(listing, data) {
  const merged = { ...listing };
  const fill = (field, value) => {
    if ((merged[field] == null || merged[field] === '') && value != null) merged[field] = value;
  };
  fill('rooms', data.rooms);
  fill('bedrooms', data.bedrooms);
  fill('areaSqm', data.areaM2);
  fill('floor', data.floor);
  fill('totalFloors', data.floorsTotal);
  fill('district', data.district);
  fill('kvartal', data.kvartal);
  if (!merged.area && merged.kvartal) merged.area = merged.kvartal;
  fill('newBuilding', data.newBuilding);
  fill('balcony', data.balcony);
  fill('airConditioner', data.airConditioner);
  fill('gas', data.gas);
  fill('bathrooms', data.bathrooms);
  fill('furnished', data.furnished);
  fill('petsAllowed', data.petsAllowed);
  fill('childrenAllowed', data.childrenAllowed);
  fill('communalSeparated', data.communalSeparated);
  fill('deposit', data.depositRequired);
  fill('depositAmount', data.depositAmount);
  fill('commission', data.commissionRequired);
  fill('commissionPercent', data.commissionPercent);
  fill('negotiable', data.negotiable);
  fill('parking', data.parking);
  fill('elevator', data.elevator);
  fill('heating', data.heating);
  fill('hotWater', data.hotWater);
  fill('internet', data.internet);
  fill('smokingAllowed', data.smokingAllowed);
  fill('utilitiesAmount', data.utilitiesAmount);
  fill('minLeaseTerm', data.minLeaseTerm);
  fill('availableFrom', data.availableFrom);
  fill('price', data.priceAmount);
  if (!merged.currency && data.priceCurrency) merged.currency = data.priceCurrency;
  fill('condition', data.condition);

  if (!merged.dealType && data.dealType) {
    merged.dealType = { rent: 'longRent', daily_rent: 'shortRent', sale: 'sale' }[data.dealType] ?? null;
  }
  if (data.propertyType === 'house' && !merged.propertyType) merged.propertyType = 'house';
  if (data.propertyType === 'room') merged.roomOnly = true;
  if (data.propertyType === 'commercial') merged.commercial = true;
  merged.amenities = [...new Set([...(merged.amenities || []), ...(data.amenities || [])])];
  return merged;
}

function apartmentNeedsAi(listing) {
  if ((listing.description || '').length < 80 || String(listing.source).startsWith('mock')) return false;
  let score = 0;
  if (listing.rooms == null) score += 2;
  if (listing.areaSqm == null) score += 2;
  if (listing.floor == null || listing.totalFloors == null) score += 1;
  if (!listing.district) score += 1;
  if (listing.deposit == null && listing.commission == null) score += 1;
  if (listing.balcony == null && listing.airConditioner == null && listing.gas == null) score += 1;
  return score >= 3;
}

async function applyApartmentAiResult(cacheKeyValue, id, fingerprint, result) {
  const entry = await cacheGet(cacheKeyValue);
  if (!entry?.complete) return;
  const index = entry.listings.findIndex((listing) => listingKey(listing) === id);
  if (index < 0) return;
  const current = entry.listings[index];
  if (apartmentAiInput(current).fingerprint !== fingerprint) return;
  const accepted = !result.lowConfidence && result.confidence >= 0.6;
  if (accepted) entry.listings[index] = mergeApartmentAi(current, result.data);
  entry.ai = entry.ai || {};
  entry.ai[id] = {
    fingerprint,
    status: accepted ? 'completed' : 'low_confidence',
    confidence: result.confidence,
    data: accepted ? result.data : undefined,
    updatedAt: new Date().toISOString(),
  };
  await cacheSet(cacheKeyValue, entry, STALE_TTL_MS);
}

function scheduleApartmentAi(cacheKeyValue, entry) {
  if (!aiWorkerEnabled()) return 0;
  // Per country refresh. Five keeps the initial five-country rollout bounded;
  // terminal records are skipped so later refreshes naturally advance.
  const batchSize = Math.max(1, Number(process.env.AI_WORKER_APARTMENT_BATCH) || 5);
  entry.ai = entry.ai || {};
  let count = 0;
  for (const listing of entry.listings) {
    if (count >= batchSize) break;
    if (!apartmentNeedsAi(listing)) continue;
    const id = listingKey(listing);
    const input = apartmentAiInput(listing);
    const prior = entry.ai[id];
    // `entry.ai` only contains metadata whose fingerprint matched the fresh
    // deterministic listing above. Completed results may already have filled
    // fields and therefore intentionally change a newly computed fingerprint.
    if (prior && prior.status !== 'pending') continue;
    const queued = scheduleAiExtraction({
      id,
      kind: 'apartment',
      ...input,
      meta: { source: listing.source, country: listing.country, id: listing.id },
      onResult: (result) => applyApartmentAiResult(cacheKeyValue, id, input.fingerprint, result),
      onFailed: async (status) => {
        if (status !== 'failed') return;
        const current = await cacheGet(cacheKeyValue);
        if (!current?.complete) return;
        current.ai = current.ai || {};
        current.ai[id] = {
          fingerprint: input.fingerprint,
          status: 'failed',
          updatedAt: new Date().toISOString(),
        };
        await cacheSet(cacheKeyValue, current, STALE_TTL_MS);
      },
    });
    if (queued) {
      entry.ai[id] = { fingerprint: input.fingerprint, status: 'pending', updatedAt: new Date().toISOString() };
      count += 1;
    }
  }
  if (count) console.log(`[flats:ai] queued ${count} ambiguous listings for ${cacheKeyValue}`);
  return count;
}

async function persistListings(
    listings,
    {
      source,
      country,
      phase = 'unknown',
    } = {},
) {
  if (
      !Array.isArray(listings) ||
      !listings.length
  ) {
    return {
      postgres: 0,
      elasticsearch: 0,
    };
  }

  /*
   * Сначала Postgres.
   *
   * Если он не сохранил данные,
   * Elasticsearch обновлять нельзя:
   * Postgres — source of truth.
   */
  const saved =
      await upsertListings(
          listings,
      );

  let indexed = 0;

  /*
   * Elasticsearch — производный индекс.
   *
   * Его ошибка не должна ломать
   * scraper / Postgres ingestion.
   */
  try {
    indexed =
        await indexListings(
            listings,
        );
  } catch (err) {
    console.warn(
        `[elasticsearch] ` +
        `${country}/${source} ` +
        `${phase} indexing failed: ` +
        `${err?.message ?? err}`,
    );
  }

  return {
    postgres:
    saved,

    elasticsearch:
    indexed,
  };
}

async function syncDeactivatedListings(
    listings,
    {
      source,
      country,
    } = {},
) {
  if (
      !Array.isArray(listings) ||
      !listings.length
  ) {
    return 0;
  }

  try {
    const deleted =
        await deleteListingDocuments(
            listings,
        );

    if (deleted) {
      console.log(
          `[elasticsearch] ` +
          `${country}/${source}: ` +
          `${deleted} inactive documents removed`,
      );
    }

    return deleted;
  } catch (err) {
    /*
     * Не откатываем Postgres.
     *
     * Если ES временно упал,
     * следующий reindex всё восстановит
     * из source of truth.
     */
    console.warn(
        `[elasticsearch] ` +
        `${country}/${source} ` +
        `deactivation sync failed: ` +
        `${err?.message ?? err}`,
    );

    return 0;
  }
}

// `onProgress({ listings, sourceCounts, sourceErrors })` (optional) is called as
// chunks/sources arrive so the caller can stream partial snapshots into the cache.
async function fetchOne(
    countryCode,
    filters,
    onProgress,
) {
  const country =
      COUNTRIES[countryCode];

  if (!country) {
    return {
      listings: [],
      degraded: false,
      sourceCounts: {},
      sourceErrors: [],
      sourceStatus: {},
    };
  }

  const sources =
      country.sources ?? ['olx'];

  const sourceCounts = {};
  const sourceErrors = {};
  const sourceStatus = {};

  let merged = [];

  // sourceErrors дальше нужен как массив.
  const errors = [];

  const emit = () => {
    if (!onProgress) {
      return;
    }

    onProgress({
      listings: merged,

      sourceCounts: {
        ...sourceCounts,
      },

      sourceErrors: [
        ...errors,
      ],

      sourceStatus: {
        ...sourceStatus,
      },
    });
  };

  const tasks =
      sources.map((name) => {
        const fn =
            SOURCES[name];

        if (!fn) {
          sourceCounts[name] = 0;

          return Promise.resolve();
        }

        sourceCounts[name] = 0;

        /*
         * Время ДО первого запроса.
         *
         * После полного crawl всё,
         * у чего last_seen_at старше этого
         * времени, считается пропущенным.
         */
        const crawlStartedAt =
            new Date()
                .toISOString();

        /*
         * PostgreSQL-записи одного source
         * выполняем последовательно,
         * чтобы page chunks не гонялись
         * друг с другом.
         */
        let dbWriting =
            Promise.resolve();

        let persistenceQueue =
            Promise.resolve();

        const queuePersistence =
            (listings) => {
              if (
                  !Array.isArray(listings) ||
                  !listings.length
              ) {
                return;
              }

              /*
               * Чанки одного source пишем
               * последовательно.
               *
               * Это сохраняет порядок:
               *
               * Postgres
               *   ↓
               * Elasticsearch
               */
              persistenceQueue =
                  persistenceQueue
                      .then(
                          () =>
                              persistListings(
                                  listings,
                                  {
                                    source:
                                    name,

                                    country:
                                    countryCode,

                                    phase:
                                        'chunk',
                                  },
                              ),
                      )
                      .catch(
                          (err) => {
                            /*
                             * Сюда попадёт в основном
                             * ошибка Postgres.
                             *
                             * ES errors уже обработаны
                             * внутри persistListings().
                             */
                            console.warn(
                                `[postgres] ` +
                                `${countryCode}/${name} ` +
                                `chunk persistence failed: ` +
                                `${err?.message ?? err}`,
                            );
                          },
                      );
            };

        const onChunk =
            (chunk) => {
              if (!chunk?.length) {
                return;
              }

              sourceCounts[name] +=
                  chunk.length;

              merged =
                  dedupe(
                      merged.concat(
                          chunk,
                      ),
                  );

              // OLX сохраняется в PostgreSQL
              // прямо постранично.
              queuePersistence(
                  chunk,
              );

              emit();
            };

        const timeoutResult = {
          listings: [],
          complete: false,

          errors: [
            {
              error:
                  `Source deadline exceeded ` +
                  `after ${SOURCE_DEADLINE_MS}ms`,
            },
          ],
        };

        const sourcePromise =
            fn(
                country,
                filters,
                onChunk,
            );

        const guardedPromise =
            name === 'olx'
                ? sourcePromise
                : withDeadline(
                    sourcePromise,
                    SOURCE_DEADLINE_MS,
                    timeoutResult,
                );

        return guardedPromise.then(
            async (result) => {
              const isLegacyArray =
                  Array.isArray(
                      result,
                  );

              const listings =
                  isLegacyArray
                      ? result
                      : Array.isArray(
                          result?.listings,
                      )
                          ? result.listings
                          : [];

              const complete =
                  isLegacyArray
                      ? true
                      : result?.complete !==
                      false;

              sourceStatus[name] = {
                complete,
              };

              merged =
                  dedupe(
                      merged.concat(
                          listings,
                      ),
                  );

              sourceCounts[name] =
                  Math.max(
                      sourceCounts[name] ??
                      0,

                      listings.length,
                  );

              /*
               * Ждём все page writes.
               */
              await dbWriting;

              /*
               * Telegram не стримит OLX-style
               * chunks, поэтому сохраняем
               * authoritative final result
               * ещё раз.
               *
               * Для OLX повторный upsert
               * безопасен и просто обновит
               * last_seen_at/data.
               */
              /*
 * Сначала ждём все page/chunk writes.
 */
              await persistenceQueue;

              try {
                /*
                 * Финальный authoritative result.
                 *
                 * Повторный upsert/index безопасен:
                 * document id в обеих БД стабилен.
                 */
                await persistListings(
                    listings,
                    {
                      source:
                      name,

                      country:
                      countryCode,

                      phase:
                          'final',
                    },
                );

                /*
                 * Missing/deactivation считаем
                 * ТОЛЬКО после полного crawl.
                 */
                if (complete) {
                  const missingResult =
                      await markMissingAfterCompleteCrawl({
                        source:
                        name,

                        country:
                        countryCode,

                        crawlStartedAt,
                      });

                  /*
                   * После третьего miss Postgres
                   * переводит listing в active=false.
                   *
                   * Такие документы сразу убираем
                   * из Elasticsearch.
                   */
                  await syncDeactivatedListings(
                      missingResult
                          ?.deactivated ??
                      [],
                      {
                        source:
                        name,

                        country:
                        countryCode,
                      },
                  );
                }
              } catch (err) {
                console.warn(
                    `[postgres] ` +
                    `${countryCode}/${name} ` +
                    `final persistence failed: ` +
                    `${err?.message ?? err}`,
                );
              }

              if (!complete) {
                const resultErrors =
                    Array.isArray(
                        result?.errors,
                    ) &&
                    result.errors.length
                        ? result.errors
                        : [
                          {
                            error:
                                'Incomplete scrape',
                          },
                        ];

                for (
                    const item
                    of resultErrors
                    ) {
                  errors.push({
                    source: name,
                    country:
                    countryCode,
                    page:
                    item.page,
                    segment:
                    item.segment,
                    stopReason:
                    item.stopReason,
                    error:
                        item.error ??
                        'Incomplete scrape',
                  });
                }
              }

              emit();
            },

            async (err) => {
              const msg =
                  err?.message ??
                  String(err);

              sourceStatus[name] = {
                complete: false,
              };

              errors.push({
                source: name,
                country:
                countryCode,
                error: msg,
              });

              console.warn(
                  `[scraper] ` +
                  `${countryCode}/${name} ` +
                  `failed: ${msg}`,
              );

              await dbWriting;

              /*
               * Здесь markMissing НЕ вызываем:
               * source завершился ошибкой.
               */

              emit();
            },
        );
      });

  await Promise.allSettled(
      tasks,
  );

  if (
      Array.isArray(
          filters.customSources,
      ) &&
      filters.customSources.length
  ) {
    const custom =
        await scrapeCustom(
            country,
            filters,
        );

    sourceCounts.custom =
        custom.listings.length;

    merged =
        dedupe(
            merged.concat(
                custom.listings,
            ),
        );

    for (
        const error
        of custom.errors
        ) {
      errors.push({
        source: 'custom',
        country:
        countryCode,
        url:
        error.url,
        error:
        error.error,
      });
    }

    emit();
  }

  if (!merged.length) {
    console.warn(
        `[scraper] ${countryCode} ` +
        `all sources empty -> mock`,
    );

    return {
      listings:
          generateMock(
              countryCode,
          ),

      degraded: true,
      sourceCounts,
      sourceErrors:
      errors,
      sourceStatus,
    };
  }

  return {
    listings: merged,
    degraded: false,
    sourceCounts,
    sourceErrors:
    errors,
    sourceStatus,
  };
}

// Scrape a country fresh and store the result in the (Redis or in-memory) cache.
// Concurrent callers for the same key share a single in-flight scrape.
function refresh(countryCode, filters, key) {
  if (inFlight.has(key)) {
    return inFlight.get(key);
  }

  const p = (async () => {
    const previousEntry =
        await cacheGet(key);

    const previousAi =
        previousEntry?.ai || {};

    const previousListings =
        Array.isArray(previousEntry?.listings)
            ? previousEntry.listings
            : [];

    let lastWrite = 0;
    let writing = Promise.resolve();
    let acceptProgress = true;

    function mergeProgressListings(
        previous,
        fresh,
    ) {
      const byId = new Map();

      // Сначала старый snapshot.
      for (const listing of previous) {
        if (!listing?.id) {
          continue;
        }

        const id = [
          listing.source ?? '',
          listing.country ?? '',
          listing.id,
        ].join(':');

        byId.set(
            id,
            listing,
        );
      }

      // Свежие объявления заменяют
      // старые объявления с тем же ID.
      for (const listing of fresh) {
        if (!listing?.id) {
          continue;
        }

        const id = [
          listing.source ?? '',
          listing.country ?? '',
          listing.id,
        ].join(':');

        byId.set(
            id,
            listing,
        );
      }

      return dedupe([
        ...byId.values(),
      ]);
    }

    function countSources(listings) {
      const counts = {};

      for (const listing of listings) {
        const source =
            String(
                listing?.source || '',
            ).toLowerCase();

        if (!source) {
          continue;
        }

        counts[source] =
            (counts[source] ?? 0) + 1;
      }

      return counts;
    }

    const onProgress = (partial) => {
      if (!acceptProgress) {
        return;
      }

      const now = Date.now();

      if (
          now - lastWrite <
          PARTIAL_WRITE_MS
      ) {
        return;
      }

      lastWrite = now;

      const partialListings =
          Array.isArray(partial?.listings)
              ? partial.listings
              : [];

      const mergedListings =
          mergeProgressListings(
              previousListings,
              partialListings,
          );

      const sourceCounts =
          countSources(
              mergedListings,
          );

      const progressiveEntry = {
        at: Date.now(),

        listings:
        mergedListings,

        sourceCounts,

        sourceErrors:
            Array.isArray(
                partial?.sourceErrors,
            )
                ? partial.sourceErrors
                : [],

        sourceStatus:
            partial?.sourceStatus ?? {},

        degraded:
            Boolean(
                previousEntry?.degraded ||
                partial?.degraded,
            ),

        // Весь refresh ещё не завершён.
        complete: false,
      };

      writing = writing
          .then(() =>
              cacheSet(
                  key,
                  progressiveEntry,
                  STALE_TTL_MS,
              ),
          )
          .catch((err) => {
            console.warn(
                `[scraper] progressive cache ` +
                `${countryCode} failed: ` +
                `${err?.message ?? err}`,
            );
          });
    };

    const result =
        await fetchOne(
            countryCode,
            snapshotFilters(filters),
            onProgress,
        );

    // После fetchOne больше никакие поздние
    // chunks не должны затереть final snapshot.
    acceptProgress = false;

    // Дожидаемся последней уже поставленной
    // progressive-записи.
    await writing;

    const olxIncomplete =
        result.sourceStatus
            ?.olx
            ?.complete === false;

    /*
     * Если OLX завершился частично,
     * сохраняем объявления из предыдущего
     * стабильного snapshot.
     */
    if (
        olxIncomplete &&
        previousEntry?.complete === true &&
        Array.isArray(
            previousEntry.listings,
        )
    ) {
      const previousOlx =
          previousEntry.listings.filter(
              (listing) =>
                  listing.source === 'olx',
          );

      const freshOlx =
          result.listings.filter(
              (listing) =>
                  listing.source === 'olx',
          );

      const nonOlx =
          result.listings.filter(
              (listing) =>
                  listing.source !== 'olx',
          );

      const olxById =
          new Map();

      for (
          const listing
          of previousOlx
          ) {
        olxById.set(
            `${listing.country}:${listing.id}`,
            listing,
        );
      }

      // Новый OLX имеет приоритет.
      for (
          const listing
          of freshOlx
          ) {
        olxById.set(
            `${listing.country}:${listing.id}`,
            listing,
        );
      }

      const preservedOlx = [
        ...olxById.values(),
      ];

      result.listings = [
        ...nonOlx,
        ...preservedOlx,
      ];

      result.sourceCounts = {
        ...result.sourceCounts,
        olx: preservedOlx.length,
      };

      result.degraded = true;

      console.warn(
          `[scraper] ${countryCode}/olx incomplete; ` +
          `preserving previous OLX snapshot ` +
          `(fresh=${freshOlx.length}, ` +
          `previous=${previousOlx.length}, ` +
          `merged=${preservedOlx.length})`,
      );
    }

    /*
     * Геокодирование делаем только один раз
     * после завершения source crawling.
     */
    try {
      await geocodeListings(
          result.listings,
          COUNTRIES[countryCode],
      );
    } catch (err) {
      console.warn(
          `[geocode] ${countryCode} failed: ` +
          `${err?.message ?? err}`,
      );
    }

    /*
     * Восстанавливаем уже готовые AI results,
     * если исходные данные объявления
     * не изменились.
     */
    const ai = {};

    result.listings =
        result.listings.map(
            (listing) => {
              const id =
                  listingKey(listing);

              const input =
                  apartmentAiInput(
                      listing,
                  );

              const prior =
                  previousAi[id];

              if (
                  prior?.fingerprint !==
                  input.fingerprint
              ) {
                return listing;
              }

              ai[id] = prior;

              if (
                  prior.status ===
                  'completed' &&
                  prior.data
              ) {
                return mergeApartmentAi(
                    listing,
                    prior.data,
                );
              }

              return listing;
            },
        );

    /*
     * Final snapshot.
     *
     * complete:true означает:
     * refresh закончился.
     *
     * Состояние отдельных sources находится
     * в sourceStatus.
     */
    const entry = {
      at: Date.now(),
      ...result,
      ai,
      complete: true,
    };

    await cacheSet(
        key,
        entry,
        STALE_TTL_MS,
    );

    if (
        scheduleApartmentAi(
            key,
            entry,
        )
    ) {
      await cacheSet(
          key,
          entry,
          STALE_TTL_MS,
      );
    }

    return entry;
  })()
      .finally(() => {
        inFlight.delete(key);
      });

  inFlight.set(
      key,
      p,
  );

  return p;
}

// Stale-while-revalidate:
//   fresh cache hit  -> return immediately
//   stale cache hit  -> return the stale copy now, refresh in the background
//   miss             -> scrape synchronously
// This means a user request never blocks on a slow telegram scrape once the
// key has been warmed at least once, which is what caused the 504s / few results.
export async function getListings(countryCode, filters, { force = false } = {}) {
  const key = cacheKey(countryCode, filters);
  if (force) return refresh(countryCode, filters, key);

  const hit = await cacheGet(key);
  if (hit) {
    // An in-progress (partial) snapshot: serve what we have and keep the client
    // polling so the count/results climb as more chunks land. If no refresh is
    // actually running (e.g. the process restarted mid-scrape), resume one.
    if (hit.complete === false) {
      if (!inFlight.has(key)) {
        refresh(countryCode, filters, key).catch((e) =>
          console.warn(`[scraper] resume refresh ${countryCode} failed: ${e.message}`),
        );
      }
      return { ...hit, warming: true };
    }
    const age = Date.now() - hit.at;
    if (age < CACHE_TTL_MS) return { ...hit, warming: false }; // fresh
    // Stale: kick off a background refresh but serve the cached copy now.
    refresh(countryCode, filters, key).catch((e) =>
      console.warn(`[scraper] background refresh ${countryCode} failed: ${e.message}`),
    );
    return { ...hit, warming: true };
  }
  // Mirror the vacancy store: a cold request starts population in the
  // background and returns immediately. The web client polls while `warming`
  // is true, so nginx never waits for a 20+ second OLX/Telegram scrape.
  refresh(countryCode, filters, key).catch((e) =>
    console.warn(`[scraper] initial refresh ${countryCode} failed: ${e.message}`),
  );
  return {
    at: Date.now(),
    listings: [],
    degraded: false,
    sourceCounts: {},
    sourceErrors: [],
    warming: true,
  };
}

// Default "browse" filters — the query the app sends when no filters are set.
// The hourly warmer refreshes this key so the common view is always instant.
export const BASE_FILTERS = {
  propertyType: 'any',
  dealType: 'any',
  agency: 'any',
  priceMin: null,
  priceMax: null,
  query: '',
  sources: [],
  offset: 0,
  limit: 50,
};

// Force-refresh the default browse cache for one country (bypasses the TTL).
export async function warmCountry(countryCode) {
  return getListings(countryCode, BASE_FILTERS, { force: true });
}
