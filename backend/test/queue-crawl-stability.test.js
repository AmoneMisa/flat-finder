import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const queueServer = readFileSync(new URL('../src/queue-task-server.js', import.meta.url), 'utf8');
const queueTasks = readFileSync(new URL('../src/queueTasks.js', import.meta.url), 'utf8');
const queueDedup = readFileSync(new URL('../src/queueTaskDedup.js', import.meta.url), 'utf8');
const pgQueue = readFileSync(new URL('../src/pgQueue.js', import.meta.url), 'utf8');
const scheduler = readFileSync(new URL('../src/scheduler.js', import.meta.url), 'utf8');
const worker = readFileSync(new URL('../../queue-worker/worker.py', import.meta.url), 'utf8');
const workerDockerfile = readFileSync(new URL('../../queue-worker/Dockerfile', import.meta.url), 'utf8');
const compose = readFileSync(new URL('../../docker-compose.yml', import.meta.url), 'utf8');

test('queue plan seeds one OLX page and lets successful tasks extend the chain', () => {
  assert.doesNotMatch(queueServer, /page\s*<=\s*5/);
  assert.match(queueServer, /page:\s*1/);
  assert.match(queueTasks, /pastCutoff/);
  assert.match(queueTasks, /rawCount\s*<=\s*0/);
  assert.match(queueTasks, /nextTasks:/);
  assert.match(queueTasks, /page:\s*nextPage/);
});

test('queue protocol v3 partitions stable crawl chains', () => {
  assert.match(queueServer, /queueProtocol = Math\.max\(3,/);
  assert.match(queueServer, /function stableHash/);
  assert.match(queueServer, /function chainKey/);
  assert.match(queueServer, /crawlerShard: crawlerShard\(task\)/);
  assert.match(queueServer, /crawlGeneration = randomUUID\(\)/);
  assert.match(queueTasks, /crawlerShard: task\.crawlerShard/);
  assert.match(queueTasks, /crawlGeneration: task\.crawlGeneration/);
});

test('PostgreSQL owns durable queue state, priority, leases and retries', () => {
  assert.match(pgQueue, /CREATE TABLE IF NOT EXISTS crawl_tasks/);
  assert.match(pgQueue, /status IN \('pending', 'running', 'done', 'dead'\)/);
  assert.match(pgQueue, /priority DESC/);
  assert.match(pgQueue, /FOR UPDATE SKIP LOCKED/);
  assert.match(pgQueue, /locked_until/);
  assert.match(pgQueue, /run_after/);
  assert.match(pgQueue, /ON CONFLICT \(task_key\) DO NOTHING/);
  assert.match(pgQueue, /pg_advisory_xact_lock/);
  assert.match(pgQueue, /RETRY_BASE_MS/);
  assert.match(pgQueue, /RETRY_MAX_MS/);
});

test('queue-task API dispatches generations and exposes atomic claim/complete/fail transitions', () => {
  assert.match(queueServer, /dispatchGenerationIfIdle/);
  assert.match(queueServer, /\/internal\/queue-claim/);
  assert.match(queueServer, /\/internal\/queue-complete/);
  assert.match(queueServer, /\/internal\/queue-fail/);
  assert.match(queueServer, /initCrawlQueueSchema/);
  assert.match(queueServer, /dispatchTick/);
  assert.match(queueServer, /setInterval\(\(\) => void dispatchTick\(\), dispatchPollMs\)/);
});

test('OLX workers remain pinned to independent shards', () => {
  assert.match(worker, /QUEUE_SHARD/);
  assert.match(worker, /WORKER_ROLE == "telegram"/);
  assert.match(worker, /task_type == "flat\.olx\.page" and shard == QUEUE_SHARD/);
  assert.match(worker, /\/internal\/queue-claim/);
  assert.match(compose, /QUEUE_WORKER_ROLE: olx/);
  assert.match(compose, /QUEUE_SHARD: 0/);
  assert.match(compose, /QUEUE_SHARD: 1/);
});

test('Telegram tasks stay isolated on the dedicated worker', () => {
  assert.match(worker, /return task_type == "flat\.telegram\.channel"/);
  assert.match(compose, /flat-finder-queue-worker-telegram:/);
  assert.match(compose, /QUEUE_WORKER_ROLE: telegram/);
  assert.match(compose, /TELEGRAM_WORKER_MEMORY_LIMIT:-256m/);
});

test('successful completion enqueues chained OLX pages in the same Postgres transaction', () => {
  assert.match(pgQueue, /const nextTasks = Array\.isArray\(result\?\.nextTasks\)/);
  assert.match(pgQueue, /enqueueTasks\(nextTasks, client\)/);
  assert.match(pgQueue, /await client\.query\('COMMIT'\)/);
});

test('each OLX shard is pinned to a different fetcher', () => {
  assert.match(queueTasks, /OLX_FETCHER_URL_0/);
  assert.match(queueTasks, /OLX_FETCHER_URL_1/);
  assert.match(queueTasks, /function olxFetcherUrl/);
  assert.match(compose, /OLX_FETCHER_URL_0=http:\/\/flat-finder-olx-fetcher:4020/);
  assert.match(compose, /OLX_FETCHER_URL_1=http:\/\/flat-finder-olx-fetcher-ua:4020/);
});

test('task execution deduplication remains PostgreSQL-backed during transport migration', () => {
  assert.match(queueTasks, /executeQueueTaskOnce/);
  assert.match(queueDedup, /crawl_task_runs/);
  assert.match(queueDedup, /ON CONFLICT \(task_key\)/);
  assert.match(queueDedup, /locked_until/);
  assert.match(queueDedup, /status = 'done'/);
  assert.match(queueDedup, /deduplicated: true/);
});

test('RabbitMQ and Redis are absent from the Flat Finder runtime', () => {
  assert.doesNotMatch(compose, /flat-finder-rabbitmq:/);
  assert.doesNotMatch(compose, /flat-finder-redis:/);
  assert.doesNotMatch(compose, /RABBITMQ_/);
  assert.doesNotMatch(compose, /REDIS_URL=/);
  assert.doesNotMatch(worker, /\bpika\b/);
  assert.doesNotMatch(worker, /basic_get|basic_ack|basic_publish|heartbeat/i);
  assert.doesNotMatch(workerDockerfile, /pip install/);
  assert.doesNotMatch(compose, /flat-finder-queue-dispatcher:/);
});

test('worker retries through Postgres state and logs useful task identity', () => {
  assert.match(worker, /\/internal\/queue-fail/);
  assert.match(worker, /target = "dead" if outcome\.get\("dead"\) else "retry"/);
  assert.match(worker, /segment=\{payload\.get\('segment'\) or payload\.get\('channel'\) or '-'\}/);
});

test('legacy in-process crawler stands down when the durable queue is configured', () => {
  assert.match(scheduler, /QUEUE_INTERNAL_KEY/);
  assert.match(scheduler, /ENABLE_LEGACY_LISTING_SCHEDULER/);
  assert.match(scheduler, /PostgreSQL queue owns crawl/);
});
