import assert from 'node:assert/strict';
import test from 'node:test';

import {closeDb, pool} from '../src/db.js';
import {assertDatabaseReady} from '../src/db-ready.js';

const enabled = process.env.TEST_POSTGRES_SEARCH === '1';

async function column(schema, table, name) {
  const result = await pool.query(`
    SELECT data_type, udt_name, character_maximum_length
    FROM information_schema.columns
    WHERE table_schema = $1
      AND table_name = $2
      AND column_name = $3
  `, [schema, table, name]);
  assert.equal(result.rows.length, 1, `${schema}.${table}.${name} must exist`);
  return result.rows[0];
}

function assertVarchar(actual, length) {
  assert.equal(actual.data_type, 'character varying');
  assert.equal(Number(actual.character_maximum_length), length);
}

test('short relational fields use bounded varchar while external/free-form identifiers stay text', {skip: !enabled}, async () => {
  await assertDatabaseReady();

  try {
    assertVarchar(await column('public', 'listings', 'city'), 160);
    assertVarchar(await column('public', 'listings', 'district'), 160);
    assertVarchar(await column('public', 'listings', 'currency'), 8);
    assert.equal((await column('public', 'listings', 'source_id')).data_type, 'text');
    assert.equal((await column('public', 'listings', 'description')).data_type, 'text');

    assertVarchar(await column('public', 'crawl_tasks', 'type'), 64);
    assertVarchar(await column('public', 'crawl_tasks', 'country'), 8);
    assertVarchar(await column('public', 'crawl_tasks', 'status'), 16);
    assert.equal((await column('public', 'crawl_tasks', 'lock_token')).udt_name, 'uuid');
    assert.equal((await column('public', 'crawl_tasks', 'task_key')).data_type, 'text');

    assertVarchar(await column('public', 'places', 'city'), 160);
    assertVarchar(await column('public', 'places', 'name'), 255);
    assert.equal((await column('public', 'places', 'external_id')).data_type, 'text');

    assertVarchar(await column('public', 'learned_geo', 'entity_type'), 64);
    assertVarchar(await column('public', 'learned_geo', 'provider'), 64);
    assert.equal((await column('public', 'learned_geo', 'provider_id')).data_type, 'text');
    assert.equal((await column('public', 'learned_geo', 'query_text')).data_type, 'text');

    assertVarchar(await column('public', 'listing_property_clusters', 'cluster_id'), 128);
    assertVarchar(await column('public', 'listing_location_terms', 'term_type'), 64);
    assertVarchar(await column('public', 'listing_location_terms', 'normalized_name'), 255);
    assertVarchar(await column('public', 'listing_nearby_places', 'kind'), 64);

    assertVarchar(await column('subscriptions', 'mobile_subscriptions', 'name'), 120);
    assert.equal((await column('subscriptions', 'mobile_devices', 'push_token')).data_type, 'text');
    assert.equal((await column('subscriptions', 'mobile_deliveries', 'item_key')).data_type, 'text');
  } finally {
    await closeDb();
  }
});
