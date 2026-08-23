import { COUNTRIES } from './countries.js';
import { makeListing } from './normalize.js';
import { guessPropertyType } from './textparse.js';
import { fetchChannel } from './scrapers/telegram.js';
import { scrapeCustomUrl } from './scrapers/custom.js';
import { throttle } from './ratelimit.js';
import { upsertListings } from './db.js';
import { indexListings } from './elasticsearch.js';
import { executeQueueTaskOnce } from './queueTaskDedup.js';
import { geocodeListings } from './geocode.js';
import { rejectOutOfAreaCoordinates } from './coordinate-validation.js';
import { reconcileAuthoritativeOlxSegment } from './crawl-reconciliation.js';
import { deactivateMissingCustomSourceListings } from './custom-source-repository.js';

const OLX_FETCHER_URL = String(process.env.OLX_FETCHER_URL || '').replace(/\/$/, '');
const OLX_FETCHER_URLS = [
  String(process.env.OLX_FETCHER_URL_0 || '').replace(/\/$/, ''),
  String(process.env.OLX_FETCHER_URL_1 || '').replace(/\/$/, ''),
];
const OLX_MIN_INTERVAL_MS = Number(process.env.OLX_MIN_INTERVAL_MS) || 900;
const OLX_JITTER_MS = Number(process.env.OLX_JITTER_MS) || 500;
const OLX_QUEUE_MAX_PAGES = Math.max(
  1,
  Number(process.env.OLX_QUEUE_MAX_PAGES) || 1000,
);

function stateParam(item, keyRe, nameRe) {
  for (const param of item.params ?? []) {
    if (
      (param.key && keyRe.test(param.key)) ||
      (param.name && nameRe.test(param.name))
    ) {
      return param.value;
    }
  }
  return null;
}

function stateRooms(item) {
  const raw = stateParam(
    item,
    /room|komnat|kimnat|xonali|kolichestvo/i,
    /комнат|кімнат|room|xonali|спал/i,
  );

  let rooms = raw != null
    ? Number(String(raw).match(/\d+/)?.[0])
    : null;

  if (!rooms) {
    const match = (item.title || '').match(
      /(\d+)\s*[-хx]?\s*(?:camer|комнатн|комн|кімнат|кімн|room|bedroom|xonali|xona)/i,
    );
    rooms = match ? Number(match[1]) : null;
  }

  if (rooms != null && (rooms < 1 || rooms > 10)) {
    return null;
  }

  return rooms || null;
}

function stateArea(item) {
  const raw = stateParam(
    item,
    /area|m2|total_area|ploshch|maydon|kvadrat/i,
    /площад|area|m²|кв\.?\s*м|maydon|майдон/i,
  );

  const value = raw != null
    ? Number(String(raw).replace(',', '.').match(/\d+(?:\.\d+)?/)?.[0])
    : null;

  return value || null;
}

function normalizeCurrency(code) {
  if (!code) return null;
  const normalized = String(code).toUpperCase();
  return ['UYE', 'У.Е.', 'УЕ'].includes(normalized)
    ? 'USD'
    : code;
}

function mapOlxStateItem(item, country, forcedCity = null) {
  const regularPrice = item.price?.regularPrice ?? {};
  const paramText = (item.params ?? [])
    .map((param) => `${param.name ?? ''} ${Array.isArray(param.value) ? param.value.join(' ') : param.value ?? ''}`)
    .join(' ');

  const listing = makeListing({
    id: item.id,
    source: 'olx',
    country: country.code,
    title: item.title,
    description: item.description ?? '',
    propertyType: guessPropertyType(`${item.title || ''} ${paramText}`),
    byAgency: Boolean(item.isBusiness),
    price: regularPrice.value ?? null,
    currency: normalizeCurrency(regularPrice.currencyCode) ?? country.currency,
    rooms: stateRooms(item),
    areaSqm: stateArea(item),
    city: item.location?.cityName ?? item.location?.regionName ?? '',
    district: item.location?.districtName ?? null,
    lat: item.map?.lat ?? null,
    lng: item.map?.lon ?? null,
    photos: Array.isArray(item.photos) ? item.photos.filter(Boolean) : [],
    url: item.url ?? country.olxHost,
    createdAt: item.createdTime ?? null,
  });

  if (forcedCity) {
    listing.city = forcedCity;
  }

  return listing;
}

