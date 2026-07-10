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

// Currency marker used to spot amounts written right next to a currency, e.g.
// "150 $", "$81500", "750€", "1 500 у.е". Lets us keep small hard-currency
// rents (a few hundred $/€) that the "must be ≥ 1000" fallback would drop.
const PRICE_SYMBOL =
  "(?:\\$|€|₸|₴|usd|eur|грн|uah|lei|ron|тенге|тг|kzt|сум|so'?m|uzs|у\\.?е\\.?|доллар|евро)";
const PRICE_NUM = '\\d[\\d\\s.,]*\\d|\\d';

export function parsePriceFromText(text, fallbackCurrency = '') {
  if (!text) return { price: null, currency: fallbackCurrency };

  let currency = fallbackCurrency;
  for (const [re, code] of CURRENCY_WORDS) {
    if (re.test(text)) {
      currency = code;
      break;
    }
  }

  // (1) Prefer a number sitting right next to a currency marker. These are
  // reliable even when small, so hard-currency rents like "150 $" survive.
  let tagged = null;
  const reNumSym = new RegExp(`(${PRICE_NUM})\\s*${PRICE_SYMBOL}`, 'ig');
  const reSymNum = new RegExp(`${PRICE_SYMBOL}\\s*(${PRICE_NUM})`, 'ig');
  for (const re of [reNumSym, reSymNum]) {
    let m;
    while ((m = re.exec(text)) !== null) {
      const n = Number(m[1].replace(/[\s.,]/g, ''));
      if (n >= 50 && n <= 5_000_000_000 && (tagged == null || n > tagged)) tagged = n;
    }
  }
  if (tagged != null) return { price: tagged, currency };

  // (2) Fallback: the largest plausible number with common thousands separators,
  // e.g. "1 500 000", "120.000", "85,000", "50000". A ≥1000 floor here avoids
  // mistaking areas/floors for a price when no currency is attached.
  const matches = text.match(/\d[\d\s.,]{2,}\d|\d{3,}/g) || [];
  let best = null;
  for (const m of matches) {
    const n = Number(m.replace(/[\s.,]/g, ''));
    if (n >= 1000 && n <= 5_000_000_000 && (best == null || n > best)) best = n;
  }
  return { price: best, currency };
}

export function parseRoomsFromText(text) {
  if (!text) return null;
  // (B) number AFTER the label — the common Telegram form: "Количество
  // комнат: 3", "Комнат 1", "Комнаты: 2", "Xonalar soni: 3", "Number of
  // rooms - 2". Checked FIRST so a stray preceding number (e.g. in "Этаж 3
  // Комнат 1" the 3 belongs to the floor) doesn't get grabbed by the
  // number-first pattern below.
  const after = text.match(
    /(?:количество\s+комнат|комнат[а-яё]*|кімнат[а-яё]*|xonalar\s*soni|xona\s*soni|number\s+of\s+rooms)\s*[:\-–—]?\s*(\d+)/i,
  );
  // (A) number BEFORE the room word: "3 комнатная", "2-комн", "3 xona",
  // "1 room". camer (RO), комн (RU), кімн (UA), xona/xonali (UZ),
  // бөлме/бөлмелі (KZ), room/bedroom (EN). We deliberately do NOT match a bare
  // "кв" — that is "кв.м" (area) or "квартал" (block), e.g. "Чиланзар 16кв".
  const before = text.match(
    /(\d+)\s*[-хx]?\s*(?:camer|комнатн|комн|кімн|room|bedroom|xonali|xona|бөлмел|бөлме)|(\d+)\s*-\s*к(?:омн|\.?\s*кв)/i,
  );
  const n = after ? Number(after[1]) : before ? Number(before[1] ?? before[2]) : null;
  // Dwellings realistically have 1–10 rooms; anything larger is a mis-parse.
  return n != null && n >= 1 && n <= 10 ? n : null;
}

// Non-residential / commercial listings (offices, retail, warehouses) that
// should not appear among housing results. Kept conservative so amenities like
// "магазин рядом" (shop nearby) don't wrongly flag a flat.
// Includes: offices, commercial/business centres, non-residential "помещение",
// retail/warehouse/production premises, land plots (sotix/sotka/соток/yer
// maydoni — not housing) and service/auto premises (car wash, repair bay).
const COMMERCIAL_RE =
  /(офис[ _]|под ?офис|офисн|\boffice\b|\bofis\b|кеңсе|коммерческ|commercial|бизнес[ -]?центр|нежил(?:ое|ое помещ|ых)|помещени[ея]|торгов(?:ое|ая) ?площад|торгов(?:ое|ое помещ)|warehouse|склад(?!н|ыв)|производствен(?:ное|ых) ?помещ|spatiu comercial|birou|\d+\s*sot(?:ix|ka)|\d+\s*сот(?:ок|ка|ки|ых)|yer\s*maydoni|bosh\s*yer|уч[аа]сток\s*земл|servis\s*uchun|kassaprav|avtomoyka|автомойк|car\s?wash|шиномонтаж|салон\s*красот|zallik\s*saloni|beauty\s*salon|парикмахерск|барбершоп|barbershop)/i;

export function looksCommercial(text) {
  return text ? COMMERCIAL_RE.test(text) : false;
}

