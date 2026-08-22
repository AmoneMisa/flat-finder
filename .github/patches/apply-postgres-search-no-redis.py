from pathlib import Path
import json


def replace_once(text, old, new, name):
    if old not in text:
        raise SystemExit(f'missing patch anchor: {name}')
    return text.replace(old, new, 1)

# Share the existing PostgreSQL pool with the fast search and queue idempotency layers.
db_path = Path('backend/src/db.js')
db = db_path.read_text()
db = replace_once(db, 'const pool = new Pool({', 'export const pool = new Pool({', 'export db pool')
db_path.write_text(db)

server_path = Path('backend/src/server.js')
server = server_path.read_text()
server = replace_once(
    server,
    "import {closeDb, dbHealth, getAvailableListingLocations, getDbStats, initDb,} from './db.js';\n",
    "import {closeDb, dbHealth, getAvailableListingLocations, getDbStats, initDb,} from './db.js';\nimport {initPostgresSearchSchema, searchPostgresListings} from './postgres-search.js';\n",
    'postgres search import',
)
server = replace_once(
    server,
    "    limit: Math.min(num(q.limit) ?? 40, 60),\n",
    "    limit: Math.min(num(q.limit) ?? 40, 60),\n    cursor: q.cursor ? String(q.cursor) : '',\n",
    'cursor filter',
)
fast_path = r'''

  /*
   * Normal Flat Finder requests are served straight from PostgreSQL.
   * The crawler writes normalized rows continuously; the request path must not
   * deserialize country-wide Redis snapshots just to discard all but 20 rows.
   *
   * The legacy snapshot path below remains only as a safety fallback and for
   * user-supplied custom source URLs that are intentionally not persisted.
   */
  if (!filters.customSources.length) {
    if (force) {
      void refreshAll('manual').catch((err) => {
        console.warn('[postgres-search] background refresh failed:', err?.message ?? err);
      });
    }

    try {
      let searchError = null;
      const searchMatches = filters.query
        ? await searchListingMatches(filters.query, {
            countries: codes,
            sources: filters.sources,
          }).catch((err) => {
            searchError = err?.message ?? String(err);
            console.warn(`[elasticsearch] postgres search fallback: ${searchError}`);
            return null;
          })
        : null;

      let fxRates = null;
      try {
        fxRates = (await getRates()).rates;
      } catch {}

      const result = await searchPostgresListings({
        filters,
        countries: codes,
        rates: fxRates,
        searchMatches,
      });

      return res.json({
        count: result.count,
        degradedCountries: [],
        sourceCounts: {},
        sourceErrors: searchError
          ? [{ source: 'elasticsearch', error: searchError }]
          : [],
        warming: false,
        filters,
        searchEngine: filters.query
          ? (searchMatches ? 'elasticsearch+postgres' : 'postgres-fallback')
          : 'postgres',
        searchIndexedMatches: searchMatches?.total ?? null,
        searchTruncated: searchMatches?.truncated ?? false,
        queryMs: result.queryMs,
        nextCursor: result.nextCursor,
        listings: result.listings,
      });
    } catch (err) {
      // Deployment-safe fallback: if the new SQL path is temporarily broken,
      // keep the old snapshot implementation available instead of taking the
      // public search endpoint down.
      console.warn('[postgres-search] fast path failed, using legacy fallback:', err?.message ?? err);
    }
  }
'''
anchor = "    filters.cityAliases =\n        [...forms];\n  }\n\n  try {"
server = replace_once(
    server,
    anchor,
    "    filters.cityAliases =\n        [...forms];\n  }" + fast_path + "\n  try {",
    'fast path insertion',
)
server = replace_once(
    server,
    "async function start() {\n  await initDb();\n",
    "async function start() {\n  await initDb();\n  await initPostgresSearchSchema();\n",
    'search schema startup',
)
server = server.replace(
    "   * Пока выдача ещё работает через\n   * Redis/Postgres pipeline, ES не делаем\n   * причиной падения всего backend.\n",
    "   * PostgreSQL is the primary listing/search store. Elasticsearch remains\n   * an optional text-ranking layer and is not required for backend health.\n",
)
server_path.write_text(server)

compose_path = Path('docker-compose.yml')
compose = compose_path.read_text()
compose = compose.replace('      - REDIS_URL=redis://flat-finder-redis:6379\n', '')
compose = compose.replace('      flat-finder-redis:\n        condition: service_healthy\n', '')
redis_start = compose.find('  flat-finder-redis:\n')
if redis_start != -1:
    pg_start = compose.find('  flat-finder-postgres:\n', redis_start)
    if pg_start == -1:
        raise SystemExit('could not locate postgres service after redis')
    compose = compose[:redis_start] + compose[pg_start:]
compose_path.write_text(compose)

# Redis is no longer a runtime dependency. npm install --package-lock-only in the
# workflow updates package-lock.json consistently after this edit.
package_path = Path('backend/package.json')
package = json.loads(package_path.read_text())
package.get('dependencies', {}).pop('redis', None)
package_path.write_text(json.dumps(package, indent=2, ensure_ascii=False) + '\n')

queue_test_path = Path('backend/test/queue-crawl-stability.test.js')
queue_test = queue_test_path.read_text()
old = """test('crawl task execution is deduplicated per generation', () => {\n  assert.match(queueTasks, /executeQueueTaskOnce/);\n  assert.match(queueDedup, /task\\.crawlGeneration/);\n  assert.match(queueDedup, /NX: true/);\n  assert.match(queueDedup, /state: 'done'/);\n  assert.match(queueDedup, /deduplicated: true/);\n  assert.match(compose, /REDIS_URL=redis:\\/\\/flat-finder-redis:6379/);\n});"""
new = """test('crawl task execution is deduplicated per generation in PostgreSQL', () => {\n  assert.match(queueTasks, /executeQueueTaskOnce/);\n  assert.match(queueDedup, /task\\.crawlGeneration/);\n  assert.match(queueDedup, /crawl_task_runs/);\n  assert.match(queueDedup, /ON CONFLICT \\(task_key\\)/);\n  assert.match(queueDedup, /locked_until/);\n  assert.match(queueDedup, /status = 'done'/);\n  assert.match(queueDedup, /deduplicated: true/);\n  assert.doesNotMatch(compose, /flat-finder-redis:/);\n  assert.doesNotMatch(compose, /REDIS_URL=/);\n});"""
queue_test = replace_once(queue_test, old, new, 'queue dedup test')
queue_test_path.write_text(queue_test)
