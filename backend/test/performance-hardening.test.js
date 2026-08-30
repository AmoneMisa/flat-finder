import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';

async function source(path) {
  return readFile(new URL(path, import.meta.url), 'utf8');
}

test('hot listing filters use typed columns and normalized relations', async () => {
  const search = await source('../src/postgres-search.js');

  for (const column of [
    'l.bedrooms',
    'l.floor_number',
    'l.total_floors',
    'l.building_year',
    'l.commission_percent',
    'l.metro_distance_m',
  ]) {
    assert.match(search, new RegExp(column.replace('.', '\\.')));
  }
  assert.match(search, /FROM listing_location_terms term/u);
  assert.match(search, /FROM listing_nearby_places place/u);
  assert.match(search, /l\.lat BETWEEN/u);
  assert.match(search, /l\.lng BETWEEN/u);
  assert.match(search, /6371000 \* ACOS/u);
});

test('mobile subscription scans claim durable delivery before FCM send', async () => {
  const mobile = await source('../src/mobile-subscriptions.js');

  assert.match(mobile, /pg_try_advisory_lock/u);
  assert.match(mobile, /async function claimDelivery/u);
  assert.match(mobile, /ON CONFLICT \(device_id, kind, item_key\) DO UPDATE/u);
  assert.match(mobile, /status = 'sending'/u);
  assert.match(mobile, /lock_token = \$3::uuid/u);
  assert.match(mobile, /deliveryId:/u);
  assert.match(mobile, /UNNEST\(\$2::text\[\]\)/u);
  assert.doesNotMatch(mobile, /async function seen\(/u);
  assert.doesNotMatch(mobile, /async function delivered\(/u);
});

test('photo anti-fake uses indexed bands and one atomic cluster merge call', async () => {
  const antiFake = await source('../src/photo-antifake.js');

  assert.match(antiFake, /SUBSTRING\(perceptual_hash FROM 1 FOR 2\)/u);
  assert.match(antiFake, /SUBSTRING\(perceptual_hash FROM 15 FOR 2\)/u);
  assert.match(antiFake, /merge_listing_property_cluster\(\$1::jsonb, \$2::text\)/u);
  assert.doesNotMatch(antiFake, /PERCEPTUAL_CANDIDATE_LIMIT/u);
  assert.doesNotMatch(antiFake, /for \(const member of unique\)[\s\S]*INSERT INTO listing_property_clusters/u);
});

test('crawl queue batches inserts and rate-limits expired lease recovery', async () => {
  const queue = await source('../src/pgQueue.js');

  assert.match(queue, /jsonb_to_recordset\(\$1::jsonb\)/u);
  assert.match(queue, /ENQUEUE_BATCH_SIZE/u);
  assert.match(queue, /maybeRecoverExpiredTasks/u);
  assert.match(queue, /pg_try_advisory_xact_lock/u);
  assert.match(queue, /RECOVERY_INTERVAL_MS/u);
  assert.doesNotMatch(queue, /async function insertTask/u);
  assert.doesNotMatch(queue, /for \(const task of tasks \|\| \[\]\)[\s\S]*await insertTask/u);
});

test('performance migrations own materialization, relations, delivery leases and atomic clustering', async () => {
  const hot = await source('../migrations/024_hot_filter_columns.sql');
  const relations = await source('../migrations/025_search_relations.sql');
  const spatial = await source('../migrations/026_spatial_prefilter.sql');
  const delivery = await source('../migrations/027_mobile_delivery_outbox.sql');
  const bands = await source('../migrations/028_perceptual_hash_bands.sql');
  const clusters = await source('../migrations/029_atomic_property_cluster_merge.sql');
  const feed = await source('../migrations/030_public_feed_member_upsert.sql');

  assert.match(hot, /GENERATED ALWAYS AS/u);
  assert.match(hot, /listings_active_country_city_metro_distance_idx/u);
  assert.match(relations, /CREATE TABLE IF NOT EXISTS listing_location_terms/u);
  assert.match(relations, /CREATE TABLE IF NOT EXISTS listing_nearby_places/u);
  assert.match(relations, /CREATE TRIGGER listings_sync_search_relations/u);
  assert.match(spatial, /listings_active_country_geo_idx/u);
  assert.match(delivery, /mobile_deliveries_status_check/u);
  assert.match(delivery, /locked_until/u);
  assert.match(bands, /listing_photo_hashes_phash_band_8_idx/u);
  assert.match(clusters, /CREATE OR REPLACE FUNCTION merge_listing_property_cluster/u);
  assert.match(clusters, /pg_advisory_xact_lock/u);
  assert.match(clusters, /jsonb_to_recordset\(p_members\)/u);
  assert.match(feed, /ON CONFLICT \(listing_id\) DO UPDATE/u);
  assert.doesNotMatch(feed, /DELETE FROM listing_public_feed_members[\s\S]*INSERT INTO listing_public_feed_members/u);
});

test('hiring data reuses the main backend pool instead of opening another pool', async () => {
  const hiring = await source('../src/hiring-db.js');
  assert.match(hiring, /import \{pool\} from '\.\/db\.js'/u);
  assert.doesNotMatch(hiring, /new Pool\(/u);
  assert.doesNotMatch(hiring, /HIRING_PG_POOL_MAX/u);
});
