from pathlib import Path

path = Path('backend/test/telegram-room-dedupe.test.js')
source = path.read_text()
source = source.replace(
    "const postgresSearch = await readFile(new URL('../src/postgres-search.js', import.meta.url), 'utf8');\n",
    "const postgresSearch = await readFile(new URL('../src/postgres-search.js', import.meta.url), 'utf8');\nconst dedupeMigration = await readFile(new URL('../migrations/010_persisted_dedupe_key.sql', import.meta.url), 'utf8');\n",
    1,
)
old = """test('PostgreSQL feed consumes photo fingerprint keys, falls back to content, and keeps exact-id lookup', () => {\n  assert.match(postgresSearch, /'telegram:photos:' \\|\\| MD5/);\n  assert.match(postgresSearch, /data->>'photoFingerprintKey'/);\n  assert.match(postgresSearch, /LENGTH\\(\\$\\{telegramPhotoKey\\}\\) >= 129/);\n  assert.match(postgresSearch, /'telegram:content:' \\|\\| MD5/);\n  assert.match(postgresSearch, /LENGTH\\(\\$\\{description\\}\\) >= 40/);\n  assert.match(postgresSearch, /const dedupeEnabled = !filters\\.listingId/);\n});\n"""
new = """test('PostgreSQL feed consumes persisted Telegram fingerprints and keeps exact-id lookup', () => {\n  assert.match(dedupeMigration, /'telegram:photos:' \\|\\| MD5/);\n  assert.match(dedupeMigration, /p_data->>'photoFingerprintKey'/);\n  assert.match(dedupeMigration, /LENGTH\\(telegram_photo_key\\) >= 129/);\n  assert.match(dedupeMigration, /'telegram:content:' \\|\\| MD5/);\n  assert.match(dedupeMigration, /LENGTH\\(description\\) >= 40/);\n  assert.match(postgresSearch, /dedupeEnabled \\? 'l\\.dedupe_key'/);\n  assert.match(postgresSearch, /const dedupeEnabled = !filters\\.listingId/);\n});\n"""
assert old in source
path.write_text(source.replace(old, new, 1))
