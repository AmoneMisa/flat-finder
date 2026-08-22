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

test('RabbitMQ worker heartbeat exceeds the synchronous task timeout', () => {
  assert.match(worker, /RABBITMQ_HEARTBEAT/);
  assert.match(worker, /max\(240,/);
  assert.match(worker, /for next_task in result\.get\("nextTasks"\)/);
  assert.match(worker, /publish_task\(ch, next_task\)/);
  assert.match(worker, /ch\.basic_ack\(method\.delivery_tag\)/);
});

test('legacy in-process crawler stands down when the durable queue is configured', () => {
  assert.match(scheduler, /QUEUE_INTERNAL_KEY/);
  assert.match(scheduler, /ENABLE_LEGACY_LISTING_SCHEDULER/);
  assert.match(scheduler, /RabbitMQ queue owns crawl/);
});
