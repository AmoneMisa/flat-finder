import {
  parseResidentialComplex as baseParseResidentialComplex,
} from './textparse.js';

// Explicit no-fee/no-intermediary phrases. These outrank every positive broker
// word so `БЕЗ МАКЛЕР`, `maklersiz`, `owner direct`, etc. cannot become a fee.
const NO_COMMISSION_RE =
  /(?:
    без\s+(?:комисси\w*|комісі\w*|комиссионн\w*|макл(?:ер\w*)?|ри[еэ]?лтор\w*|посредник\w*|агент\w*)|
    от\s+(?:хозяин\w*|собственник\w*)|
    власник\w*\s+без\s+комісі\w*|
    no\s+(?:commission|agency\s+fee|broker\s+fee|realtor\s+fee|agent\s+fee|agency|broker|realtor|agent)|
    owner\s+direct|direct\s+from\s+(?:owner|landlord)|
    f(?:ă|a)r(?:ă|a)\s+(?:comision|agen(?:ț|t)ie|intermediar\w*)|direct\s+(?:de\s+la\s+)?proprietar|
    komissiya\s*[- ]?siz|komissiyasiz|makler\s*[- ]?siz|maklersiz|vositachi\s*[- ]?siz|vositachisiz|egasidan|uy\s+egasidan|
    комиссиясыз|комиссия\s*жоқ|делдалсыз|делдал\s*жоқ|иесінен|үй\s+иесінен
  )/iux;

// Strong positive fee markers. Broker presence by itself is intentionally NOT
// enough to set commission=true: `риелтор`, `makler`, `agent` may identify who
// posted the ad without saying that the tenant pays a fee.
const COMMISSION_PERCENT_RE = [
  // Common labelled fee forms: "комиссия 50%", "commission: 50%", etc.
  /(?:комисси\w*|комісі\w*|commission|comision|komissiya|комиссия)\s*[:=\-]?\s*(\d{1,3})\s*%/iu,
  // Broker + explicit percentage: "Makler 50%", "realtor 30%", "agent fee 25%".
  /(?:макл(?:ер\w*)?|makler|ри[еэ]?лтор\w*|rieltor|realtor|broker|agent|vositachi|делдал)\s*(?:fee|haq(?:i)?|хак|ақы)?\s*[:=\-]?\s*(\d{1,3})\s*%/iu,
  // Central-Asian shorthand M50% / М50%.
  /(?:^|[^\p{L}\p{N}_])[mм]\s*[:.\-]?\s*(\d{1,3})\s*%/iu,
];

const EXPLICIT_FEE_RE =
  /(?:
    агентск\w*\s+(?:комисси\w*|вознаграждени\w*)|
    комисси\w*\s+(?:есть|оплачива\w*|взима\w*|бер[её]тся|требу\w*)|
    комісі\w*\s+(?:є|сплачу\w*|оплачу\w*)|
    agency\s+fee|broker\s+fee|realtor\s+fee|agent\s+fee|
    comision\s+(?:agen(?:ț|t)ie|intermediar)|
    komissiya\s+(?:bor|olinadi|to['’`]?lanadi)|
    makler\s+(?:haqi|xaqi|haq)|rieltor\s+(?:haqi|xaqi|haq)|vositachi\s+(?:haqi|xaqi|haq)|
    комиссия\s+(?:бар|алынады|төленеді)|делдал\s+(?:ақысы|ақы)
  )/iux;

const BROKER_MENTION_RE =
  /(?:макл(?:ер\w*)?|makler|ри[еэ]?лтор\w*|rieltor|realtor|broker|agent|агентств\w*|vositachi|делдал|agen(?:ț|t)ie|intermediar)/iu;

const RC_TRAILING_NO_BROKER_RE =
  /\s+(?:без\s+(?:макл(?:ер\w*)?|ри[еэ]?лтор\w*|посредник\w*|агент\w*)|no\s+(?:broker|realtor|agent|agency)|f(?:ă|a)r(?:ă|a)\s+(?:agen(?:ț|t)ie|intermediar\w*)|maklersiz|vositachisiz|egasidan|делдалсыз|иесінен)\b[\s\S]*$/iu;

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
