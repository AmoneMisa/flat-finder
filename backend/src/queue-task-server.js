import express from 'express';
import { randomUUID } from 'node:crypto';
import { COUNTRIES } from './countries.js';
import { initDb, closeDb } from './db.js';
import {
  initElasticsearch,
  closeElasticsearch,
} from './elasticsearch.js';
import { processQueueTask } from './queueTasks.js';
import {
  claimTask,
  completeTask,
  dispatchGenerationIfIdle,
  failTask,
  initCrawlQueueSchema,
  pruneQueueHistory,
  queueStats,
} from './pgQueue.js';

const app = express();
const port = Number(process.env.QUEUE_TASK_PORT) || 4010;
const internalKey = String(process.env.QUEUE_INTERNAL_KEY || '');
const queueProtocol = Math.max(3, Number(process.env.QUEUE_PROTOCOL_VERSION) || 3);
const crawlerShards = Math.max(1, Number(process.env.QUEUE_SHARDS) || 2);
const refreshSeconds = Math.max(60, Number(process.env.QUEUE_REFRESH_SECONDS) || 1800);
const maxAttempts = Math.max(1, Number(process.env.QUEUE_MAX_ATTEMPTS) || 5);
const leaseMs = Math.max(
  60_000,
  Number(process.env.QUEUE_TASK_LEASE_SECONDS || 300) * 1000,
);
const dispatchPollMs = Math.min(30_000, Math.max(5_000, refreshSeconds * 1000));

app.use(express.json({ limit: '512kb' }));

function authorized(req) {
  return internalKey.length >= 16
    && String(req.get('x-queue-key') || '') === internalKey;
}

function channelConfig(value) {
  if (typeof value === 'string') {
    return { name: value, city: null, dealType: null };
  }

  if (value && typeof value === 'object' && value.name) {
    return {
      name: String(value.name),
      city: value.city ? String(value.city) : null,
      dealType: value.dealType ? String(value.dealType) : null,
    };
  }

  return null;
}

