import {
  ADDRESS_TERMS,
  APPLIANCE_TERMS,
  DEAL_TYPES,
  DEPOSIT_TERMS,
  HOUSING_OCCUPANCY_TYPES,
  aliasesOf,
  canonicalAnyCity,
  canonicalCountryCode,
  escapeRegex,
  findCanonical,
  normalizeUnicode,
} from '@whiteslove/parsing-lexicon';

const values = (entry) => [entry?.canonical, ...aliasesOf(entry)].filter(Boolean);
const loosePart = (value) => escapeRegex(normalizeUnicode(value).trim())
  .replace(/[\s\-–—'’‘`ʻʼ]+/g, "[\\s\\-–—'’‘`ʻʼ]*");
const alternatives = (entries) => [...new Set(entries.flatMap(values))]
  .sort((a, b) => String(b).length - String(a).length)
  .map(loosePart)
  .join('|');

const addressLabelPart = alternatives([ADDRESS_TERMS.label]);
const streetMarkerPart = alternatives([
  ADDRESS_TERMS.street,
  ADDRESS_TERMS.avenue,
  ADDRESS_TERMS.neighborhood,
  ADDRESS_TERMS.residentialComplex,
]);
const addressLabelRe = new RegExp(`(?:${addressLabelPart})\\s*[:\\-–—]\\s*([^\\n]{3,100})`, 'iu');
const markedStreetRe = new RegExp(
  `((?:${streetMarkerPart})\\.?\\s+[^\\n,;]{2,70}(?:,?\\s*(?:${alternatives([ADDRESS_TERMS.house])})?\\.?\\s*\\d+[\\p{L}0-9/-]*)?)`,
  'iu',
);

function cleanAddress(value) {
  return String(value || '')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/[.;,]+$/, '');
}

export function parseCanonicalCountryCode(value) {
  return canonicalCountryCode(value) || String(value || '').trim().toUpperCase() || null;
}

export function parseCanonicalCity(countryCode, value) {
  if (!value) return '';
  return canonicalAnyCity(value, countryCode) || String(value).trim();
}

export function parseLexiconDealType(text) {
  return findCanonical(text, DEAL_TYPES, { partial: true })?.canonical || null;
}

export function parseHousingOccupancyType(text) {
  return findCanonical(text, HOUSING_OCCUPANCY_TYPES, { partial: true })?.canonical || null;
}

export function parseDepositKind(text) {
  if (!text) return null;
  for (const key of ['noDeposit', 'firstAndLastMonth', 'advance', 'refundable', 'deposit']) {
    const entry = DEPOSIT_TERMS[key];
    if (entry && findCanonical(text, [entry], { partial: true })) return entry.canonical;
  }
  return null;
}

export function parseAppliances(text) {
  if (!text) return [];
  const out = [];
  for (const entry of Object.values(APPLIANCE_TERMS)) {
    if (findCanonical(text, [entry], { partial: true })) out.push(entry.canonical);
  }
  return [...new Set(out)];
}

export function parseLexiconAddress(text, canonicalStreet = null) {
  if (!text) return canonicalStreet || null;
  const labeled = String(text).match(addressLabelRe);
  if (labeled) return cleanAddress(labeled[1]);

  const marked = String(text).match(markedStreetRe);
  if (marked) return cleanAddress(marked[1]);

  // If the structured location resolver identified a canonical street, retain
  // it rather than returning a false numeric segment as an address.
  if (canonicalStreet) return canonicalStreet;

  const bare = String(text).match(
    /(?:^|[,;\n]\s*)([\p{L}][\p{L}'’‘`ʻʼ.-]*(?:\s+[\p{L}][\p{L}'’‘`ʻʼ.-]*){0,5}\s+\d+[\p{L}0-9/-]*)(?=\s*(?:[,.;\n]|$))/iu,
  );
  return bare ? cleanAddress(bare[1]) : null;
}
