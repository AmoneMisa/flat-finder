import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const queueServer = readFileSync(new URL('../src/queue-task-server.js', import.meta.url), 'utf8');
const queueTasks = readFileSync(new URL('../src/queueTasks.js', import.meta.url), 'utf8');
const queueDedup = readFileSync(new URL('../src/queueTaskDedup.js', import.meta.url), 'utf8');
const scheduler = readFileSync(new URL('../src/scheduler.js', import.meta.url), 'utf8');
const worker = readFileSync(new URL('../../queue-worker/worker.py', import.meta.url), 'utf8');
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

test('workers consume independent shard queues and purge the v2 backlog', () => {
  assert.match(worker, /MAIN_QUEUE_PREFIX = "crawl\.flats\.tasks\.v3"/);
  assert.match(worker, /QUEUE_SHARD/);
  assert.match(worker, /main_queue\(QUEUE_SHARD\)/);
  assert.match(worker, /retry_queue\(QUEUE_SHARD\)/);
  assert.match(worker, /purge_legacy_queues/);
  assert.match(compose, /QUEUE_SHARD: 0/);
  assert.match(compose, /QUEUE_SHARD: 1/);
});

test('each shard is pinned to a different OLX fetcher', () => {
  assert.match(queueTasks, /OLX_FETCHER_URL_0/);
  assert.match(queueTasks, /OLX_FETCHER_URL_1/);
  assert.match(queueTasks, /function olxFetcherUrl/);
  assert.match(compose, /OLX_FETCHER_URL_0=http:\/\/flat-finder-olx-fetcher:4020/);
  assert.match(compose, /OLX_FETCHER_URL_1=http:\/\/flat-finder-olx-fetcher-ua:4020/);
});

test('crawl page execution is deduplicated per generation', () => {
  assert.match(queueTasks, /executeQueueTaskOnce/);
  assert.match(queueDedup, /task\.crawlGeneration/);
  assert.match(queueDedup, /NX: true/);
  assert.match(queueDedup, /state: 'done'/);
  assert.match(queueDedup, /deduplicated: true/);
  assert.match(compose, /REDIS_URL=redis:\/\/flat-finder-redis:6379/);
});

test('worker services AMQP heartbeats while the HTTP task is running', () => {
  assert.match(worker, /ThreadPoolExecutor/);
  assert.match(worker, /execute_with_heartbeats/);
  assert.match(worker, /connection\.process_data_events\(time_limit=1\)/);
  assert.match(worker, /channel\.basic_get/);
  assert.doesNotMatch(worker, /start_consuming\(\)/);
  assert.match(worker, /for next_task in result\.get\("nextTasks"\)/);
  assert.match(worker, /publish_task\(channel, next_task\)/);
});

test('dispatcher rechecks quickly while a crawl backlog is draining', () => {
  assert.match(worker, /return False/);
  assert.match(worker, /min\(30, REFRESH_SECONDS\)/);
});

test('legacy in-process crawler stands down when the durable queue is configured', () => {
  assert.match(scheduler, /QUEUE_INTERNAL_KEY/);
  assert.match(scheduler, /ENABLE_LEGACY_LISTING_SCHEDULER/);
  assert.match(scheduler, /RabbitMQ queue owns crawl/);
});
