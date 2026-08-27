from pathlib import Path

path = Path('backend/src/postgres-search.js')
text = path.read_text()
text = text.replace(
    "import { pool } from './db.js';\n",
    "import { pool } from './db.js';\nimport {CITIES} from '@whiteslove/parsing-lexicon/geography';\n",
    1,
)

anchor = "const CURSOR_VERSION = 1;\n"
helper = '''const CURSOR_VERSION = 1;

function canonicalCityAliasRows(countries) {
  const allowed = new Set((countries || []).map((value) => String(value).toUpperCase()).filter(Boolean));
  const rows = new Map();
  const collisions = new Set();

  for (const city of CITIES) {
    const country = String(city?.country || '').toUpperCase();
    const canonical = String(city?.canonical || '').trim();
    if (!country || !canonical || (allowed.size && !allowed.has(country))) continue;

    const aliases = new Set([canonical]);
    for (const values of Object.values(city?.aliases || {})) {
      for (const alias of Array.isArray(values) ? values : [values]) {
        const value = String(alias || '').trim();
        if (value) aliases.add(value);
      }
    }

    for (const alias of aliases) {
      const normalized = alias.normalize('NFKC').toLowerCase();
      const key = `${country}\\u0000${normalized}`;
      const existing = rows.get(key);
      if (existing && existing.canonical !== canonical) {
        collisions.add(key);
        continue;
      }
      rows.set(key, {country, alias: normalized, canonical});
    }
  }

  for (const key of collisions) rows.delete(key);
  return [...rows.values()];
}
'''
if anchor not in text:
    raise SystemExit('cursor anchor missing')
text = text.replace(anchor, helper, 1)

count_anchor = "  const countSql = `SELECT COUNT(*)::int AS count FROM (${rankedSql}) l WHERE l.dedupe_rank = 1`;\n\n  const statsSql = `\n"
replacement = "  const countSql = `SELECT COUNT(*)::int AS count FROM (${rankedSql}) l WHERE l.dedupe_rank = 1`;\n\n  const statsParams = [...baseParams, JSON.stringify(canonicalCityAliasRows(countries))];\n  const cityAliasesParam = `$${statsParams.length}`;\n\n  const statsSql = `\n    WITH city_aliases AS MATERIALIZED (\n      SELECT country, alias, canonical\n      FROM jsonb_to_recordset(${cityAliasesParam}::jsonb) AS item(country text, alias text, canonical text)\n    ),\n"
if count_anchor not in text:
    raise SystemExit('stats anchor missing')
text = text.replace(count_anchor, replacement, 1)

old_classified = '''    WITH ranked AS MATERIALIZED (${rankedSql}),
    visible AS MATERIALIZED (SELECT * FROM ranked WHERE dedupe_rank = 1),
    classified AS MATERIALIZED (
      SELECT visible.*,
        CASE
          WHEN data @> '{"roomOnly":true}'::jsonb THEN 'roomRent'
          WHEN deal_type IN ('sale', 'longRent', 'shortRent') THEN deal_type
          ELSE 'unknown'
        END AS deal_key
      FROM visible
    ),'''
new_classified = '''    ranked AS MATERIALIZED (${rankedSql}),
    visible AS MATERIALIZED (SELECT * FROM ranked WHERE dedupe_rank = 1),
    classified AS MATERIALIZED (
      SELECT visible.*,
        COALESCE(city_alias.canonical, NULLIF(BTRIM(visible.city), '')) AS canonical_city,
        CASE
          WHEN data @> '{"roomOnly":true}'::jsonb THEN 'roomRent'
          WHEN deal_type IN ('sale', 'longRent', 'shortRent') THEN deal_type
          ELSE 'unknown'
        END AS deal_key
      FROM visible
      LEFT JOIN city_aliases city_alias
        ON city_alias.country = UPPER(visible.country)
       AND city_alias.alias = LOWER(BTRIM(visible.city))
    ),'''
if old_classified not in text:
    raise SystemExit('classified CTE missing')
text = text.replace(old_classified, new_classified, 1)

city_value = "        ('city', NULLIF(BTRIM(v.city), ''))," 
if city_value not in text:
    raise SystemExit('city geo value missing')
text = text.replace(city_value, "        ('city', v.canonical_city),", 1)
text = text.replace('pool.query(statsSql, baseParams)', 'pool.query(statsSql, statsParams)')
path.write_text(text)

test = Path('backend/test/postgres-search.integration.test.js')
source = test.read_text()
source = source.replace(
    "    listing('kyiv-200', 200, 'USD', 'Kyiv', true, 4),\n",
    "    listing('kyiv-200', 200, 'USD', 'Kyiv', true, 4),\n    listing('kyiv-uk-100', 100, 'USD', 'Київ', true, 6),\n    listing('kyiv-ru-300', 300, 'USD', 'Киев', true, 7),\n",
    1,
)
marker = "  const second = await searchPostgresListings({\n"
regression = '''  const canonicalStats = await searchPostgresListings({
    filters: {
      ...filters,
      city: '',
      cityAliases: [],
      priceMax: null,
      airConditioner: null,
      sources: ['pg-search-test'],
      statsOnly: true,
      limit: 1,
      offset: 0,
    },
    countries: ['UA'],
    rates: {USD: 1, UAH: 40},
  });
  const kyivStats = canonicalStats.statistics.geographies.city.find((row) => row.label === 'Kyiv');
  assert.deepEqual(kyivStats, {
    label: 'Kyiv',
    count: 3,
    priceCount: 3,
    medianUsd: 200,
    minUsd: 100,
    maxUsd: 300,
  });
  assert.equal(canonicalStats.statistics.geographies.city.some((row) => row.label === 'Киев' || row.label === 'Київ'), false);

'''
if marker not in source:
    raise SystemExit('test insertion marker missing')
source = source.replace(marker, regression + marker, 1)
test.write_text(source)
