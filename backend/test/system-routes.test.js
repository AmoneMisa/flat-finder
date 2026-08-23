import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

import { installSystemRoutes } from '../src/system-routes.js';

const systemRoutesSource = readFileSync(
  new URL('../src/system-routes.js', import.meta.url),
  'utf8',
);

function fakeApp() {
  const routes = new Map();
  return {
    locals: {},
    routes,
    get(path, handler) {
      routes.set(`GET ${path}`, handler);
    },
    post(path, handler) {
      routes.set(`POST ${path}`, handler);
    },
  };
}

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

function withEnv(values, fn) {
  const previous = {};
  for (const [key, value] of Object.entries(values)) {
    previous[key] = process.env[key];
    if (value == null) delete process.env[key];
    else process.env[key] = value;
  }
  try {
    return fn();
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

test('system routes expose health publicly and operations only under /internal', () => {
  const app = fakeApp();
  installSystemRoutes(app);

  assert.ok(app.routes.has('GET /health'));
  assert.ok(app.routes.has('GET /internal/db-stats'));
  assert.ok(app.routes.has('GET /internal/refresh'));
  assert.ok(app.routes.has('POST /internal/refresh'));
  assert.equal(app.routes.has('GET /api/db-stats'), false);
  assert.equal(app.routes.has('GET /api/refresh'), false);
  assert.equal(app.routes.has('POST /api/refresh'), false);
});

test('operational routes reject unauthenticated requests before touching dependencies', async () => {
  const app = fakeApp();
  installSystemRoutes(app);

  await withEnv({ OPS_INTERNAL_KEY: null, QUEUE_INTERNAL_KEY: null }, async () => {
    const handler = app.routes.get('GET /internal/db-stats');
    const res = responseRecorder();
    await handler({ get: () => '' }, res);
    assert.equal(res.statusCode, 503);
  });

  await withEnv({ OPS_INTERNAL_KEY: 'ops-secret-123456', QUEUE_INTERNAL_KEY: null }, async () => {
    const handler = app.routes.get('POST /internal/refresh');
    const res = responseRecorder();
    await handler({ get: () => 'wrong-key' }, res);
    assert.equal(res.statusCode, 401);
  });
});

test('operational dependency failures stay JSON instead of falling through Express defaults', () => {
  assert.match(systemRoutesSource, /app\.post\('\/internal\/refresh'/);
  assert.match(systemRoutesSource, /res\.status\(500\)\.json\(\{/);
  assert.match(systemRoutesSource, /ok: false/);
  assert.match(systemRoutesSource, /error: err\?\.message \?\? String\(err\)/);
});
