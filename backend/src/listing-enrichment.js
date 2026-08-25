const PHONE_RUN_RE = /\+?\d[\d\s().-]{7,}\d/g;
const PHONE_WORD_RE = /(?:тел(?:ефон)?|phone|mobile|моб(?:ильный)?|whats?app|telegram|aloqa)\s*[:.-]?\s*/giu;
const BROKER_RE = /(?:комисси[а-яёіїґ]*|комісі[а-яіїґ]*|commission|comision|komissiya|макл(?:ер[а-яё]*)?|makler|ри[еэ]лтор[а-яё]*|рієлтор[а-яіїґ]*|rieltor|realtor|broker|agent|агентств[а-яё]*|vositachi|делдал)/iu;
const NO_COMMISSION_RE = /(?:без\s+комисси|без\s+комісі|no\s+commission|fara\s+comision|fără\s+comision|без\s+маклер|maklersiz|vositachisiz)/iu;

function boundedCount(value, max = 20) {
  const number = Number(value);
  return Number.isInteger(number) && number >= 1 && number <= max ? number : null;
}

function parseBedrooms(text) {
  if (!text) return null;
  const value = String(text);
  const patterns = [
    /(\d{1,2})\s*(?:спальн(?:я|и|ь|ых|ые|ю)?|спалень|bedrooms?|yotoq\s*xona(?:si|lari)?|yotoqxona(?:si|lari)?|ётоқхона(?:си|лари)?)/iu,
    /(?:спальн(?:я|и|ь|ых|ые|ю)?|спалень|bedrooms?|yotoq\s*xona(?:si|lari)?|yotoqxona(?:si|lari)?|ётоқхона(?:си|лари)?)\s*[:=\-–—]?\s*(\d{1,2})/iu,
    /(?:кол(?:ичество)?\s+спален|number\s+of\s+bedrooms)\s*[:=\-–—]?\s*(\d{1,2})/iu,
  ];
  for (const pattern of patterns) {
    const match = value.match(pattern);
    const number = boundedCount(match?.[1], 12);
    if (number != null) return number;
  }
  return null;
}

function parseBathrooms(text) {
  if (!text) return null;
  const value = String(text);
  const label = '(?:сан\\s*уз(?:ел|ла|лов|лы|лами)?|с\\s*[/\\\\]\\s*у|ванн(?:ая|ые|ых|ых комнат)?|bathrooms?|bath(?:s)?|sanuzel(?:lar)?|hammom(?:lar)?|hojatxona(?:lar)?)';
  const patterns = [
    new RegExp(`(\\d{1,2})\\s*${label}`, 'iu'),
    new RegExp(`${label}\\s*[:=\\-–—]?\\s*(\\d{1,2})`, 'iu'),
    /(?:кол(?:ичество)?\s+санузл(?:ов)?|number\s+of\s+bathrooms)\s*[:=\-–—]?\s*(\d{1,2})/iu,
  ];
  for (const pattern of patterns) {
    const match = value.match(pattern);
    const number = boundedCount(match?.[1], 12);
    if (number != null) return number;
  }
  return null;
}

function parseFloorPair(text) {
  if (!text) return null;
  const value = String(text);
  const floorWord = '(?:этаж|эт\\.|поверх|qavat|қабат|floor)';
  const patterns = [
    new RegExp(`${floorWord}[^\\d\\r\\n]{0,8}([0-9]{1,2})\\s*[\\/\\\\]\\s*([0-9]{1,2})`, 'iu'),
    new RegExp(`([0-9]{1,2})\\s*[\\/\\\\]\\s*([0-9]{1,2})[^\\d\\r\\n]{0,8}${floorWord}`, 'iu'),
    /(?:^|[\r\n;|])\s*([0-9]{1,2})\s*[\/\\]\s*([0-9]{1,2})\s*(?=$|[\r\n;|])/mu,
  ];
  for (const pattern of patterns) {
    const match = value.match(pattern);
    if (!match) continue;
    const floor = Number(match[1]);
    const totalFloors = Number(match[2]);
    if (floor >= 0 && floor <= 40 && totalFloors >= 1 && totalFloors <= 40 && floor <= totalFloors) {
      return {floor, totalFloors};
    }
  }
  return null;
}

function parseCommissionPercent(text) {
  if (!text) return null;
  const value = String(text);
  const broker = BROKER_RE.source;
  const patterns = [
    new RegExp(`${broker}[^\\d%\\r\\n]{0,24}(\\d{1,3})\\s*%`, 'iu'),
    new RegExp(`(\\d{1,3})\\s*%[^\\r\\n]{0,24}${broker}`, 'iu'),
    /(?:^|[^\p{L}\p{N}_])[mм]\s*[:=.-]?\s*(\d{1,3})\s*%/iu,
    new RegExp(`${broker}[^\\d\\r\\n]{0,24}(\\d{1,3})\\s*[/\\\\]\\s*(?:50|100)(?=$|[^\\d])`, 'iu'),
    new RegExp(`${broker}\\s*[:=\\-–—]?\\s*(\\d{1,3})(?=\\s*(?:$|[;,|\\r\\n]))`, 'iu'),
  ];
  for (const pattern of patterns) {
    const match = value.match(pattern);
    if (!match) continue;
    const percent = Number(match[1]);
    if (Number.isFinite(percent) && percent >= 0 && percent <= 100) return percent;
  }
  return null;
}