function olxFetcherUrl(crawlerShard) {
  const shard = Math.max(0, Math.trunc(Number(crawlerShard) || 0));
  return OLX_FETCHER_URLS[shard] || OLX_FETCHER_URL;
}

async function fetchOlxPage({ country, segment, page, citySlug, city, crawlerShard }) {
  const fetcherUrl = olxFetcherUrl(crawlerShard);
  if (!fetcherUrl) {
    throw new Error('OLX_FETCHER_URL is not configured');
  }

  const config = COUNTRIES[country];
  if (!config) {
    throw new Error(`Unknown country ${country}`);
  }

  await throttle(
    `queue:olx:${config.olxHost}:shard:${crawlerShard ?? 0}`,
    OLX_MIN_INTERVAL_MS,
    OLX_JITTER_MS,
  );

  const params = new URLSearchParams({
    country,
    segment,
    page: String(page),
  });

  if (citySlug) {
    params.set('city', citySlug);
  }

  const response = await fetch(
    `${fetcherUrl}/olx/listings?${params}`,
    { signal: AbortSignal.timeout(60_000) },
  );

  if (!response.ok) {
    let detail = `HTTP ${response.status}`;
    try {
      detail = (await response.json())?.error || detail;
    } catch {}
    throw new Error(
      `OLX shard=${crawlerShard ?? 0} ${country}/${segment}/${citySlug || 'all'}/page-${page}: ${detail}`,
    );
  }

  const body = await response.json();
  const ads = Array.isArray(body?.ads) ? body.ads : [];

  return {
    listings: ads
      .filter((item) => item?.id != null)
      .map((item) => mapOlxStateItem(item, config, city || null)),
    rawCount: Number.isFinite(Number(body?.rawCount))
      ? Number(body.rawCount)
      : ads.length,
    pastCutoff: body?.pastCutoff === true,
    lookbackDays: Number(body?.lookbackDays) || null,
    cutoffAt: body?.cutoffAt || null,
    oldestKnownAt: body?.oldestKnownAt || null,
    newestKnownAt: body?.newestKnownAt || null,
    unknownDateCount: Number(body?.unknownDateCount) || 0,
  };
}

function findTelegramChannel(country, name) {
  const config = COUNTRIES[country];
  if (!config) return null;

  for (const value of config.telegramChannels ?? []) {
    const channel = typeof value === 'string'
      ? { name: value, city: null, dealType: null }
      : value;

    if (String(channel?.name || '').toLowerCase() === name.toLowerCase()) {
      return channel;
    }
  }

  return null;
}

async function persist(listings, task) {
  if (!Array.isArray(listings) || !listings.length) {
    return { saved: 0, indexed: 0 };
  }

  const saved = await upsertListings(listings);
  let indexed = 0;

  try {
    indexed = await indexListings(listings);
  } catch (error) {
    console.warn(
      `[queue:${task.type}] Elasticsearch indexing failed: ${error?.message ?? error}`,
    );
  }

  return { saved, indexed };
}

function nextOlxTask(task, pageResult, page) {
  if (
    pageResult.pastCutoff ||
    pageResult.rawCount <= 0 ||
    page >= OLX_QUEUE_MAX_PAGES
  ) {
    return null;
  }

  const nextPage = page + 1;
  return {
    type: 'flat.olx.page',
    country: String(task.country || '').toUpperCase(),
    city: task.city || null,
    citySlug: task.citySlug || null,
    segment: String(task.segment || ''),
    page: nextPage,
    priority: Math.max(1, 7 - nextPage),
    queueProtocol: task.queueProtocol,
    crawlGeneration: task.crawlGeneration,
    crawlerShard: task.crawlerShard,
  };
}

