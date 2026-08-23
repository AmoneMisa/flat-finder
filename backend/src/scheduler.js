// Refresh commands and shared maintenance helpers. Recurring crawling is owned
// exclusively by src/worker.js. API-triggered refreshes enqueue a crawl generation
// in PostgreSQL; they never execute marketplace scrapers inside the HTTP process.

import {geocodeBbox, geocodeQuery} from './geocode.js';
import {placesFreshness} from './places-db.js';
import {syncAllPlaces} from './places-sync.js';
import {dispatchGenerationIfIdle} from './pgQueue.js';
import {buildCrawlPlan, QUEUE_SHARDS} from './queuePlan.js';

const PLACES_MAX_AGE_MS = Math.max(
  1,
  Number(process.env.PLACES_REFRESH_DAYS) || 30,
) * 24 * 60 * 60 * 1000;
const MANUAL_REFRESH_COOLDOWN_SECONDS = Math.max(
  60,
  Number(process.env.MANUAL_REFRESH_COOLDOWN_SECONDS) || 60,
);

let dispatching = false;
let placesRunning = false;
let lastRun = null;

// Preserve the existing refresh command used by clients, but keep execution in
// worker.js. The queue transaction globally prevents duplicate generations and
// refuses to open a new generation while another one is pending/running.
export async function refreshAll(reason = 'manual') {
  if (dispatching) return lastRun;
  dispatching = true;

  try {
    const {tasks, crawlGeneration} = buildCrawlPlan({shardCount: QUEUE_SHARDS});
    const outcome = await dispatchGenerationIfIdle(
      tasks,
      MANUAL_REFRESH_COOLDOWN_SECONDS,
    );

    lastRun = {
      at: new Date().toISOString(),
      reason,
      crawlGeneration,
      taskCount: tasks.length,
      queued: outcome.queued,
      queueReason: outcome.reason,
      retryAfterMs: outcome.retryAfterMs ?? null,
    };

    console.log(
      `[scheduler] ${reason} refresh request: queued=${outcome.queued}/${tasks.length} ` +
        `reason=${outcome.reason} generation=${crawlGeneration}`,
    );

    return lastRun;
  } finally {
    dispatching = false;
  }
}

/**
 * Refills the places table when it is empty or older than the max age. The
 * worker calls this on startup and periodically; failures are deliberately
 * non-fatal because listing ingestion must not depend on OSM availability.
 */
export async function refreshPlaces(force = false) {
  if (placesRunning) return null;
  placesRunning = true;

  try {
    const freshness = await placesFreshness();
    const newest = freshness.reduce(
      (latest, row) => Math.max(
        latest,
        new Date(row.updated_at || 0).getTime() || 0,
      ),
      0,
    );

    if (!force && newest && Date.now() - newest < PLACES_MAX_AGE_MS) {
      console.log(
        `[places] skipping sync, table filled ` +
          `${Math.round((Date.now() - newest) / 86_400_000)}d ago`,
      );
      return null;
    }

    return await syncAllPlaces(geocodeQuery, geocodeBbox);
  } catch (error) {
    console.warn('[places] sync failed:', error?.message || error);
    return null;
  } finally {
    placesRunning = false;
  }
}

export function getLastRun() {
  return lastRun;
}
