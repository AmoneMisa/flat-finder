// Best-effort extraction of price / rooms / area from free-text posts
// (Reddit, Telegram, Threads) where there is no structured field.

const CURRENCY_WORDS = [
  [/(€|eur\b|euro)/i, 'EUR'],
  [/(\$|usd\b|у\.?е\.?|у\.о\.?|dollar|доллар)/i, 'USD'],
  [/(грн|uah\b|₴|гривн)/i, 'UAH'],
  [/(lei\b|ron\b)/i, 'RON'],
  [/(тенге|теңге|tenge|tg\b|kzt\b|₸)/i, 'KZT'],
  [/(сум|сўм|so'?m\b|soʻm|som\b|uzs\b)/i, 'UZS'],
];

export function parsePriceFromText(text, fallbackCurrency = '') {
  if (!text) return { price: null, currency: fallbackCurrency };

  // Grab number groups with common thousands separators, e.g. "1 500 000",
  // "120.000", "85,000", "50000".
  const matches = text.match(/\d[\d\s.,]{2,}\d|\d{3,}/g) || [];
  let best = null;
  for (const m of matches) {
    const n = Number(m.replace(/[\s.,]/g, ''));
    if (n >= 1000 && n <= 5_000_000_000 && (best == null || n > best)) best = n;
  }

  let currency = fallbackCurrency;
  for (const [re, code] of CURRENCY_WORDS) {
    if (re.test(text)) {
      currency = code;
      break;
    }
  }
  return { price: best, currency };
}

export function parseRoomsFromText(text) {
  if (!text) return null;
  // camer (RO), комн (RU), кімн (UA), xona/xonali (UZ), бөлме/бөлмелі (KZ),
  // room/bedroom (EN).
  const m = text.match(
    /(\d+)\s*-?\s*(?:camer|комн|кімн|room|bedroom|xona|xonali|бөлме|бөлмел|к\.?в|-к\b)/i,
  );
  return m ? Number(m[1]) : null;
}

export function parseAreaFromText(text) {
  if (!text) return null;
  const m = text.match(/(\d{2,4})\s*(?:m2|m²|мкв|м2|м²|sq ?m|кв\.?\s*м)/i);
  return m ? Number(m[1]) : null;
}

// Classify a listing's deal type from its text. Returns one of
// 'sale' | 'longRent' | 'shortRent' | null (unknown). Short-term is checked
// first because those posts almost always also contain generic rent words.
export function classifyDealType(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  // Short-term: RO/RU/UA + UZ (sutkaga/kunlik/kecha) + KZ (тәулік/сағаттық).
  if (/(regim hotelier|in regim|posutoc|подобов|подобно|посуточн|почасов|за сутки|per (night|day)|daily rent|short[\s-]?term|nightly|sutkaga|kunlik|kecha[- ]?kunduz|тәулік|тәулiк|сағаттық)/i.test(t))
    return 'shortRent';
  // Long-term rent: RO/RU/UA/EN + UZ (ijara/arenda) + KZ (жалға/жалдау/аренда).
  if (/(inchiri|închiri|de închiriat|оренд|аренд|rent\b|for rent|сдам|сдаётся|сдается|здам|найм|долгосроч|довгостро|ijara|ijaraga|arenda|жалға|жалдау|жалга|жал\b)/i.test(t))
    return 'longRent';
  // Sale: RO/RU/UA/EN + UZ (sotiladi/sotuv/sotaman) + KZ (сатылады/сату).
  if (/(de v[aâ]nzare|v[aâ]nzare|продаж|продам|продаётся|продается|for sale|\bsale\b|купит|kupit|to buy|sotiladi|sotuv|sotaman|sotib|сатылады|сату|сатамын)/i.test(t))
    return 'sale';
  return null;
}

// Floor and total floors, e.g. "5/9", "этаж 5 из 9", "3-й этаж", "5-qavat",
// "floor 5". Returns { floor, totalFloors } with nulls when not found.
export function parseFloor(text) {
  if (!text) return { floor: null, totalFloors: null };
  const t = text.toLowerCase();
  const FLOOR = '(?:этаж|поверх|qavat|қабат|қабатт|etaj|floor|эт\\.?)';
  const ok = (f, total) =>
    f >= 0 && f <= 200 && (total == null || (total >= f && total <= 200));

  // "X/Y" with a floor word on either side.
  let m =
    t.match(new RegExp(`${FLOOR}\\D{0,4}(\\d{1,2})\\s*\\/\\s*(\\d{1,2})`)) ||
    t.match(new RegExp(`(\\d{1,2})\\s*\\/\\s*(\\d{1,2})\\s*${FLOOR}`));
  if (m) {
    const floor = Number(m[1]);
    const total = Number(m[2]);
    if (ok(floor, total)) return { floor, totalFloors: total };
  }

  // Single floor: "X этаж", "X-й этаж", "floor X", "этаж: X".
  let s =
    t.match(new RegExp(`(\\d{1,2})\\s*-?\\s*(?:й|го|nd|rd|th|st)?\\s*${FLOOR}\\b`)) ||
    t.match(new RegExp(`${FLOOR}\\s*[:№#]?\\s*(\\d{1,2})\\b`));
  if (s) {
    const floor = Number(s[1]);
    if (ok(floor, null)) return { floor, totalFloors: null };
  }
  return { floor: null, totalFloors: null };
}

// Construction year. Requires a build-related keyword nearby (or a year followed
// by a year-unit) to avoid matching random 4-digit numbers.
export function parseYear(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  const YEAR = '(19\\d{2}|20[0-3]\\d)';
  const KW =
    '(?:год(?:а)? постройк|построен|сдача|рік побудов|побудован|введен в експлуат|' +
    'built|year built|construc[cțt]ie|an construc|qurilgan|qurilish yil|salingan|' +
    'жыл(?:ы)? салынған)';
  let m =
    t.match(new RegExp(`${KW}\\D{0,12}${YEAR}`)) ||
    t.match(new RegExp(`${YEAR}\\s*(?:г\\.?|года|й\\.?|йил|жыл|year)\\b`));
  if (m) {
    const y = Number(m[1]);
    const max = new Date().getFullYear() + 3;
    if (y >= 1900 && y <= max) return y;
  }
  return null;
}

// Number of sleeping rooms / bedrooms (distinct from total rooms).
export function parseBedrooms(text) {
  if (!text) return null;
  const m = text.match(
    /(\d+)\s*-?\s*(?:bedroom|спальн|спалень|dormitoare|dormitor|yotoq(?:xona)?|жатын)/i,
  );
  return m ? Number(m[1]) : null;
}

// Target-audience restriction stated in the post, or null. Family is checked
// first so "for a family with girls" resolves to family.
export function classifyAudience(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  if (/(для семь|семейн|для сім|для родин|for famil|families?|pentru famil|oila(ga| uchun)|отбасы)/.test(t))
    return 'family';
  if (/(девуш|девоч|для дівч|дівчат|for girls|for women|only girls|doar fete|\bfete\b|qizlar(ga| uchun)?|қыздар)/.test(t))
    return 'women';
  if (/(парн(ей|ям)|для мужчин|мужчинам|для хлопц|for men\b|for boys|doar b[aă]ie[țt]i|yigitlar(ga| uchun)?|жігіттер|ер адам)/.test(t))
    return 'men';
  return null;
}

// Best-effort seller contact: an international phone (leading +), a local phone
// introduced by a phone keyword, or an @handle. Kept conservative so it does not
// mistake large prices (e.g. UZS amounts) for phone numbers.
export function parseContact(text) {
  if (!text) return null;

  const intl = text.match(/\+\d[\d\s().-]{7,}\d/);
  if (intl) {
    const digits = intl[0].replace(/\D/g, '');
    if (digits.length >= 10 && digits.length <= 15) return '+' + digits;
  }

  const kw = text.match(
    /(?:tel|тел|phone|моб|whats?app|viber|telegram|звонит|звоніть|aloqa|byla|contact)[^\d+]{0,8}(\+?\d[\d\s().-]{6,}\d)/i,
  );
  if (kw) {
    const digits = kw[1].replace(/\D/g, '');
    if (digits.length >= 9 && digits.length <= 15) return kw[1].trim();
  }

  const handle = text.match(/@[A-Za-z0-9_]{4,32}/);
  if (handle) return handle[0];

  return null;
}

export function guessPropertyType(text) {
  if (!text) return 'flat';
  // house (EN), casa (RO), dom/дом (RU), будин (UA), коттедж/villa/вілл/вилл,
  // uy/hovli (UZ), үй (KZ).
  return /\b(house|casa|dom\b|будин|дом\b|коттедж|villa|вілл|вилл|hovli|\buy\b|үй\b)/i.test(text)
    ? 'house'
    : 'flat';
}
