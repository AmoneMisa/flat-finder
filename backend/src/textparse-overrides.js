import {
  parseResidentialComplex as baseParseResidentialComplex,
} from './textparse.js';

// Explicit no-fee/no-intermediary phrases. These outrank every positive broker
// word so `БЕЗ МАКЛЕР`, `maklersiz`, `owner direct`, etc. cannot become a fee.
const NO_COMMISSION_RE = /(?:без\s+(?:комисси[а-яёіїґ]*|комісі[а-яёіїґ]*|комиссионн[а-яё]*|макл(?:ер[а-яё]*)?|ри[еэ]?лтор[а-яё]*|посредник[а-яё]*|агент[а-яё]*)|от\s+(?:хозяин[а-яё]*|собственник[а-яё]*)|власник[а-яіїґ]*\s+без\s+комісі[а-яіїґ]*|no\s+(?:commission|agency\s+fee|broker\s+fee|realtor\s+fee|agent\s+fee|agency|broker|realtor|agent)|owner\s+direct|direct\s+from\s+(?:owner|landlord)|f(?:ă|a)r(?:ă|a)\s+(?:comision|agen(?:ț|t)ie|intermediar\w*)|direct\s+(?:de\s+la\s+)?proprietar|komissiya\s*[- ]?siz|komissiyasiz|makler\s*[- ]?siz|maklersiz|vositachi\s*[- ]?siz|vositachisiz|egasidan|uy\s+egasidan|комиссиясыз|комиссия\s*жоқ|делдалсыз|делдал\s*жоқ|иесінен|үй\s+иесінен)/iu;

// Strong positive fee markers. Broker presence by itself is intentionally NOT
// enough to set commission=true: `риелтор`, `makler`, `agent` may identify who
// posted the ad without saying that the tenant pays a fee.
const COMMISSION_PERCENT_RE = [
  /(?:комисси[а-яёіїґ]*|комісі[а-яіїґ]*|commission|comision|komissiya|комиссия)\s*[:=\-]?\s*(\d{1,3})\s*%/iu,
  /(?:макл(?:ер[а-яё]*)?|makler|ри[еэ]?лтор[а-яё]*|rieltor|realtor|broker|agent|vositachi|делдал)\s*(?:fee|haq(?:i)?|хак|ақы)?\s*[:=\-]?\s*(\d{1,3})\s*%/iu,
  /(?:^|[^\p{L}\p{N}_])[mм]\s*[:.\-]?\s*(\d{1,3})\s*%/iu,
];

const EXPLICIT_FEE_RE = /(?:агентск[а-яё]*\s+(?:комисси[а-яё]*|вознаграждени[а-яё]*)|комисси[а-яё]*\s+(?:есть|оплачива[а-яё]*|взима[а-яё]*|бер[её]тся|требу[а-яё]*)|комісі[а-яіїґ]*\s+(?:є|сплачу[а-яіїґ]*|оплачу[а-яіїґ]*)|agency\s+fee|broker\s+fee|realtor\s+fee|agent\s+fee|comision\s+(?:agen(?:ț|t)ie|intermediar)|komissiya\s+(?:bor|olinadi|to['’`]?lanadi)|makler\s+(?:haqi|xaqi|haq)|rieltor\s+(?:haqi|xaqi|haq)|vositachi\s+(?:haqi|xaqi|haq)|комиссия\s+(?:бар|алынады|төленеді)|делдал\s+(?:ақысы|ақы))/iu;

const BROKER_MENTION_RE = /(?:макл(?:ер[а-яё]*)?|makler|ри[еэ]?лтор[а-яё]*|rieltor|realtor|broker|agent|агентств[а-яё]*|vositachi|делдал|agen(?:ț|t)ie|intermediar)/iu;

const RC_TRAILING_NO_BROKER_RE = /\s+(?:без\s+(?:макл(?:ер[а-яё]*)?|ри[еэ]?лтор[а-яё]*|посредник[а-яё]*|агент[а-яё]*)|no\s+(?:broker|realtor|agent|agency)|f(?:ă|a)r(?:ă|a)\s+(?:agen(?:ț|t)ie|intermediar\w*)|maklersiz|vositachisiz|egasidan|делдалсыз|иесінен)\b[\s\S]*$/iu;

export function parseCommission(text) {
  if (!text) return { has: null, percent: null };

  if (NO_COMMISSION_RE.test(text)) {
    return { has: false, percent: 0 };
  }

  for (const re of COMMISSION_PERCENT_RE) {
    const match = text.match(re);
    if (!match) continue;
    const percent = Number(match[1]);
    return {
      has: true,
      percent: Number.isFinite(percent) && percent >= 0 && percent <= 100 ? percent : null,
    };
  }

  if (EXPLICIT_FEE_RE.test(text)) {
    return { has: true, percent: null };
  }

  // Critical semantic split: merely mentioning an agent/realtor/makler is not
  // proof of a tenant-paid commission. Preserve `unknown` until a fee is stated.
  if (BROKER_MENTION_RE.test(text)) {
    return { has: null, percent: null };
  }

  return { has: null, percent: null };
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
