import { COUNTRIES } from './countries.js';
import { markMissingAfterCompleteCrawl, upsertListings } from './db.js';
import { deleteListingDocuments, indexListings } from './elasticsearch.js';
import { scrapeFacebook, scrapeThreads } from './scrapers/social.js';
import { buildThreadsHousingCoverage, rotatingCoverage } from './social-search-coverage.js';

const SOCIAL_REFRESH_MINUTES = Math.max(10, Number(process.env.SOCIAL_HOUSING_REFRESH_MINUTES) || 30);
const SOCIAL_REFRESH_MS = SOCIAL_REFRESH_MINUTES * 60 * 1000;
const START_DELAY_MS = Math.max(5_000, Number(process.env.SOCIAL_HOUSING_START_DELAY_MS) || 20_000);
const THREADS_QUERIES_PER_CYCLE = Math.max(
  4,
  Math.min(30, Number(process.env.SOCIAL_HOUSING_THREADS_QUERIES_PER_CYCLE) || 12),
);

let timer = null;
let running = false;

const FACEBOOK_TARGETS = {
  UZ: [
    { target: 'https://www.facebook.com/groups/antimakler/', city: 'Tashkent' },
    { target: 'https://www.facebook.com/groups/741615396187925/', city: 'Tashkent' },
    { target: 'https://www.facebook.com/groups/281140502050492/', city: 'Tashkent' },
  ],
};

function countryConfig(code, { facebookHousingTargets = [], threadsHousingQueries = [] } = {}) {
  return {
    ...(COUNTRIES[code] || {}),
    code,
    facebookHousingTargets,
    threadsHousingQueries,
  };
}

function selectedThreadsByCountry() {
  const all = buildThreadsHousingCoverage();
  const selected = rotatingCoverage(all, {
    maxPerCycle: THREADS_QUERIES_PER_CYCLE,
    slotMinutes: SOCIAL_REFRESH_MINUTES,
  });
  const grouped = new Map();
  for (const target of selected) {
    const list = grouped.get(target.country) || [];
    list.push(target);
    grouped.set(target.country, list);
  }
  return { all, selected, grouped };
}

async function persist(source, countryCode, result, crawlStartedAt, allowMissingSweep) {
  const listings = Array.isArray(result?.listings) ? result.listings : [];
  let saved = 0;

  if (listings.length) {
    saved = await upsertListings(listings);
    try {
      await indexListings(listings);
    } catch (error) {
      console.warn(`[social-housing] ${source}/${countryCode} Elasticsearch failed: ${error?.message || error}`);
    }
  }

  if (allowMissingSweep && result?.complete === true) {
    try {
      const missing = await markMissingAfterCompleteCrawl({
        source,
        country: countryCode,
        crawlStartedAt,
      });
      if (missing.deactivated?.length) {
        await deleteListingDocuments(missing.deactivated).catch((error) => {
          console.warn(
            `[social-housing] ${source}/${countryCode} deactivation index sync failed: ${error?.message || error}`,
          );
        });
      }
    } catch (error) {
      console.warn(`[social-housing] ${source}/${countryCode} missing-row sweep failed: ${error?.message || error}`);
    }
  } else if (result?.complete !== true) {
    console.warn(
      `[social-housing] ${source}/${countryCode} crawl partial; keeping unseen rows active ` +
      `(errors=${Array.isArray(result?.errors) ? result.errors.length : 0})`,
    );
  }

  return saved;
}

async function refreshFacebook() {
  let total = 0;
  for (const [countryCode, targets] of Object.entries(FACEBOOK_TARGETS)) {
    const startedAt = new Date().toISOString();
    try {
      const result = await scrapeFacebook(countryConfig(countryCode, { facebookHousingTargets: targets }));
      total += await persist('facebook', countryCode, result, startedAt, true);
    } catch (error) {
      console.warn(`[social-housing] Facebook/${countryCode} failed: ${error?.message || error}`);
    }
  }
  return total;
}

async function refreshThreads() {
  const coverage = selectedThreadsByCountry();
  let total = 0;

  for (const [countryCode, targets] of coverage.grouped.entries()) {
    const startedAt = new Date().toISOString();
    try {
      const result = await scrapeThreads(countryConfig(countryCode, { threadsHousingQueries: targets }));
      // Coverage is intentionally rotated: a successful batch is not a complete
      // country crawl, so it must never deactivate listings from other batches.
      total += await persist('threads', countryCode, result, startedAt, false);
    } catch (error) {
      console.warn(`[social-housing] Threads/${countryCode} failed: ${error?.message || error}`);
    }
  }

  console.log(
    `[social-housing] Threads coverage: ${coverage.selected.length}/${coverage.all.length} queries this cycle`,
  );
  return total;
}

export async function refreshSocialHousing(reason = 'scheduled') {
  if (running) return null;
  if (process.env.SOCIAL_HOUSING_SOURCE === 'off') return null;
  running = true;

  try {
    const [facebook, threads] = await Promise.allSettled([
      refreshFacebook(),
      refreshThreads(),
    ]);

    const counts = {
      facebook: facebook.status === 'fulfilled' ? facebook.value : 0,
      threads: threads.status === 'fulfilled' ? threads.value : 0,
    };

    if (facebook.status === 'rejected') {
      console.warn(`[social-housing] Facebook failed: ${facebook.reason?.message || facebook.reason}`);
    }
    if (threads.status === 'rejected') {
      console.warn(`[social-housing] Threads failed: ${threads.reason?.message || threads.reason}`);
    }

    console.log(`[social-housing] ${reason}: facebook=${counts.facebook}, threads=${counts.threads}`);
    return counts;
  } finally {
    running = false;
  }
}

export function startSocialHousingScheduler() {
  if (process.env.SOCIAL_HOUSING_SOURCE === 'off') {
    console.log('[social-housing] disabled via SOCIAL_HOUSING_SOURCE=off');
    return;
  }

  const first = setTimeout(
    () => refreshSocialHousing('startup').catch((error) =>
      console.warn(`[social-housing] startup failed: ${error?.message || error}`),
    ),
    START_DELAY_MS,
  );
  first.unref?.();

  timer = setInterval(
    () => refreshSocialHousing('scheduled').catch((error) =>
      console.warn(`[social-housing] scheduled failed: ${error?.message || error}`),
    ),
    SOCIAL_REFRESH_MS,
  );
  timer.unref?.();

  console.log(
    `[social-housing] refresh every ${SOCIAL_REFRESH_MINUTES} min; ` +
    `Threads queries/cycle=${THREADS_QUERIES_PER_CYCLE}`,
  );
}
