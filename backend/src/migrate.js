import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const { Pool } = pg;
const migrationsDir = fileURLToPath(new URL('../migrations/', import.meta.url));

const pool = new Pool({
  host: process.env.PGHOST || 'flat-finder-postgres',
  port: Number(process.env.PGPORT) || 5432,
  database: process.env.POSTGRES_DB || 'flatfinder',
  user: process.env.POSTGRES_USER || 'flatfinder',
  password: process.env.POSTGRES_PASSWORD,
  max: 1,
  connectionTimeoutMillis: 10_000,
});

async function runMigrations() {
  const client = await pool.connect();
  try {
    await client.query("SELECT pg_advisory_lock(hashtext('flat_finder_migrations'))");
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    const appliedResult = await client.query('SELECT version FROM schema_migrations');
    const applied = new Set(appliedResult.rows.map((row) => row.version));
    const files = (await readdir(migrationsDir))
      .filter((name) => /^\d+.*\.sql$/.test(name))
      .sort();

    for (const file of files) {
      if (applied.has(file)) continue;
      const sql = await readFile(new URL(`../migrations/${file}`, import.meta.url), 'utf8');

      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations(version) VALUES ($1)', [file]);
        await client.query('COMMIT');
        console.log(`[migrate] applied ${file}`);
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      }
    }
  } finally {
    await client.query("SELECT pg_advisory_unlock(hashtext('flat_finder_migrations'))").catch(() => {});
    client.release();
  }
}

runMigrations()
  .then(() => pool.end())
  .catch(async (error) => {
    console.error('[migrate] failed:', error?.stack || error?.message || error);
    await pool.end().catch(() => {});
    process.exitCode = 1;
  });