function stableHash(value) {
  let hash = 2166136261;
  for (const char of String(value || '')) {
    hash ^= char.codePointAt(0);
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  return hash >>> 0;
}

function chainKey(task) {
  if (task.type === 'flat.olx.page') {
    return [
      task.country,
      task.citySlug || 'all',
      task.segment || 'all',
    ].join(':');
  }

  if (task.type === 'flat.telegram.channel') {
    return [
      task.country,
      'telegram',
      task.channel || 'unknown',
    ].join(':');
  }

  return [task.country || 'unknown', task.type || 'unknown'].join(':');
}

function crawlerShard(task) {
  return stableHash(chainKey(task)) % crawlerShards;
}

function versionTask(task, crawlGeneration) {
  return {
    ...task,
    queueProtocol,
    crawlGeneration,
    crawlerShard: crawlerShard(task),
  };
}

function taskPriority(task) {
  if (task.type === 'flat.olx.page') {
    if (task.country === 'UA' && task.page === 1 && task.city) return 10;
    if (task.page === 1 && task.city) return 9;
    if (task.page === 1) return 7;
    return Math.max(1, 7 - task.page);
  }

  if (task.type === 'flat.telegram.channel') {
    if (
      task.country === 'UA' &&
      ['Lutsk', 'Chernivtsi', 'Uzhhorod', 'Mukachevo'].includes(task.city)
    ) {
      return 10;
    }
    return 8;
  }

  return 1;
}

function buildPlan() {
  const tasks = [];
  const crawlGeneration = randomUUID();

  for (const country of Object.values(COUNTRIES)) {
    if (country.sources?.includes('olx')) {
      const segments = ['flat:longRent', 'flat:sale'];

      if (country.code === 'UA' && Array.isArray(country.olxCities)) {
        for (const target of country.olxCities) {
          for (const segment of segments) {
            const task = versionTask({
              type: 'flat.olx.page',
              country: country.code,
              city: target.city,
              citySlug: target.slug,
              segment,
              page: 1,
            }, crawlGeneration);
            tasks.push({ ...task, priority: taskPriority(task) });
          }
        }

        for (const segment of segments) {
          const task = versionTask({
            type: 'flat.olx.page',
            country: country.code,
            city: null,
            citySlug: null,
            segment,
            page: 1,
          }, crawlGeneration);
          tasks.push({ ...task, priority: taskPriority(task) });
        }
      } else {
        for (const segment of segments) {
          const task = versionTask({
            type: 'flat.olx.page',
            country: country.code,
            city: null,
            citySlug: null,
            segment,
            page: 1,
          }, crawlGeneration);
          tasks.push({ ...task, priority: taskPriority(task) });
        }
      }
    }

    if (country.sources?.includes('telegram')) {
      for (const raw of country.telegramChannels ?? []) {
        const channel = channelConfig(raw);
        if (!channel) continue;

        const task = versionTask({
          type: 'flat.telegram.channel',
          country: country.code,
          channel: channel.name,
          city: channel.city,
        }, crawlGeneration);
        tasks.push({ ...task, priority: taskPriority(task) });
      }
    }
  }

  return { tasks, crawlGeneration };
}

app.get('/health', async (_req, res) => {
  try {
    const stats = await queueStats();
    res.json({ ok: true, queue: stats });
  } catch (error) {
    res.status(503).json({
      ok: false,
      error: error?.message ?? String(error),
    });
  }
});

app.get('/internal/queue-plan', (req, res) => {
  if (!authorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { tasks, crawlGeneration } = buildPlan();
  return res.json({
    ok: true,
    count: tasks.length,
    queueProtocol,
    crawlerShards,
    crawlGeneration,
    tasks,
  });
});

app.get('/internal/queue-stats', async (req, res) => {
  if (!authorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  return res.json({ ok: true, ...(await queueStats()) });
});

app.post('/internal/queue-claim', async (req, res) => {
  if (!authorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const role = String(req.body?.role || 'olx').toLowerCase();
  if (!['olx', 'telegram'].includes(role)) {
    return res.status(400).json({ error: 'Invalid worker role' });
  }

  const shard = Math.max(0, Math.trunc(Number(req.body?.shard) || 0));
  if (role === 'olx' && shard >= crawlerShards) {
    return res.status(400).json({ error: 'Invalid crawler shard' });
  }

  try {
    const task = await claimTask({
      role,
      shard,
      workerId: req.body?.workerId,
      leaseMs,
      maxAttempts,
    });
    return res.json({ ok: true, task });
  } catch (error) {
    console.error('[pg-queue] claim failed:', error?.message ?? error);
    return res.status(500).json({ ok: false, error: error?.message ?? String(error) });
  }
});

app.post('/internal/queue-task', async (req, res) => {
  if (!authorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const result = await processQueueTask(req.body || {});
    return res.json(result);
  } catch (error) {
    console.error('[queue-task] failed:', error?.message ?? error);
    return res.status(500).json({
      ok: false,
      error: error?.message ?? String(error),
    });
  }
});

app.post('/internal/queue-complete', async (req, res) => {
  if (!authorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const id = String(req.body?.id || '');
  const lockToken = String(req.body?.lockToken || '');
  if (!id || !lockToken) {
    return res.status(400).json({ error: 'Missing task id or lock token' });
  }

  try {
    const outcome = await completeTask({
      id,
      lockToken,
      result: req.body?.result || {},
    });
    return res.status(outcome.completed ? 200 : 409).json({ ok: outcome.completed, ...outcome });
  } catch (error) {
    console.error('[pg-queue] complete failed:', error?.message ?? error);
    return res.status(500).json({ ok: false, error: error?.message ?? String(error) });
  }
});

app.post('/internal/queue-fail', async (req, res) => {
  if (!authorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const id = String(req.body?.id || '');
  const lockToken = String(req.body?.lockToken || '');
  if (!id || !lockToken) {
    return res.status(400).json({ error: 'Missing task id or lock token' });
  }

  try {
    const outcome = await failTask({
      id,
      lockToken,
      error: req.body?.error,
      maxAttempts,
    });
    return res.status(outcome.failed ? 200 : 409).json({ ok: outcome.failed, ...outcome });
  } catch (error) {
    console.error('[pg-queue] fail transition failed:', error?.message ?? error);
    return res.status(500).json({ ok: false, error: error?.message ?? String(error) });
  }
});

let dispatching = false;
async function dispatchTick() {
  if (dispatching) return;
  dispatching = true;
  try {
    const { tasks, crawlGeneration } = buildPlan();
    const outcome = await dispatchGenerationIfIdle(tasks, refreshSeconds);
    if (outcome.queued > 0) {
      const perShard = Array.from({ length: crawlerShards }, () => 0);
      let telegram = 0;
      for (const task of tasks) {
        if (task.type === 'flat.telegram.channel') telegram += 1;
        else perShard[task.crawlerShard] += 1;
      }
      console.log(
        `[pg-queue] queued ${outcome.queued} tasks generation=${crawlGeneration} ` +
        `olx_shards=${JSON.stringify(perShard)} telegram=${telegram}`,
      );
    }
  } catch (error) {
    console.error('[pg-queue] dispatcher failed:', error?.message ?? error);
  } finally {
    dispatching = false;
  }
}

await initDb();
await initElasticsearch();
await initCrawlQueueSchema();
await pruneQueueHistory().catch((error) => {
  console.warn('[pg-queue] initial history prune failed:', error?.message ?? error);
});

const server = app.listen(port, '0.0.0.0', () => {
  console.log(
    `[queue-task] listening on :${port} protocol=${queueProtocol} shards=${crawlerShards} backend=postgres`,
  );
  void dispatchTick();
});

const dispatchTimer = setInterval(() => void dispatchTick(), dispatchPollMs);
dispatchTimer.unref?.();
const pruneTimer = setInterval(
  () => void pruneQueueHistory().catch((error) => {
    console.warn('[pg-queue] history prune failed:', error?.message ?? error);
  }),
  24 * 60 * 60_000,
);
pruneTimer.unref?.();

async function shutdown() {
  clearInterval(dispatchTimer);
  clearInterval(pruneTimer);
  server.close(async () => {
    await Promise.allSettled([
      closeDb(),
      closeElasticsearch(),
    ]);
    process.exit(0);
  });
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
