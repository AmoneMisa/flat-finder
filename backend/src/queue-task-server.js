import express from 'express';
import { COUNTRIES } from './countries.js';
import { initDb, closeDb } from './db.js';
import {
  initElasticsearch,
  closeElasticsearch,
} from './elasticsearch.js';
import { processQueueTask } from './queueTasks.js';

const app = express();
const port = Number(process.env.QUEUE_TASK_PORT) || 4010;
const internalKey = String(process.env.QUEUE_INTERNAL_KEY || '');
const QUEUE_PROTOCOL_VERSION = 2;

app.use(express.json({ limit: '256kb' }));

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

function queueTask(task) {
  return {
    ...task,
    queueProtocol: QUEUE_PROTOCOL_VERSION,
    priority: taskPriority(task),
  };
}

function buildPlan() {
  const tasks = [];

  for (const country of Object.values(COUNTRIES)) {
    if (country.sources?.includes('olx')) {
      const segments = ['flat:longRent', 'flat:sale'];

      if (country.code === 'UA' && Array.isArray(country.olxCities)) {
        for (const target of country.olxCities) {
          for (const segment of segments) {
            const task = {
              type: 'flat.olx.page',
              country: country.code,
              city: target.city,
              citySlug: target.slug,
              segment,
              page: 1,
            };
            tasks.push(queueTask(task));
          }
        }

        // Start one national chain per segment for towns that are not curated.
        // Every successful OLX page decides whether page N+1 is still inside
        // the freshness window, so the queue is no longer pre-filled with a
        // guessed fixed page count.
        for (const segment of segments) {
          const task = {
            type: 'flat.olx.page',
            country: country.code,
            city: null,
            citySlug: null,
            segment,
            page: 1,
          };
          tasks.push(queueTask(task));
        }
      } else {
        // Other OLX portals use the same dynamic page-chain protocol.
        for (const segment of segments) {
          const task = {
            type: 'flat.olx.page',
            country: country.code,
            city: null,
            citySlug: null,
            segment,
            page: 1,
          };
          tasks.push(queueTask(task));
        }
      }
    }

    if (country.sources?.includes('telegram')) {
      for (const raw of country.telegramChannels ?? []) {
        const channel = channelConfig(raw);
        if (!channel) continue;

        const task = {
          type: 'flat.telegram.channel',
          country: country.code,
          channel: channel.name,
          city: channel.city,
        };
        tasks.push(queueTask(task));
      }
    }
  }

  return tasks;
}

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

app.get('/internal/queue-plan', (req, res) => {
  if (!authorized(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const tasks = buildPlan();
  return res.json({
    ok: true,
    queueProtocol: QUEUE_PROTOCOL_VERSION,
    count: tasks.length,
    tasks,
  });
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

await initDb();
await initElasticsearch();

const server = app.listen(port, '0.0.0.0', () => {
  console.log(`[queue-task] listening on :${port}`);
});

async function shutdown() {
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