async function processQueueTaskInner(task) {
  const type = String(task?.type || '');
  const country = String(task?.country || '').toUpperCase();

  if (!COUNTRIES[country]) {
    throw new Error(`Unsupported country ${country || '<empty>'}`);
  }

  if (type === 'flat.olx.page') {
    const segment = String(task.segment || '');
    if (!['flat:longRent', 'flat:sale'].includes(segment)) {
      throw new Error(`Unsupported OLX segment ${segment}`);
    }

    const page = Math.max(1, Math.trunc(Number(task.page) || 1));
    const pageResult = await fetchOlxPage({
      country,
      segment,
      page,
      citySlug: task.citySlug ? String(task.citySlug) : null,
      city: task.city ? String(task.city) : null,
      crawlerShard: task.crawlerShard,
    });

    // Source map coordinates are useful when sane, but OLX occasionally emits
    // a point far outside the crawled locality. Only those outliers are cleared
    // and re-geocoded from address/district text, keeping the normal path cheap.
    const rejected = await rejectOutOfAreaCoordinates(
      pageResult.listings,
      COUNTRIES[country],
      { areaHint: task.citySlug ? String(task.citySlug) : null },
    );
    if (rejected.length) {
      await geocodeListings(rejected, COUNTRIES[country]);
    }

    const nextTask = nextOlxTask(task, pageResult, page);
    const persisted = await persist(pageResult.listings, task);

    // The all-country segment is authoritative. Once its sequential page chain
    // reaches a normal terminal page, everything in this generation has either
    // been seen and upserted or is no longer part of the current OLX snapshot.
    // City-specific chains overlap, so they intentionally never reconcile.
    let reconciliation = null;
    if (!nextTask && !task.citySlug && task.crawlGeneration) {
      reconciliation = await reconcileAuthoritativeOlxSegment({
        country,
        segment,
        crawlGeneration: task.crawlGeneration,
      });
    }

    return {
      ok: true,
      type,
      country,
      city: task.city || null,
      segment,
      page,
      crawlerShard: task.crawlerShard,
      crawlGeneration: task.crawlGeneration,
      fetched: pageResult.listings.length,
      rawCount: pageResult.rawCount,
      pastCutoff: pageResult.pastCutoff,
      lookbackDays: pageResult.lookbackDays,
      cutoffAt: pageResult.cutoffAt,
      oldestKnownAt: pageResult.oldestKnownAt,
      newestKnownAt: pageResult.newestKnownAt,
      unknownDateCount: pageResult.unknownDateCount,
      repairedCoordinates: rejected.length,
      nextTasks: nextTask ? [nextTask] : [],
      reconciliation: reconciliation
        ? {
            reconciled: reconciliation.reconciled,
            dealType: reconciliation.dealType || null,
            startedAt: reconciliation.startedAt || null,
            deactivated: reconciliation.deactivated?.length || 0,
            reason: reconciliation.reason || null,
          }
        : null,
      ...persisted,
    };
  }

  if (type === 'flat.telegram.channel') {
    const channelName = String(task.channel || '');
    const channel = findTelegramChannel(country, channelName);
    if (!channel) {
      throw new Error(`Unknown Telegram channel ${country}/@${channelName}`);
    }

    const listings = await fetchChannel(
      channel,
      COUNTRIES[country],
      {},
      Date.now() + 120_000,
    );

    return {
      ok: true,
      type,
      country,
      channel: channelName,
      crawlerShard: task.crawlerShard,
      crawlGeneration: task.crawlGeneration,
      fetched: listings.length,
      nextTasks: [],
      ...(await persist(listings, task)),
    };
  }

  if (type === 'flat.custom.url') {
    const sourceUrl = String(task.url || '').trim();
    if (!sourceUrl) {
      throw new Error('Missing custom source URL');
    }

    const crawlStartedAt = new Date().toISOString();
    const listings = (await scrapeCustomUrl(sourceUrl, COUNTRIES[country])).map((listing) => ({
      ...listing,
      source: 'custom',
      country,
      customSourceUrl: sourceUrl,
    }));
    const persisted = await persist(listings, task);
    const deactivated = await deactivateMissingCustomSourceListings({
      country,
      sourceUrl,
      crawlStartedAt,
    });

    return {
      ok: true,
      type,
      country,
      url: sourceUrl,
      crawlGeneration: task.crawlGeneration,
      fetched: listings.length,
      deactivated,
      nextTasks: [],
      ...persisted,
    };
  }

  throw new Error(`Unsupported queue task type ${type || '<empty>'}`);
}

export async function processQueueTask(task) {
  return executeQueueTaskOnce(
    task,
    () => processQueueTaskInner(task),
  );
}
