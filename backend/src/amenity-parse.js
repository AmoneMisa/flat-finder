import {
  AMENITY_TERMS,
  APPLIANCE_TERMS,
  aliasesOf,
  aliasesToRegex,
} from '@whiteslove/parsing-lexicon';

const dishwasherRe = aliasesToRegex([APPLIANCE_TERMS.dishwasher.canonical, ...aliasesOf(APPLIANCE_TERMS.dishwasher)]);
const terraceRe = aliasesToRegex([AMENITY_TERMS.terrace.canonical, ...aliasesOf(AMENITY_TERMS.terrace)]);

export function parseDishwasher(text) {
  if (!text) return null;
  return dishwasherRe.test(text) ? true : null;
}

export function parseTerrace(text) {
  if (!text) return null;
  return terraceRe.test(text) ? true : null;
}

export function parsePrivateYard(text) {
  if (!text) return null;
  // Ownership/private semantics are a Flat Finder business rule, not a shared
  // lexical entity: a generic common courtyard must not satisfy this filter.
  return /(?:личн(?:ый|ого|ым)\s+двор|сво[йеё]\s+(?:закрыт(?:ый|ого)\s+)?двор|собственн(?:ый|ого)\s+двор|приватн(?:ий|ый)\s+двір|власн(?:ий|ого)\s+двір|private\s+(?:courtyard|yard)|curte\s+(?:proprie|privat[ăa])|o['’`]?z\s+hovli(?:si)?|shaxsiy\s+hovli)/i.test(text)
    ? true
    : null;
}
