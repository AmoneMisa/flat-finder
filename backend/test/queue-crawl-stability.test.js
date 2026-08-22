import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const queueServer = readFileSync(new URL('../src/queue-task-server.js', import.meta.url), 'utf8');
const queueTasks = readFileSync(new URL('../src/queueTasks.js', import.meta.url), 'utf8');
const scheduler = readFileSync(new URL('../src/scheduler.js', import.meta.url), 'utf8');
const worker = readFileSync(new URL('../../queue-worker/worker.py', import.meta.url), 'utf8');

test('queue plan seeds one OLX page and lets successful tasks extend the chain', () => {
  assert.doesNotMatch(queueServer, /page\s*<=\s*5/);
  assert.match(queueServer, /page:\s*1/);
  assert.match(queueTasks, /pastCutoff/);
  assert.match(queueTasks, /rawCount\s*<=\s*0/);
  assert.match(queueTasks, /nextTasks:/);
  assert.match(queueTasks, /page:\s*nextPage/);
});

test('queue protocol survives page chaining and invalidates durable legacy backlog', () => {
  assert.match(queueServer, /QUEUE_PROTOCOL_VERSION\s*=\s*2/);
  assert.match(queueServer, /queueProtocol:\s*QUEUE_PROTOCOL_VERSION/);
  assert.match(queueTasks, /queueProtocol:\s*Number\(task\.queueProtocol\)/);
  assert.match(worker, /QUEUE_PROTOCOL_VERSION/);
  assert.match(worker, /dropped legacy task/);
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

test('dispatcher rechecks quickly while an old crawl backlog is draining', () => {
  assert.match(worker, /return False/);
  assert.match(worker, /min\(30, REFRESH_SECONDS\)/);
});

test('legacy in-process crawler stands down when the durable queue is configured', () => {
  assert.match(scheduler, /QUEUE_INTERNAL_KEY/);
  assert.match(scheduler, /ENABLE_LEGACY_LISTING_SCHEDULER/);
  assert.match(scheduler, /RabbitMQ queue owns crawl/);
});
