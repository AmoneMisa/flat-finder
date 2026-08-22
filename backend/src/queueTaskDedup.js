const mem = new Map();

const RUNNING_TTL_MS = Math.max(
  60_000,
  Number(process.env.QUEUE_TASK_RUNNING_TTL_MS) || 5 * 60_000,
);
const DONE_TTL_MS = Math.max(
  RUNNING_TTL_MS,
  Number(process.env.QUEUE_TASK_DONE_TTL_MS) || 24 * 60 * 60_000,
);

let client = null;
let ready = false;
let initPromise = null;

function taskIdentity(task) {
  return [
    task.queueProtocol || 0,
    task.crawlGeneration || 'legacy',
    task.type || 'unknown',
    task.country || 'unknown',
    task.citySlug || task.city || 'all',
    task.segment || task.channel || 'all',
    task.page || 0,
  ].join(':');
}

function redisKey(task) {
  return `ff:queue-task:${taskIdentity(task)}`;
}

async function ensureClient() {
  if (initPromise) return initPromise;

  initPromise = (async () => {
    const url = process.env.REDIS_URL;
    if (!url) return;

    try {
      const { createClient } = await import('redis');
      const instance = createClient({ url });
      instance.on('error', (error) => {
        if (ready) {
          console.warn('[queue-dedup] redis error:', error.message);
        }
        ready = false;
      });
      await instance.connect();
      client = instance;
      ready = true;
      console.log('[queue-dedup] connected to Redis');
    } catch (error) {
      console.warn('[queue-dedup] Redis unavailable, using memory:', error.message);
      client = null;
      ready = false;
    }
  })();

  return initPromise;
}

ensureClient();

function memGet(key) {
  const value = mem.get(key);
  if (!value) return null;
  if (Date.now() >= value.expiresAt) {
    mem.delete(key);
    return null;
  }
  return value;
}

function memSet(key, state, value, ttlMs) {
  mem.set(key, {
    state,
    value,
    expiresAt: Date.now() + ttlMs,
  });
}

export async function executeQueueTaskOnce(task, execute) {
  await ensureClient();
  const key = redisKey(task);

  if (client && ready) {
    const lock = await client.set(
      key,
      JSON.stringify({ state: 'running' }),
      { NX: true, PX: RUNNING_TTL_MS },
    );

    if (lock !== 'OK') {
      const raw = await client.get(key);
      if (raw) {
        try {
          const existing = JSON.parse(raw);
          if (existing.state === 'done' && existing.result) {
            return {
              ...existing.result,
              deduplicated: true,
            };
          }
        } catch {}
      }

      throw new Error(`queue task already running: ${taskIdentity(task)}`);
    }

    try {
      const result = await execute();
      await client.set(
        key,
        JSON.stringify({ state: 'done', result }),
        { PX: DONE_TTL_MS },
      );
      return result;
    } catch (error) {
      try {
        await client.del(key);
      } catch {}
      throw error;
    }
  }

  const existing = memGet(key);
  if (existing?.state === 'done') {
    return {
      ...existing.value,
      deduplicated: true,
    };
  }
  if (existing?.state === 'running') {
    throw new Error(`queue task already running: ${taskIdentity(task)}`);
  }

  memSet(key, 'running', null, RUNNING_TTL_MS);
  try {
    const result = await execute();
    memSet(key, 'done', result, DONE_TTL_MS);
    return result;
  } catch (error) {
    mem.delete(key);
    throw error;
  }
}

export async function closeQueueTaskDedup() {
  if (client) {
    try {
      await client.quit();
    } catch {}
  }
  client = null;
  ready = false;
}
