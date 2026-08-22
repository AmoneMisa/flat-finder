import { randomUUID } from 'node:crypto';

const mem = new Map();

const RUNNING_TTL_MS = Math.max(
  30_000,
  Number(process.env.QUEUE_TASK_RUNNING_TTL_MS) || 90_000,
);
const DONE_TTL_MS = Math.max(
  RUNNING_TTL_MS,
  Number(process.env.QUEUE_TASK_DONE_TTL_MS) || 24 * 60 * 60_000,
);
const RENEW_INTERVAL_MS = Math.max(10_000, Math.floor(RUNNING_TTL_MS / 3));

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

const REFRESH_LOCK_SCRIPT = `
local current = redis.call('GET', KEYS[1])
if current == ARGV[1] then
  return redis.call('PEXPIRE', KEYS[1], ARGV[2])
end
return 0
`;

const FINISH_LOCK_SCRIPT = `
local current = redis.call('GET', KEYS[1])
if current == ARGV[1] then
  redis.call('SET', KEYS[1], ARGV[2], 'PX', ARGV[3])
  return 1
end
return 0
`;

const RELEASE_LOCK_SCRIPT = `
local current = redis.call('GET', KEYS[1])
if current == ARGV[1] then
  return redis.call('DEL', KEYS[1])
end
return 0
`;

async function refreshRedisLock(key, runningValue) {
  if (!client || !ready) return;
  await client.eval(
    REFRESH_LOCK_SCRIPT,
    {
      keys: [key],
      arguments: [runningValue, String(RUNNING_TTL_MS)],
    },
  );
}

async function finishRedisLock(key, runningValue, result) {
  const doneValue = JSON.stringify({ state: 'done', result });
  return client.eval(
    FINISH_LOCK_SCRIPT,
    {
      keys: [key],
      arguments: [runningValue, doneValue, String(DONE_TTL_MS)],
    },
  );
}

async function releaseRedisLock(key, runningValue) {
  if (!client) return;
  await client.eval(
    RELEASE_LOCK_SCRIPT,
    {
      keys: [key],
      arguments: [runningValue],
    },
  );
}

export async function executeQueueTaskOnce(task, execute) {
  await ensureClient();
  const key = redisKey(task);

  if (client && ready) {
    const token = randomUUID();
    const runningValue = JSON.stringify({ state: 'running', token });
    const lock = await client.set(
      key,
      runningValue,
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

    const renewTimer = setInterval(() => {
      refreshRedisLock(key, runningValue).catch((error) => {
        console.warn('[queue-dedup] lock refresh failed:', error.message);
      });
    }, RENEW_INTERVAL_MS);
    renewTimer.unref?.();

    try {
      const result = await execute();
      const finished = await finishRedisLock(key, runningValue, result);
      if (!finished) {
        throw new Error(`queue task lost dedup lock: ${taskIdentity(task)}`);
      }
      return result;
    } catch (error) {
      try {
        await releaseRedisLock(key, runningValue);
      } catch {}
      throw error;
    } finally {
      clearInterval(renewTimer);
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
