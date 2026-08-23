import {hostname} from 'node:os';
import {closeDb, initDb} from './db.js';
import {closeElasticsearch, initElasticsearch} from './elasticsearch.js';
import {processQueueTask} from './queueTasks.js';
import {
  claimTask,
  completeTask,
  dispatchGenerationIfIdle,
  failTask,
  pruneQueueHistory,
} from './pgQueue.js';
import {buildCrawlPlan, QUEUE_SHARDS} from './queuePlan.js';
import {refreshPlaces} from './scheduler.js';
import {startSocialHousingScheduler} from './social-housing-scheduler.js';
import {verifyDueListingAvailability} from './availability-sweep.js';

const REFRESH_SECONDS = Math.max(60, Number(process.env.QUEUE_REFRESH_SECONDS) || 1800);
const POLL_MS = Math.max(200, Number(process.env.QUEUE_POLL_SECONDS || 1) * 1000);
const ERROR_RETRY_MS = Math.max(1_000, Number(process.env.QUEUE_ERROR_RETRY_SECONDS || 5) * 1000);
const DISPATCH_MS = Math.min(30_000, Math.max(5_000, Number(process.env.QUEUE_DISPATCH_TICK_SECONDS || 10) * 1000));
const PRUNE_MS = Math.max(60_000, Number(process.env.QUEUE_HISTORY_PRUNE_SECONDS || 86_400) * 1000);
const PLACES_CHECK_MS = Math.max(60 * 60_000, Number(process.env.PLACES_CHECK_HOURS || 24) * 60 * 60_000);
const AVAILABILITY_SWEEP_MS = Math.max(
  30_000,
  Number(process.env.LISTING_AVAILABILITY_SWEEP_SECONDS || 30) * 1000,
);

let stopping = false;
let dispatching = false;
let availabilityRunning = false;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function workerId(role, shard) {
  const suffix = role === 'telegram' ? 'telegram' : `olx:${shard}`;
  return String(`${hostname()}:${suffix}`).slice(0, 200);
}

async function dispatchTick() {
  if (dispatching || stopping) return;
  dispatching = true;
  try {
    const {tasks, crawlGeneration} = buildCrawlPlan({shardCount: QUEUE_SHARDS});
    const outcome = await dispatchGenerationIfIdle(tasks, REFRESH_SECONDS);
    if (outcome.queued > 0) {
      console.log(
        `[flat:worker] queued ${outcome.queued} crawl tasks generation=${crawlGeneration}`,
      );
    }
  } catch (error) {
    console.error('[flat:worker] dispatcher failed:', error?.message ?? error);
  } finally {
    dispatching = false;
  }
}

async function availabilityTick() {
  if (availabilityRunning || stopping) return;
  availabilityRunning = true;
  try {
    const results = await verifyDueListingAvailability();
    if (results.length) {
      const inactive = results.filter((item) => item.status === 'inactive').length;
      console.log(`[flat:worker] availability checked=${results.length} inactive=${inactive}`);
    }
  } catch (error) {
    console.warn('[flat:worker] availability sweep failed:', error?.message ?? error);
  } finally {
    availabilityRunning = false;
  }
}

async function failClaim(task, error) {
  try {
    const outcome = await failTask({
      id: task.id,
      lockToken: task.lockToken,
      error: error?.message ?? String(error),
    });
    console.error(
      `[flat:worker] failed type=${task.payload?.type} country=${task.payload?.country} ` +
      `attempt=${task.attempts} dead=${Boolean(outcome.dead)}: ${error?.message ?? error}`,
    );
  } catch (transitionError) {
    console.error(
      `[flat:worker] failed to transition task ${task.id}:`,
      transitionError?.message ?? transitionError,
    );
  }
}

async function executeClaim(task, label) {
  try {
    const result = await processQueueTask(task.payload || {});
    const outcome = await completeTask({
      id: task.id,
      lockToken: task.lockToken,
      result,
    });
    if (!outcome.completed) {
      throw new Error(`completion lost queue lease: ${outcome.reason || 'unknown'}`);
    }
    console.log(
      `[flat:worker:${label}] completed ${task.payload?.type} ` +
      `country=${task.payload?.country || '-'} fetched=${result?.fetched || 0} ` +
      `saved=${result?.saved || 0} next=${outcome.queuedNext || 0}`,
    );
  } catch (error) {
    await failClaim(task, error);
  }
}

async function workerLoop(role, shard = 0) {
  const label = role === 'telegram' ? 'telegram' : `olx:${shard}`;
  const id = workerId(role, shard);
  console.log(`[flat:worker:${label}] direct PostgreSQL worker started id=${id}`);

  while (!stopping) {
    try {
      const task = await claimTask({role, shard, workerId: id});
      if (!task) {
        await sleep(POLL_MS);
        continue;
      }
      await executeClaim(task, label);
    } catch (error) {
      console.error(`[flat:worker:${label}] loop error:`, error?.message ?? error);
      await sleep(ERROR_RETRY_MS);
    }
  }
}

async function main() {
  // Versioned migrations are guaranteed by the Compose/deploy migration gate.
  // Worker startup therefore performs runtime initialization only, never schema DDL.
  await initDb();

  try {
    await initElasticsearch();
  } catch (error) {
    console.warn('[flat:worker] Elasticsearch startup degraded:', error?.message ?? error);
  }

  await pruneQueueHistory().catch((error) => {
    console.warn('[flat:worker] initial queue prune failed:', error?.message ?? error);
  });

  startSocialHousingScheduler();
  void refreshPlaces().catch((error) => {
    console.warn('[flat:worker] places startup check failed:', error?.message ?? error);
  });
  void availabilityTick();

  await dispatchTick();

  const dispatchTimer = setInterval(() => void dispatchTick(), DISPATCH_MS);
  const pruneTimer = setInterval(
    () => void pruneQueueHistory().catch((error) => {
      console.warn('[flat:worker] queue prune failed:', error?.message ?? error);
    }),
    PRUNE_MS,
  );
  const placesTimer = setInterval(
    () => void refreshPlaces().catch((error) => {
      console.warn('[flat:worker] places check failed:', error?.message ?? error);
    }),
    PLACES_CHECK_MS,
  );
  const availabilityTimer = setInterval(() => void availabilityTick(), AVAILABILITY_SWEEP_MS);
  dispatchTimer.unref?.();
  pruneTimer.unref?.();
  placesTimer.unref?.();
  availabilityTimer.unref?.();

  try {
    await Promise.all([
      ...Array.from({length: QUEUE_SHARDS}, (_, shard) => workerLoop('olx', shard)),
      workerLoop('telegram', 0),
    ]);
  } finally {
    clearInterval(dispatchTimer);
    clearInterval(pruneTimer);
    clearInterval(placesTimer);
    clearInterval(availabilityTimer);
    await Promise.allSettled([closeElasticsearch(), closeDb()]);
  }
}

for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    console.log(`[flat:worker] ${signal}, stopping after current tasks`);
    stopping = true;
  });
}

main().catch((error) => {
  console.error('[flat:worker] fatal:', error?.stack || error?.message || error);
  process.exit(1);
});