// Residential-complex ("ЖК ...", "residential complex", "ЖМ", "TP", RO "ansamblu")
// name, when the post names one. Returns a short trimmed name or null.
export function parseResidentialComplex(text) {
  if (!text) return null;
  const m = text.match(
    /(?:жк|жм|ж\/к|residential complex|ansamblu(?: rezidential)?|turar[- ]?joy majmuasi)\s*["'«»„“]?\s*([^"'«»„“\n,.;()]{2,40})/i,
  );
  if (!m) return null;
  const name = m[1].trim().replace(/\s{2,}/g, ' ');
  // Reject captures that are just a number or too short to be a name.
  return /[a-zA-Zа-яёіїґ]{2,}/i.test(name) ? name : null;
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
  // Sale: RO/RU/UA/EN + UZ (sotiladi/sotuv/sotaman) + KZ (сатылады/сату).
  // Checked BEFORE long-term rent because sale posts routinely pitch rental
  // income ("подойдёт для сдачи в аренду"), which would otherwise be misread as
  // a rental. A negation guard avoids "не продаётся" flipping a rental to sale.
  const sale =
    /(de v[aâ]nzare|v[aâ]nzare|прода[жёе]|продам|на продаж|for sale|\bsale\b|купит|kupit|to buy|sotiladi|sotuv|sotaman|sotib|сатылады|сату|сатамын)/i.test(t) &&
    !/не\s+прода/i.test(t);
  if (sale) return 'sale';
  // Long-term rent: RO/RU/UA/EN + UZ (ijara/arenda) + KZ (жалға/жалдау/аренда).
  if (/(inchiri|închiri|de închiriat|оренд|аренд|rent\b|for rent|сдам|сдаётся|сдается|здам|найм|долгосроч|довгостро|ijara|ijaraga|arenda|жалға|жалдау|жалга|жал\b)/i.test(t))
    return 'longRent';
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
    if (ok(floor, null)) {
      // Building height stated on its own line ("Этажность: 4",
      // "qavatlar soni: 9", "этажей 12") fills totalFloors when present.
      const tm = t.match(
        /(?:этажность|этажей|поверхови|поверховість|qavatlar(?:\s*soni)?|qavatli|қабатты?)\D{0,6}(\d{1,2})/,
      );
      const total = tm ? Number(tm[1]) : null;
      return { floor, totalFloors: total && total >= floor && total <= 200 ? total : null };
    }
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

// Whether pets are explicitly allowed. Returns true / false / null (unstated).
// We only return false on an explicit ban so "unknown" stays lenient.
export function classifyPets(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  if (/(без ?животн|нельзя с животными|без тварин|no pets|pets not allowed|fara animale|hayvon.*mumkin emas|үй жануар.*болмайды)/i.test(t))
    return false;
  if (/(можно с животными|можно с питомц|з тваринами можна|з тваринами дозвол|pets? ?(allowed|ok|friendly)|se accepta animale|animale acceptate|uy hayvon.*mumkin|үй жануар.*болады)/i.test(t))
    return true;
  return null;
}

// Whether children are explicitly allowed. Same true/false/null convention.
export function classifyChildren(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  if (/(без ?детей|нельзя с детьми|без дітей|no (kids|children)|children not allowed|fara copii|bolalar.*mumkin emas|балалар.*болмайды)/i.test(t))
    return false;
  if (/(можно с детьми|можно с ребен|з дітьми можна|з дітьми дозвол|children ?(allowed|ok|welcome)|kids ?(ok|welcome)|se accepta copii|copii acceptati|bolalar.*mumkin|балалар.*болады)/i.test(t))
    return true;
  return null;
}

// True when the post is renting only a room (not the whole flat), a.k.a.
// "подселение" / partial rent / room in a shared flat.
export function looksRoomOnly(text) {
  if (!text) return false;
  return /(подселени|подселение|комнату в|сдаётся комната|сдается комната|сдам комнату|здам кімнат|кімнату в|room in a (shared |)flat|room for rent|shared (flat|apartment|room)|roommate|xona ijaraga|бөлме жалға|închiriez camer[ăa])/i.test(text);
}

// Security deposit required? true/false/null. Also returns the amount when the
// post states one (e.g. "залог 500$").
export function parseDeposit(text) {
  if (!text) return { required: null, amount: null };
  const t = text.toLowerCase();
  const KW = '(?:залог|заклад|депозит|deposit|garan[țt]ie|kaus|kafolat|кепіл)';
  if (!new RegExp(KW, 'i').test(t)) return { required: null, amount: null };
  if (/(без ?залог|без ?депозит|no deposit|fara garantie|депозит ?не ?требует)/i.test(t))
    return { required: false, amount: null };
  const m = t.match(new RegExp(`${KW}[^\\d]{0,15}(\\d[\\d\\s.,]{1,})`, 'i'));
  const amount = m ? Number(m[1].replace(/[\s.,]/g, '')) : null;
  return { required: true, amount: amount && amount >= 10 ? amount : null };
}

// Agency commission. Returns { has: bool|null, percent: number|null } — percent
// is filled when the post states one (e.g. "комиссия 50%").
export function parseCommission(text) {
  if (!text) return { has: null, percent: null };
  const t = text.toLowerCase();
  const KW = '(?:комисси|комісі|commission|comision|komissiya|комиссионн)';
  if (/(без ?комисси|без ?комісі|no commission|fara comision|fără comision|без ?комиссионн)/i.test(t))
    return { has: false, percent: 0 };
  if (!new RegExp(KW, 'i').test(t)) return { has: null, percent: null };
  const m = t.match(new RegExp(`${KW}[^\\d]{0,15}(\\d{1,3})\\s*%`, 'i'));
  const percent = m ? Number(m[1]) : null;
  return { has: true, percent: percent != null && percent <= 100 ? percent : null };
}

export function guessPropertyType(text) {
  if (!text) return 'flat';
  // house (EN), casa (RO), dom/дом (RU), будин (UA), коттедж/villa/вілл/вилл,
  // uy/hovli (UZ), үй (KZ).
  return /\b(house|casa|dom\b|будин|дом\b|коттедж|villa|вілл|вилл|hovli|\buy\b|үй\b)/i.test(text)
    ? 'house'
    : 'flat';
}
