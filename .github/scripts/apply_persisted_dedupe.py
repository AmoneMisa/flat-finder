from pathlib import Path

SEARCH = Path('backend/src/postgres-search.js')
CI = Path('.github/workflows/backend-ci.yml')
MIGRATION = Path('backend/migrations/010_persisted_dedupe_key.sql')
TEST = Path('backend/test/persisted-dedupe-key.integration.test.js')

search = SEARCH.read_text()
start = search.index('function olxPhotoSql(')
end = search.index('export async function searchPostgresListings(')
search = search[:start] + search[end:]
needle = "  const dedupeKey = listingDedupeSql('l');\n"
assert search.count(needle) == 1, search.count(needle)
search = search.replace(needle, '', 1)
needle = "${dedupeEnabled ? dedupeKey : `CONCAT_WS(':', LOWER(l.source), UPPER(l.country), l.source_id)`} AS dedupe_key"
replacement = "${dedupeEnabled ? 'l.dedupe_key' : `CONCAT_WS(':', LOWER(l.source), UPPER(l.country), l.source_id)`} AS dedupe_key"
assert search.count(needle) == 1, search.count(needle)
search = search.replace(needle, replacement, 1)
assert 'listingDedupeSql' not in search
assert 'olxPhotoSql' not in search
SEARCH.write_text(search)

MIGRATION.write_text(r'''-- Persist the exact public-feed deduplication fingerprint so reads do not
-- repeatedly normalize photos/title/description and calculate MD5 for every
-- matching row. The generated column keeps ingestion/update semantics atomic:
-- whenever a fingerprint input changes PostgreSQL recomputes the stored key.
CREATE OR REPLACE FUNCTION compute_listing_dedupe_key(
  p_source TEXT,
  p_country TEXT,
  p_source_id TEXT,
  p_title TEXT,
  p_description TEXT,
  p_property_type TEXT,
  p_deal_type TEXT,
  p_city TEXT,
  p_price DOUBLE PRECISION,
  p_currency TEXT,
  p_rooms INTEGER,
  p_area_sqm DOUBLE PRECISION,
  p_data JSONB
)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
AS $$
  WITH normalized AS (
    SELECT
      LOWER(COALESCE(p_source, '')) AS source,
      UPPER(COALESCE(p_country, '')) AS country,
      COALESCE(p_source_id, '') AS source_id,
      LOWER(COALESCE(p_city, '')) AS city,
      COALESCE(p_deal_type, '') AS deal_type,
      COALESCE(p_property_type, '') AS property_type,
      COALESCE(p_price::text, '') AS price,
      UPPER(COALESCE(p_currency, '')) AS currency,
      COALESCE(p_rooms::text, '') AS rooms,
      COALESCE(ROUND(p_area_sqm::numeric, 1)::text, '') AS area_sqm,
      LOWER(REGEXP_REPLACE(BTRIM(COALESCE(p_title, '')), '\s+', ' ', 'g')) AS title,
      LOWER(REGEXP_REPLACE(BTRIM(COALESCE(p_description, '')), '\s+', ' ', 'g')) AS description,
      LOWER(REGEXP_REPLACE(SPLIT_PART(COALESCE(
        CASE
          WHEN jsonb_typeof(p_data->'photos'->0) = 'string' THEN p_data->'photos'->>0
          WHEN jsonb_typeof(p_data->'photos'->0) = 'object' THEN COALESCE(
            p_data->'photos'->0->>'link',
            p_data->'photos'->0->>'url',
            p_data->'photos'->0->>'src',
            ''
          )
          ELSE ''
        END,
        ''
      ), '?', 1), ';s=.*$', '')) AS photo0,
      LOWER(REGEXP_REPLACE(SPLIT_PART(COALESCE(
        CASE
          WHEN jsonb_typeof(p_data->'photos'->1) = 'string' THEN p_data->'photos'->>1
          WHEN jsonb_typeof(p_data->'photos'->1) = 'object' THEN COALESCE(
            p_data->'photos'->1->>'link',
            p_data->'photos'->1->>'url',
            p_data->'photos'->1->>'src',
            ''
          )
          ELSE ''
        END,
        ''
      ), '?', 1), ';s=.*$', '')) AS photo1,
      COALESCE(p_data->>'photoFingerprintKey', '') AS telegram_photo_key
  )
  SELECT CASE
    WHEN source = 'olx'
      AND LENGTH(photo0) >= 24
      AND LENGTH(photo1) >= 24
      AND photo0 <> photo1
      THEN 'olx:photos:' || MD5(CONCAT_WS('|', country, photo0, photo1))
    WHEN source = 'olx'
      AND LENGTH(description) >= 120
      THEN 'olx:content:' || MD5(CONCAT_WS('|',
        country,
        city,
        deal_type,
        property_type,
        price,
        currency,
        rooms,
        area_sqm,
        title,
        description
      ))
    WHEN source = 'telegram'
      AND LENGTH(telegram_photo_key) >= 129
      THEN 'telegram:photos:' || MD5(CONCAT_WS('|', country, telegram_photo_key))
    WHEN source = 'telegram'
      AND LENGTH(description) >= 40
      THEN 'telegram:content:' || MD5(CONCAT_WS('|',
        country,
        city,
        deal_type,
        property_type,
        price,
        currency,
        rooms,
        area_sqm,
        title,
        description
      ))
    ELSE CONCAT_WS(':', source, country, source_id)
  END
  FROM normalized;
$$;

ALTER TABLE listings
  ADD COLUMN IF NOT EXISTS dedupe_key TEXT
  GENERATED ALWAYS AS (
    compute_listing_dedupe_key(
      source,
      country,
      source_id,
      title,
      description,
      property_type,
      deal_type,
      city,
      price,
      currency,
      rooms,
      area_sqm,
      data
    )
  ) STORED;

ALTER TABLE listings
  ALTER COLUMN dedupe_key SET NOT NULL;

-- Supports the ROW_NUMBER/PARTITION BY dedupe_key visibility contract used by
-- both ordinary feed counts and exact stats. Country-specific recency indexes
-- remain useful for the initial filter/order path.
CREATE INDEX IF NOT EXISTS listings_active_dedupe_created_idx
  ON listings(dedupe_key, created_at DESC, id DESC)
  WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS listings_active_country_dedupe_created_idx
  ON listings(country, dedupe_key, created_at DESC, id DESC)
  WHERE active = TRUE;
''')

