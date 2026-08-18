import {
  classifyAudience as baseClassifyAudience,
  parseFloor as baseParseFloor,
  parseResidentialComplex as baseParseResidentialComplex,
  parseRoomsFromText as baseParseRoomsFromText,
} from './textparse.js';

// Explicit no-fee/no-intermediary phrases. These outrank every positive broker
// word so `БЕЗ МАКЛЕР`, `maklersiz`, `owner direct`, etc. cannot become a fee.
const NO_COMMISSION_RE = /(?:без\s+(?:комисси[а-яёіїґ]*|комісі[а-яіїґ]*|комиссионн[а-яё]*|макл(?:ер[а-яё]*)?|ри[еэ]?лтор[а-яё]*|посредник[а-яё]*|агент[а-яё]*)|от\s+(?:хозяин[а-яё]*|собственник[а-яё]*)|власник[а-яіїґ]*\s+без\s+комісі[а-яіїґ]*|no\s+(?:commission|agency\s+fee|broker\s+fee|realtor\s+fee|agent\s+fee|agency|broker|realtor|agent)|owner\s+direct|direct\s+from\s+(?:owner|landlord)|f(?:ă|a)r(?:ă|a)\s+(?:comision|agen(?:ț|t)ie|intermediar\w*)|direct\s+(?:de\s+la\s+)?proprietar|komissiya\s*[- ]?siz|komissiyasiz|makler\s*[- ]?siz|maklersiz|vositachi\s*[- ]?siz|vositachisiz|egasidan|uy\s+egasidan|комиссиясыз|комиссия\s*жоқ|делдалсыз|делдал\s*жоқ|иесінен|үй\s+иесінен)/iu;

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
  if (NO_COMMISSION_RE.test(text)) return { has: false, percent: 0 };
  for (const re of COMMISSION_PERCENT_RE) {
    const match = text.match(re);
    if (!match) continue;
    const percent = Number(match[1]);
    return { has: true, percent: Number.isFinite(percent) && percent >= 0 && percent <= 100 ? percent : null };
  }
  if (EXPLICIT_FEE_RE.test(text)) return { has: true, percent: null };
  if (BROKER_MENTION_RE.test(text)) return { has: null, percent: null };
  return { has: null, percent: null };
}

// Central-Asian compact layout forms can contain a conversion marker:
//   2в3/4/5 = original 2 rooms, converted to 3 rooms, floor 4 of 5.
// A labelled Xonalari line is stronger than unrelated occupancy notation such
// as `(6/7tagacha)` elsewhere in the advertisement.
function structuredLayout(text) {
  if (!text) return null;
  const labelled = text.match(/(?:xonalari|xonalar(?:i)?|комнат(?:ы|а)?|rooms?)\s*[:\-]?\s*([1-9])\s*(?:[вv>]\s*([1-9]))?\s*\/\s*([0-9]{1,2})\s*\/\s*([0-9]{1,2})/iu);
  const raw = labelled || text.match(/(?:^|[^\d])([1-9])\s*[вv>]\s*([1-9])\s*\/\s*([0-9]{1,2})\s*\/\s*([0-9]{1,2})(?!\d)/iu);
  if (!raw) return null;
  const rooms = Number(raw[2] || raw[1]);
  const floor = Number(raw[3]);
  const totalFloors = Number(raw[4]);
  if (rooms < 1 || rooms > 10 || floor < 0 || floor > 40 || totalFloors < 1 || totalFloors > 40 || floor > totalFloors) return null;
  return { rooms, floor, totalFloors };
}

export function parseRoomsFromText(text) {
  return structuredLayout(text)?.rooms ?? baseParseRoomsFromText(text);
}

export function parseFloor(text) {
  const structured = structuredLayout(text);
  return structured ? { floor: structured.floor, totalFloors: structured.totalFloors } : baseParseFloor(text);
}

