import {createHash} from 'node:crypto';

const CURSOR_VERSION = 1;
const SCOPE_VERSION = 1;
const NON_SEMANTIC_FILTER_KEYS = new Set([
  'cursor',
  'offset',
  'limit',
  'includeStats',
  'statsOnly',
  'mapOnly',
]);

function normalizeScopeValue(value) {
  if (value === undefined) return undefined;
  if (value === null || typeof value === 'boolean' || typeof value === 'string') return value;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (Array.isArray(value)) {
    return value
      .map(normalizeScopeValue)
      .filter((item) => item !== undefined)
      .sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
  }
  if (typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .filter((key) => value[key] !== undefined)
        .map((key) => [key, normalizeScopeValue(value[key])]),
    );
  }
  return String(value);
}

function decodeCursor(value) {
  if (!value) return null;
  try {
    const parsed = JSON.parse(Buffer.from(String(value), 'base64url').toString('utf8'));
    return parsed?.v === CURSOR_VERSION ? parsed : null;
  } catch {
    return null;
  }
}

function encodeCursor(value) {
  return Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');
}

export function searchCursorScope(filters = {}, countries = []) {
  const semanticFilters = {};
  for (const key of Object.keys(filters || {}).sort()) {
    if (NON_SEMANTIC_FILTER_KEYS.has(key) || filters[key] === undefined) continue;
    semanticFilters[key] = normalizeScopeValue(filters[key]);
  }

  const normalizedCountries = [...new Set((countries || [])
    .map((value) => String(value).trim().toUpperCase())
    .filter(Boolean))]
    .sort();

  return createHash('sha256')
    .update(JSON.stringify({v: SCOPE_VERSION, countries: normalizedCountries, filters: semanticFilters}))
    .digest('base64url')
    .slice(0, 22);
}

export function prepareCursorForScope(value, scope) {
  if (!value) return '';
  const parsed = decodeCursor(value);
  if (!parsed) return '';

  if (parsed.s != null) {
    return parsed.s === scope ? String(value) : '';
  }

  // Legacy v1 cursors remain usable as positional cursors, but their carried
  // total predates scope binding and therefore cannot be trusted for a new
  // request. Removing `c` forces the core query to calculate the count once.
  const {c: _legacyCount, ...legacyCursor} = parsed;
  return encodeCursor(legacyCursor);
}

export function attachScopeToCursor(value, scope) {
  if (!value) return null;
  const parsed = decodeCursor(value);
  if (!parsed) return value;
  return encodeCursor({...parsed, s: scope});
}
