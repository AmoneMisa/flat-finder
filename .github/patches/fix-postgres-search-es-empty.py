from pathlib import Path


def replace_once(text, old, new, name):
    if old not in text:
        raise SystemExit(f'missing patch anchor: {name}')
    return text.replace(old, new, 1)

path = Path('backend/src/postgres-search.js')
text = path.read_text()
text = replace_once(
    text,
    '  const matchRows = normalizeMatchRows(searchMatches);\n  let from = \'FROM listings l\';\n',
    '  const matchRows = normalizeMatchRows(searchMatches);\n  const elasticsearchAuthoritative = searchMatches != null;\n  let from = \'FROM listings l\';\n',
    'authoritative ES marker',
)
text = replace_once(
    text,
    "  const where = ['l.active = TRUE'];\n",
    "  const where = ['l.active = TRUE'];\n  if (elasticsearchAuthoritative && matchRows.length === 0) where.push('FALSE');\n",
    'zero ES matches',
)
text = replace_once(
    text,
    '  if (filters.query && !matchRows.length) {\n',
    '  if (filters.query && !elasticsearchAuthoritative) {\n',
    'fallback only when ES failed',
)
text = replace_once(
    text,
    "    searchPath: searchMatches?.rank?.size ? 'postgres+elasticsearch' : 'postgres',\n",
    "    searchPath: searchMatches ? 'postgres+elasticsearch' : 'postgres',\n",
    'search path marker',
)
path.write_text(text)

test_path = Path('backend/test/postgres-search.integration.test.js')
test = test_path.read_text()
anchor = """  assert.equal(second.listings.length, 1);\n  assert.equal(second.listings[0].id, 'uah-10000');\n\n  await pool.query(`DELETE FROM listings WHERE source = 'pg-search-test'`);\n"""
replacement = """  assert.equal(second.listings.length, 1);\n  assert.equal(second.listings[0].id, 'uah-10000');\n\n  const noEsMatches = await searchPostgresListings({\n    filters: { ...filters, query: 'Test', cursor: '', offset: 0 },\n    countries: ['UA'],\n    rates: { USD: 1, UAH: 40 },\n    searchMatches: { rank: new Map(), scores: new Map(), total: 0, truncated: false },\n  });\n  assert.equal(noEsMatches.count, 0);\n  assert.equal(noEsMatches.listings.length, 0);\n\n  await pool.query(`DELETE FROM listings WHERE source = 'pg-search-test'`);\n"""
test = replace_once(test, anchor, replacement, 'ES zero-match regression')
test_path.write_text(test)