// If both genders are explicitly accepted (`QIZLAR yoki YIGITLAR`,
// `women or men`, etc.), there is no gender restriction.
export function classifyAudience(text) {
  if (!text) return null;
  const both = /(?:qiz(?:lar)?[^\r\n]{0,30}(?:yoki|va|\/|or)[^\r\n]{0,30}yigit(?:lar)?|yigit(?:lar)?[^\r\n]{0,30}(?:yoki|va|\/|or)[^\r\n]{0,30}qiz(?:lar)?|women?[^\r\n]{0,30}(?:or|and|\/)[^\r\n]{0,30}men|men[^\r\n]{0,30}(?:or|and|\/)[^\r\n]{0,30}women?|девушк[а-яё]*[^\r\n]{0,30}(?:или|и|\/)[^\r\n]{0,30}(?:парн|мужчин)|(?:парн|мужчин)[а-яё]*[^\r\n]{0,30}(?:или|и|\/)[^\r\n]{0,30}девушк)/iu;
  if (both.test(text)) return null;
  return baseClassifyAudience(text);
}

export function parseResidentialComplex(text) {
  const raw = baseParseResidentialComplex(text);
  if (!raw) return null;
  const cleaned = raw
    .replace(RC_TRAILING_NO_BROKER_RE, '')
    // Stop before a compact rooms/floor/storeys block and everything after it.
    .replace(/\s+[1-9]\s*(?:[вv>]\s*[1-9])?\s*\/\s*[0-9]{1,2}\s*\/\s*[0-9]{1,2}\b[\s\S]*$/iu, '')
    // A known area/orientation may sit between the ЖК name and compact block.
    .replace(/\s+(?:глинка|glinka)\s*$/iu, '')
    .replace(/\s*[!|]+\s*$/g, '')
    .trim();
  return /[a-zA-Zа-яёіїґ]{2,}/i.test(cleaned) ? cleaned : null;
}

// Administrative district phrases are stronger than inferred massifs/areas.
// This prevents `Куйлюк` or a metro name from overriding `Бектемирский район`.
const UZ_EXPLICIT_DISTRICTS = [
  ['Bektemir', /бектемирск[а-яё]*\s+район|bektemir\s+(?:tumani|district)/iu],
  ['Chilanzar', /чиланзарск[а-яё]*\s+район|чиланзар\s+туман[а-яё]*|chilonzor\s+(?:tumani|district)|chilanzar\s+district/iu],
  ['Yunusabad', /юнусабадск[а-яё]*\s+район|yunusobod\s+(?:tumani|district)|yunusabad\s+district/iu],
  ['Yakkasaray', /яккасарайск[а-яё]*\s+район|yakkasaroy\s+(?:tumani|district)|yakkasaray\s+district/iu],
  ['Mirzo Ulugbek', /мирзо[-\s]?улугбекск[а-яё]*\s+район|mirzo\s+ulug['’]?bek\s+(?:tumani|district)/iu],
  ['Mirobod', /мир[оа]б[оа]дск[а-яё]*\s+район|mirobod\s+(?:tumani|district)/iu],
  ['Almazar', /алмазарск[а-яё]*\s+район|олмазор\s+(?:tumani|district)|almazar\s+district/iu],
  ['Uchtepa', /учтепинск[а-яё]*\s+район|уч\s*теп[а-яё]*\s+район|uchtepa\s+(?:tumani|district)/iu],
  ['Yashnobod', /яшнабадск[а-яё]*\s+район|yashnobod\s+(?:tumani|district)/iu],
  ['Shaykhantahur', /шайхантахурск[а-яё]*\s+район|shayxontohur\s+(?:tumani|district)/iu],
  ['Sergeli', /сергелийск[а-яё]*\s+район|sergeli\s+(?:tumani|district)/iu],
  ['Yangihayot', /янгиха[её]тск[а-яё]*\s+район|yangihayot\s+(?:tumani|district)/iu],
];

export function parseExplicitDistrict(text, countryCode) {
  if (countryCode !== 'UZ' || !text) return null;
  return UZ_EXPLICIT_DISTRICTS.find(([, re]) => re.test(text))?.[0] || null;
}
