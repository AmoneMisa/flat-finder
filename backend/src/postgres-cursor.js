import {createHash} from 'node:crypto';

const CURSOR_VERSION = 1;
const BIGINT_MAX = 9_223_372_036_854_775_807n;
const NON_SEMANTIC_FILTER_KEYS = new Set([
  'cursor',
  'offset',
  'limit',
  'sort',
  'includeStats',
  'statsOnly',
  'mapOnly',
]);

function stableValue(value) {
  if (Array.isArray(value)) {
    return value
      .map(stableValue)
      .sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
  }
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, stableValue(value[key])])
        .filter(([, item]) => item !== undefined),
    );
  }
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (value === undefined) return undefined;
  return value;
}

export function postgresCursorScope({filters, countries}) {
  const semanticFilters = {};
  for (const key of Object.keys(filters || {}).sort()) {
    if (NON_SEMANTIC_FILTER_KEYS.has(key)) continue;
    const value = stableValue(filters[key]);
    if (value !== undefined) semanticFilters[key] = value;
  }
  const normalizedCountries = [...new Set((countries || [])
    .map((value) => String(value).trim().toUpperCase())
    .filter(Boolean))]
    .sort();

  return createHash('sha256')
    .update(JSON.stringify({countries: normalizedCountries, filters: semanticFilters}))
    .digest('base64url')
    .slice(0, 24);
}

export function decodePostgresCursor(value) {
  if (!value) return null;
  try {
    const parsed = JSON.parse(Buffer.from(String(value), 'base64url').toString('utf8'));
    return parsed?.v === CURSOR_VERSION && parsed && typeof parsed === 'object'
      ? parsed
      : null;
  } catch {
    return null;
  }
}

function validBigintId(value) {
  const text = String(value ?? '');
  if (!/^[1-9]\d*$/.test(text)) return null;
  try {
    const parsed = BigInt(text);
    return parsed <= BIGINT_MAX ? text : null;
  } catch {
    return null;
  }
}

export function resolvePostgresCursor(cursor, {sort, scope}) {
  if (!cursor || cursor.sort !== sort) return null;

  const hasExplicitScope = Object.prototype.hasOwnProperty.call(cursor, 's');
  if (hasExplicitScope && cursor.s !== scope) return null;

  const id = validBigintId(cursor.id);
  if (!id) return null;

  let time = null;
  if (cursor.t) {
    const milliseconds = Date.parse(String(cursor.t));
    if (!Number.isFinite(milliseconds)) return null;
    time = new Date(milliseconds).toISOString();
  }

  const count = Number(cursor.c);
  return {
    id,
    time,
    trustedScope: hasExplicitScope && cursor.s === scope,
    count: Number.isSafeInteger(count) && count >= 0 ? count : null,
  };
}

export function encodePostgresCursor({sort, time, id, count, scope}) {
  return Buffer.from(JSON.stringify({
    v: CURSOR_VERSION,
    sort,
    t: time || null,
    id: String(id),
    c: count,
    s: scope,
  }), 'utf8').toString('base64url');
}
