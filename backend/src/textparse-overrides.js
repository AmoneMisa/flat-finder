import {
  parseCommission as baseParseCommission,
  parseResidentialComplex as baseParseResidentialComplex,
} from './textparse.js';

const NO_COMMISSION_BROKER_RE =
  /(?:без\s+(?:макл(?:ер[а-яё]*)?|ри[еэ]?лтор[а-яё]*|посредник[а-яё]*|агент[а-яё]*)|no\s+(?:broker|realtor|agent|agency)|vositachisiz|egasidan)/iu;

const RC_TRAILING_NO_BROKER_RE =
  /\s+(?:без\s+(?:макл(?:ер[а-яё]*)?|ри[еэ]?лтор[а-яё]*|посредник[а-яё]*|агент[а-яё]*)|no\s+(?:broker|realtor|agent|agency)|vositachisiz|egasidan)\b[\s\S]*$/iu;

export function parseCommission(text) {
  if (!text) return { has: null, percent: null };
  if (NO_COMMISSION_BROKER_RE.test(text)) {
    return { has: false, percent: 0 };
  }
  return baseParseCommission(text);
}

export function parseResidentialComplex(text) {
  const raw = baseParseResidentialComplex(text);
  if (!raw) return null;

  const cleaned = raw
    .replace(RC_TRAILING_NO_BROKER_RE, '')
    .replace(/\s*[!|]+\s*$/g, '')
    .trim();

  return /[a-zA-Zа-яёіїґ]{2,}/i.test(cleaned) ? cleaned : null;
}
