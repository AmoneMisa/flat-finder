import { createHash } from 'node:crypto';

const workerUrl = String(process.env.AI_WORKER_URL || '').replace(/\/$/, '');
const workerKey = process.env.AI_WORKER_KEY || '';
const requestTimeoutMs = Math.max(500, Number(process.env.AI_WORKER_REQUEST_TIMEOUT_MS) || 3000);
const pollIntervalMs = Math.max(1000, Number(process.env.AI_WORKER_POLL_MS) || 5000);
const maxQueued = Math.max(1, Number(process.env.AI_WORKER_MAX_PENDING) || 60);
const submitConcurrency = Math.max(1, Number(process.env.AI_WORKER_SUBMIT_CONCURRENCY) || 4);

const queue = [];
const pending = new Map();
const scheduled = new Set();
let activeSubmissions = 0;
let pollTimer = null;
let lastWarningAt = 0;

function warn(message) {
  if (Date.now() - lastWarningAt < 60_000) return;
  lastWarningAt = Date.now();
  console.warn(`[ai-worker] ${message}`);
}

function stable(value) {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.entries(value)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

export function aiFingerprint(kind, rawText, knownFacts) {
  return createHash('sha256')
    .update(`${kind}\0${rawText.replace(/\s+/g, ' ').trim()}\0${stable(knownFacts)}`)
    .digest('hex')
    .slice(0, 24);
}

export function aiWorkerEnabled() {
  return Boolean(workerUrl);
}

async function request(path, init = {}) {
  const headers = new Headers(init.headers);
  headers.set('accept', 'application/json');
  if (init.body) headers.set('content-type', 'application/json');
  if (workerKey) headers.set('x-ai-key', workerKey);
  const response = await fetch(`${workerUrl}${path}`, {
    ...init,
    headers,
    signal: AbortSignal.timeout(requestTimeoutMs),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

async function finish(task, result) {
  scheduled.delete(task.fingerprint);
  try {
    await task.onResult(result);
  } catch (error) {
    warn(`result merge failed for ${task.id}: ${error.message}`);
  }
}

async function fail(task, status) {
  scheduled.delete(task.fingerprint);
  try {
    await task.onFailed?.(status);
  } catch (error) {
    warn(`failure callback failed for ${task.id}: ${error.message}`);
  }
}

function schedulePoll() {
  if (pollTimer || pending.size === 0) return;
  pollTimer = setTimeout(() => {
    pollTimer = null;
    void pollPending();
  }, pollIntervalMs);
  pollTimer.unref?.();
}

async function pollPending() {
  const batch = [...pending.entries()].slice(0, submitConcurrency * 2);
  await Promise.all(batch.map(async ([key, task]) => {
    try {
      const result = await request(`/ai/result/${encodeURIComponent(key)}`);
      if (result.status === 'completed') {
        pending.delete(key);
        await finish(task, result);
      } else if (['failed', 'not_found', 'disabled'].includes(result.status)) {
        pending.delete(key);
        await fail(task, result.status);
      }
    } catch (error) {
      warn(`poll unavailable: ${error.message}`);
    }
  }));
  schedulePoll();
}

async function submit(task) {
  try {
    const result = await request('/ai/extract', {
      method: 'POST',
      body: JSON.stringify({
        kind: task.kind,
        rawText: task.rawText,
        knownFacts: task.knownFacts,
        meta: task.meta || {},
      }),
    });
    if (result.status === 'completed') await finish(task, result);
    else if (result.status === 'pending' && result.key) {
      pending.set(result.key, task);
      schedulePoll();
    } else await fail(task, result.status);
  } catch (error) {
    warn(`submission unavailable: ${error.message}`);
    await fail(task, 'unavailable');
  } finally {
    activeSubmissions -= 1;
    pump();
  }
}

function pump() {
  while (activeSubmissions < submitConcurrency && queue.length) {
    const task = queue.shift();
    activeSubmissions += 1;
    void submit(task);
  }
}

export function scheduleAiExtraction(task) {
  if (!aiWorkerEnabled() || !task.rawText?.trim()) return false;
  const fingerprint = task.fingerprint || aiFingerprint(task.kind, task.rawText, task.knownFacts);
  if (scheduled.has(fingerprint) || queue.length + pending.size + activeSubmissions >= maxQueued) return false;
  scheduled.add(fingerprint);
  queue.push({ ...task, fingerprint });
  pump();
  return true;
}