TEST.write_text(r'''import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import pg from 'pg';

const {Client} = pg;
const connectionString = process.env.TEST_POSTGRES_URL || '';
const migrationsDir = new URL('../migrations/', import.meta.url);

const md5 = (value) => createHash('md5').update(value).digest('hex');
const cleanText = (value) => String(value ?? '').trim().replace(/\s+/gu, ' ').toLowerCase();
const cleanPhoto = (value) => {
  let raw = '';
  if (typeof value === 'string') raw = value;
  else if (value && typeof value === 'object') raw = value.link ?? value.url ?? value.src ?? '';
  return String(raw).split('?', 1)[0].replace(/;s=.*$/u, '').toLowerCase();
};
const joined = (...parts) => parts.map((part) => String(part ?? '')).join('|');
const areaText = (value) => value == null ? '' : Number(value).toFixed(1);

function legacyKey(row) {
  const source = String(row.source ?? '').toLowerCase();
  const country = String(row.country ?? '').toUpperCase();
  const title = cleanText(row.title);
  const description = cleanText(row.description);
  const photos = Array.isArray(row.data?.photos) ? row.data.photos : [];
  const photo0 = cleanPhoto(photos[0]);
  const photo1 = cleanPhoto(photos[1]);

  if (source === 'olx' && photo0.length >= 24 && photo1.length >= 24 && photo0 !== photo1) {
    return `olx:photos:${md5(joined(country, photo0, photo1))}`;
  }

  const contentParts = [
    country,
    String(row.city ?? '').toLowerCase(),
    row.deal_type ?? '',
    row.property_type ?? '',
    row.price == null ? '' : String(row.price),
    String(row.currency ?? '').toUpperCase(),
    row.rooms == null ? '' : String(row.rooms),
    areaText(row.area_sqm),
    title,
    description,
  ];

  if (source === 'olx' && description.length >= 120) {
    return `olx:content:${md5(joined(...contentParts))}`;
  }

  const telegramPhotoKey = String(row.data?.photoFingerprintKey ?? '');
  if (source === 'telegram' && telegramPhotoKey.length >= 129) {
    return `telegram:photos:${md5(joined(country, telegramPhotoKey))}`;
  }
  if (source === 'telegram' && description.length >= 40) {
    return `telegram:content:${md5(joined(...contentParts))}`;
  }

  return `${source}:${country}:${row.source_id}`;
}

async function migration(name) {
  return readFile(new URL(name, migrationsDir), 'utf8');
}

test('persisted dedupe key is equivalent to the previous runtime fingerprint', {skip: !connectionString}, async () => {
  const client = new Client({connectionString});
  await client.connect();
  try {
    await client.query('DROP TABLE IF EXISTS listings CASCADE');
    await client.query(await migration('001_baseline_listings.sql'));
    await client.query(await migration('010_persisted_dedupe_key.sql'));

    const vectors = [
      {
        source: 'olx', country: 'UA', source_id: 'photo-1', title: '  Nice   Flat ', description: 'short',
        property_type: 'flat', deal_type: 'sale', city: 'Kyiv', price: 80000, currency: 'USD', rooms: 2, area_sqm: 42.5,
        data: {photos: ['https://img.example.com/aaaaaaaaaaaa/one.jpg?x=1', {url: 'HTTPS://IMG.EXAMPLE.COM/BBBBBBBBBBBB/two.jpg;s=640x480'}]},
      },
      {
        source: 'olx', country: 'UA', source_id: 'content-1', title: ' Spacious   apartment ',
        description: 'Very long listing description '.repeat(7), property_type: 'flat', deal_type: 'longRent', city: 'Odesa',
        price: 500, currency: 'USD', rooms: 2, area_sqm: 60, data: {photos: []},
      },
      {
        source: 'telegram', country: 'UZ', source_id: 'telegram-photo', title: 'Flat', description: 'tiny',
        property_type: 'flat', deal_type: 'longRent', city: 'Tashkent', price: 700, currency: 'USD', rooms: 3, area_sqm: 75,
        data: {photoFingerprintKey: 'x'.repeat(129)},
      },
      {
        source: 'telegram', country: 'UZ', source_id: 'telegram-content', title: '  Kvartira  ',
        description: 'Long enough Telegram housing description with repeated   spaces and details.',
        property_type: 'flat', deal_type: 'longRent', city: 'Tashkent', price: 600, currency: 'USD', rooms: 2, area_sqm: 55.2,
        data: {},
      },
      {
        source: 'facebook', country: 'RO', source_id: 'fallback-1', title: 'Home', description: 'short',
        property_type: 'house', deal_type: 'sale', city: 'Cluj-Napoca', price: 100000, currency: 'EUR', rooms: 4, area_sqm: 120,
        data: {},
      },
    ];

    for (const row of vectors) {
      await client.query(`
        INSERT INTO listings (
          source, country, source_id, title, description, property_type, deal_type,
          city, price, currency, rooms, area_sqm, data, created_at
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13::jsonb,NOW())
      `, [
        row.source, row.country, row.source_id, row.title, row.description, row.property_type, row.deal_type,
        row.city, row.price, row.currency, row.rooms, row.area_sqm, JSON.stringify(row.data),
      ]);
    }

    const result = await client.query('SELECT source_id, dedupe_key FROM listings ORDER BY id');
    assert.deepEqual(result.rows.map((row) => row.dedupe_key), vectors.map(legacyKey));

    const before = result.rows.find((row) => row.source_id === 'telegram-content').dedupe_key;
    vectors[3].description += ' changed';
    await client.query('UPDATE listings SET description = $1 WHERE source_id = $2', [vectors[3].description, vectors[3].source_id]);
    const after = await client.query('SELECT dedupe_key FROM listings WHERE source_id = $1', [vectors[3].source_id]);
    assert.equal(after.rows[0].dedupe_key, legacyKey(vectors[3]));
    assert.notEqual(after.rows[0].dedupe_key, before, 'stored generated key must refresh when fingerprint inputs change');
  } finally {
    await client.end();
  }
});

test('listing reads use persisted dedupe keys while stats preserve exact visibility semantics', async () => {
  const search = await readFile(new URL('../src/postgres-search.js', import.meta.url), 'utf8');
  const migrationSql = await migration('010_persisted_dedupe_key.sql');

  assert.match(search, /dedupeEnabled \? 'l\.dedupe_key'/);
  assert.match(search, /PARTITION BY filtered\.dedupe_key/);
  assert.match(search, /SELECT COUNT\(\*\)::int FROM visible/);
  assert.match(search, /duplicatesRejected/);
  assert.doesNotMatch(search, /function listingDedupeSql/);
  assert.doesNotMatch(search, /function olxPhotoSql/);

  assert.match(migrationSql, /GENERATED ALWAYS AS/);
  assert.match(migrationSql, /compute_listing_dedupe_key/);
  assert.match(migrationSql, /listings_active_dedupe_created_idx/);
  assert.match(migrationSql, /listings_active_country_dedupe_created_idx/);
});
''')

ci = CI.read_text()
marker = '    runs-on: ubuntu-latest\n'
assert ci.count(marker) == 1, ci.count(marker)
services = '''    services:\n      postgres:\n        image: postgres:18-alpine\n        env:\n          POSTGRES_USER: flatfinder\n          POSTGRES_PASSWORD: flatfinder\n          POSTGRES_DB: flatfinder\n        ports:\n          - 5432:5432\n        options: >-\n          --health-cmd "pg_isready -U flatfinder -d flatfinder"\n          --health-interval 5s\n          --health-timeout 5s\n          --health-retries 10\n    env:\n      TEST_POSTGRES_URL: postgresql://flatfinder:flatfinder@127.0.0.1:5432/flatfinder\n'''
ci = ci.replace(marker, marker + services, 1)
CI.write_text(ci)