function detectCommission(text, current) {
  if (current === false || NO_COMMISSION_RE.test(String(text || ''))) return false;
  if (current === true) return true;
  return BROKER_RE.test(String(text || '')) ? true : current ?? null;
}

function parseCadastral(text) {
  if (!text || !/(?:кадастр|кадастров|kadastr|cadastr)/iu.test(text)) return null;
  if (/(?:без\s+кадастр|кадастр(?:а|овый\s+документ)?\s*(?:нет|отсутств)|kadastr\s*yo['’`]?q|fara\s+cadastr)/iu.test(text)) return false;
  return true;
}

function parseFirstRental(text) {
  if (!text) return null;
  if (/(?:не\s+первая\s+сдача|не\s+впервые\s+сда[её]тся|not\s+first\s+(?:rent|rental))/iu.test(text)) return false;
  if (/(?:первая\s+сдача|впервые\s+сда[её]тся|сда[её]тся\s+впервые|перв(?:ая|ый)\s+аренд[а-яё]*|first\s+(?:rent|rental)|first\s+time\s+(?:for\s+)?rent|birinchi\s+(?:marta\s+)?ijara|ilk\s+ijara)/iu.test(text)) return true;
  return null;
}

function normalizeAddressCandidate(value) {
  if (!value) return null;
  const raw = String(value).replace(/\s+/g, ' ').trim();
  if (!raw) return null;

  const phoneDigits = [...raw.matchAll(PHONE_RUN_RE)]
    .map((match) => match[0].replace(/\D/g, ''))
    .filter((digits) => digits.length >= 9);
  let cleaned = raw.replace(PHONE_RUN_RE, (segment) => (
    segment.replace(/\D/g, '').length >= 9 ? ' ' : segment
  ));
  cleaned = cleaned
    .replace(PHONE_WORD_RE, ' ')
    .replace(/^[\s,;:.\-–—]+|[\s,;:.\-–—]+$/g, '')
    .replace(/\s{2,}/g, ' ')
    .trim();

  if (!cleaned || !/\p{L}{2,}/u.test(cleaned)) return null;
  const hasAddressMarker = /(?:ул(?:ица)?|кўча|ko['’]?cha|street|st\.|просп|переул|мкр|квартал|дом\s*№?|uy\s*№?|house|жк|массив|manzil|address)/iu.test(cleaned);
  if (phoneDigits.length && !hasAddressMarker) return null;
  if (/^(?:тел(?:ефон)?|phone|whats?app|telegram|aloqa)\b/iu.test(cleaned)) return null;
  // Do not turn landmarks, room/floor facts or building-height phrases into an
  // address. They appeared in production as "школа 160", "Персидский 2-Этаж"
  // and "Этажность дом 4" after a loose source parser captured a text segment.
  if (!hasAddressMarker && /(?:\b(?:этаж|этажность|qavat|floor|школа|school|рынок|bozor|парк|park|metro|метро)\b|\b(?:xona|xonalar|комнат)\w*\b)/iu.test(cleaned)) {
    return null;
  }
  return cleaned.slice(0, 120);
}

function parseAddress(text) {
  if (!text) return null;
  const value = String(text);
  const labelled = value.match(/(?:адрес|адреса|manzil|address)\s*[:=\-–—]\s*([^\r\n]{3,120})/iu);
  const fromLabel = normalizeAddressCandidate(labelled?.[1]);
  if (fromLabel) return fromLabel;

  const street = value.match(/((?:ул(?:иц[аы])?|просп(?:ект)?|проспект|мкр|микрорайон|проезд|переулок|ko['’]?cha(?:si)?|кўча(?:си)?)\.?\s+[^\r\n,;]{2,70})/iu);
  return normalizeAddressCandidate(street?.[1]);
}

function detectRoomShare(text, current) {
  if (current === true) return true;
  if (!text) return false;
  const value = String(text);
  return /(?:подселени|койко[-\s]?мест|место\s+в\s+(?:комнат|квартир)|одно\s+место|1\s+место|bed\s*space|roommate|flatmate|sherik(?:ka|lik)|шерик(?:ка|лик)|(?:bitta|1)\s+joy\s+(?:bor|mavjud)|(?:битта|1)\s+жой\s+(?:бор|мавжуд)|birga\s+yashash(?:ga)?[^\r\n.!?]{0,36}(?:\d+\s*ta?\s*)?(?:qiz|ayol)[^\r\n.!?]{0,20}(?:kerak|kere)|kvartira(?:ga|da)?[^\r\n.!?]{0,36}(?:1|bitta)\s*(?:ta\s*)?(?:qiz|ayol)[^\r\n.!?]{0,20}(?:ijarachi\s*)?(?:kerak|kere))/iu.test(value);
}

function titleCaseWords(value) {
  return String(value || '')
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

function parseNearbyLandmarks(text) {
  if (!text) return [];
  const value = String(text).replace(/\s+/g, ' ').trim();
  const out = [];
  const push = (label) => {
    const clean = String(label || '').replace(/\s+/g, ' ').trim();
    if (!clean || out.some((item) => item.toLocaleLowerCase() === clean.toLocaleLowerCase())) return;
    out.push(clean);
  };

  for (const match of value.matchAll(/([\p{L}'’.-]{2,24})\s+moshina\s+bozor(?:i|iga|ga)?/giu)) {
    push(`${titleCaseWords(match[1])} Car Market`);
  }
  for (const match of value.matchAll(/([\p{L}'’.-]{2,24})\s+dehqon\s+bozor(?:i|iga|ga)?/giu)) {
    push(`${titleCaseWords(match[1])} Farmers Market`);
  }
  for (const match of value.matchAll(/\byaqin\s+([\p{L}'’.-]{2,24}\s+avto)\b/giu)) {
    push(titleCaseWords(match[1]));
  }

  return out.slice(0, 8);
}

function isLowRoomPrice(listing) {
  const price = Number(listing?.price);
  if (!Number.isFinite(price) || price <= 0) return false;
  const currency = String(listing?.currency || '').toUpperCase();
  const thresholds = {
    USD: 120,
    EUR: 110,
    UZS: 1_500_000,
    KZT: 55_000,
    UAH: 4_500,
    RON: 500,
  };
  const threshold = thresholds[currency];
  return threshold != null && price <= threshold;
}

function explicitlyOneWoman(text) {
  if (!text) return false;
  const value = String(text);
  return /(?:только|нужн[а-яё]*|ищ[еу][а-яё]*|подсел[а-яё]*|возьм[её]м)[^\r\n.!?]{0,24}(?:одн(?:а|ой|у)|1)\s+(?:девушк[а-яё]*|женщин[а-яё]*)|(?:одн(?:а|ой|у)|1)\s+(?:девушк[а-яё]*|женщин[а-яё]*)[^\r\n.!?]{0,24}(?:только|нужн[а-яё]*|ищ[еу][а-яё]*|подсел[а-яё]*)|(?:faqat\s+)?(?:1|bitta)\s*(?:ta\s*)?(?:qiz|ayol)[^\r\n.!?]{0,18}(?:ijarachi\s*)?(?:kerak|kere|uchun)?|(?:фақат\s+)?(?:1|битта)\s*(?:та\s*)?(?:қиз|аёл)[^\r\n.!?]{0,18}(?:ижарачи\s*)?(?:керак|учун)?/iu.test(value);
}

function classifyPotentiallyUnsafe(listing, text, roomOnly) {
  return roomOnly === true && explicitlyOneWoman(text) && isLowRoomPrice(listing);
}

/**
 * Last-mile normalization before a listing is persisted. Scrapers keep their
 * source-specific mapping, while this pass fixes fields that are commonly
 * hidden in free text or malformed by contact data.
 */
export function enrichListingDetails(listing) {
  const source = listing && typeof listing === 'object' ? listing : {};
  const text = `${source.title || ''}\n${source.description || ''}`.trim();
  const floorPair = parseFloorPair(text);
  const commissionPercent = parseCommissionPercent(text);
  const commission = detectCommission(text, source.commission);
  const roomOnly = detectRoomShare(text, source.roomOnly);

  const existingAddress = normalizeAddressCandidate(source.address);
  const parsedAddress = parseAddress(text);
  const parsedNearby = parseNearbyLandmarks(text);
  const nearby = [...new Set([
    ...(Array.isArray(source.nearby) ? source.nearby.filter(Boolean) : []),
    ...parsedNearby,
  ])];
  const enriched = {
    ...source,
    bedrooms: boundedCount(source.bedrooms, 12) ?? parseBedrooms(text),
    bathrooms: boundedCount(source.bathrooms, 12) ?? parseBathrooms(text),
    floor: source.floor != null ? Number(source.floor) : (floorPair?.floor ?? null),
    totalFloors: source.totalFloors != null ? Number(source.totalFloors) : (floorPair?.totalFloors ?? null),
    address: existingAddress ?? parsedAddress ?? null,
    commission,
    commissionPercent: commissionPercent ?? source.commissionPercent ?? (commission === false ? 0 : null),
    cadastral: source.cadastral ?? parseCadastral(text),
    firstRental: source.firstRental ?? parseFirstRental(text),
    roomOnly,
    nearby,
  };
  enriched.potentiallyUnsafe = source.potentiallyUnsafe === true || classifyPotentiallyUnsafe(enriched, text, roomOnly);
  return enriched;
}

export const __listingEnrichmentTest = {
  parseBedrooms,
  parseBathrooms,
  parseFloorPair,
  parseCommissionPercent,
  detectCommission,
  parseCadastral,
  parseFirstRental,
  normalizeAddressCandidate,
  parseAddress,
  detectRoomShare,
  parseNearbyLandmarks,
  explicitlyOneWoman,
  classifyPotentiallyUnsafe,
};
