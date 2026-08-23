import { COUNTRIES } from './countries.js';
import { markMissingAfterCompleteCrawl, upsertListings } from './db.js';
import { deleteListingDocuments, indexListings } from './elasticsearch.js';
import { scrapeFacebook, scrapeThreads } from './scrapers/social.js';

const SOCIAL_REFRESH_MINUTES = Math.max(10, Number(process.env.SOCIAL_HOUSING_REFRESH_MINUTES) || 30);
const SOCIAL_REFRESH_MS = SOCIAL_REFRESH_MINUTES * 60 * 1000;
const START_DELAY_MS = Math.max(5_000, Number(process.env.SOCIAL_HOUSING_START_DELAY_MS) || 20_000);

let timer = null;
let running = false;

const UZ_CONFIG = {
  ...(COUNTRIES.UZ || {}),
  facebookHousingTargets: [
    { target: 'https://www.facebook.com/groups/antimakler/', city: 'Tashkent' },
    { target: 'https://www.facebook.com/groups/741615396187925/', city: 'Tashkent' },
    { target: 'https://www.facebook.com/groups/281140502050492/', city: 'Tashkent' },
  ],
  threadsHousingQueries: [
    { target: 'Аренда Ташкент', city: 'Tashkent' },
    { target: 'Сдам квартиру Ташкент', city: 'Tashkent' },
    { target: 'Apartment for rent Tashkent', city: 'Tashkent' },
    { target: 'Uy ijaraga Toshkent', city: 'Tashkent' },
    { target: 'Kvartira ijara Toshkent', city: 'Tashkent' },
  ],
};

async function persist(source, result, crawlStartedAt) {
  const listings = Array.isArray(result?.listings) ? result.listings : [];
  let saved = 0;

  if (listings.length) {
    saved = await upsertListings(listings);
    try {
      await indexListings(listings);
    } catch (error) {
      console.warn(`[social-housing] ${source} Elasticsearch failed: ${error?.message || error}`);
    }
  }

  if (result?.complete === true) {
    try {
      const missing = await markMissingAfterCompleteCrawl({
        source,
        country: UZ_CONFIG.code,
        crawlStartedAt,
      });
      if (missing.deactivated?.length) {
        await deleteListingDocuments(missing.deactivated).catch((error) => {
          console.warn(
            `[social-housing] ${source} deactivation index sync failed: ${error?.message || error}`,
          );
        });
      }
    } catch (error) {
      console.warn(`[social-housing] ${source} missing-row sweep failed: ${error?.message || error}`);
    }
  } else {
    console.warn(
      `[social-housing] ${source} crawl partial; keeping unseen rows active ` +
      `(errors=${Array.isArray(result?.errors) ? result.errors.length : 0})`,
    );
  }

  return saved;
}

export async function refreshSocialHousing(reason = 'scheduled') {
  if (running) return null;
  if (process.env.SOCIAL_HOUSING_SOURCE === 'off') return null;
  running = true;

  try {
    const crawlStartedAt = {
      facebook: new Date().toISOString(),
      threads: new Date().toISOString(),
    };
    const [facebook, threads] = await Promise.allSettled([
      scrapeFacebook(UZ_CONFIG),
      scrapeThreads(UZ_CONFIG),
    ]);

    const counts = { facebook: 0, threads: 0 };

    if (facebook.status === 'fulfilled') {
      counts.facebook = await persist('facebook', facebook.value, crawlStartedAt.facebook);
    } else {
      console.warn(`[social-housing] Facebook failed: ${facebook.reason?.message || facebook.reason}`);
    }

    if (threads.status === 'fulfilled') {
      counts.threads = await persist('threads', threads.value, crawlStartedAt.threads);
    } else {
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

  console.log(`[social-housing] refresh every ${SOCIAL_REFRESH_MINUTES} min`);
}
