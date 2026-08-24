import {
  classifyAudience as baseClassifyAudience,
  parseFloor as baseParseFloor,
  parseResidentialComplex as baseParseResidentialComplex,
  parseRoomsFromText as baseParseRoomsFromText,
} from './textparse.js';
import {hasZeroCommissionSignal} from './seller-signals.js';

const COMMISSION_PERCENT_RE = [
  /(?:комисси[а-яёіїґ]*|комісі[а-яіїґ]*|commission|comision|komissiya|комиссия)\s*[:=\-]?\s*(\d{1,3})\s*%/iu,
  /(?:макл(?:ер[а-яё]*)?|makler|р[иі][еєэ]?лтор[а-яёіїґ]*|rieltor|realtor|broker|agent|vositachi|делдал)\s*(?:fee|haq(?:i)?|хак|ақы)?\s*[,;:]?\s*(\d{1,3})\s*%/iu,
  /(\d{1,3})\s*%\s*(?:комисси[а-яёіїґ]*|комісі[а-яіїґ]*|commission|comision|komissiya)/iu,
  /(?:^|[^\p{L}\p{N}_])[mм]\s*[:.\-]?\s*(\d{1,3})\s*%/iu,
];

const EXPLICIT_FEE_RE = /(?:агентск[а-яё]*\s+(?:комисси[а-яё]*|вознаграждени[а-яё]*)|комисси[а-яё]*\s+(?:есть|оплачива[а-яё]*|взима[а-яё]*|бер[её]тся|требу[а-яё]*)|комісі[а-яіїґ]*\s+(?:є|сплачу[а-яіїґ]*|оплачу[а-яіїґ]*)|agency\s+fee|broker\s+fee|realtor\s+fee|agent\s+fee|comision\s+(?:agen(?:ț|t)ie|intermediar)|komissiya\s+(?:bor|olinadi|to['’`]?lanadi)|makler\s+(?:haqi|xaqi|haq)|rieltor\s+(?:haqi|xaqi|haq)|vositachi\s+(?:haqi|xaqi|haq)|комиссия\s+(?:бар|алынады|төленеді)|делдал\s+(?:ақысы|ақы))/iu;

const BROKER_MENTION_RE = /(?:макл(?:ер[а-яё]*)?|makler|р[иі][еєэ]?лтор[а-яёіїґ]*|rieltor|realtor|broker|agent|агентств[а-яё]*|vositachi|делдал|agen(?:ț|t)ie|intermediar)/iu;
const RC_TRAILING_NO_BROKER_RE = /\s+(?:без\s+(?:макл(?:ер[а-яё]*)?|ри[еэ]?лтор[а-яё]*|посредник[а-яё]*|агент[а-яё]*)|no\s+(?:broker|realtor|agent|agency)|f(?:ă|a)r(?:ă|a)\s+(?:agen(?:ț|t)ie|intermediar\w*)|maklersiz|vositachisiz|egasidan|делдалсыз|иесінен)(?=$|[^\p{L}\p{N}_])[\s\S]*$/iu;

export function parseCommission(text) {
  if (!text) return { has: null, percent: null };
  if (hasZeroCommissionSignal(text)) return { has: false, percent: 0 };
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

function validLayout(rooms, floor, totalFloors) {
  if (rooms < 1 || rooms > 10 || floor < 0 || floor > 40 || totalFloors < 1 || totalFloors > 40 || floor > totalFloors) return null;
  return {rooms, floor, totalFloors};
}

function structuredLayout(text) {
  if (!text) return null;

  const labelled = text.match(/(?:xonalari|xonalar(?:i)?|комнат(?:ы|а)?|rooms?)\s*[:\-]?\s*([1-9])\s*(?:[вv>]\s*([1-9]))?\s*\/\s*([0-9]{1,2})\s*\/\s*([0-9]{1,2})/iu);
  if (labelled) {
    return validLayout(Number(labelled[2] || labelled[1]), Number(labelled[3]), Number(labelled[4]));
  }

  const converted = text.match(/(?:^|[^\d])([1-9])\s*[вv>]\s*([1-9])\s*\/\s*([0-9]{1,2})\s*\/\s*([0-9]{1,2})(?!\d)/iu);
  if (converted) {
    return validLayout(Number(converted[2]), Number(converted[3]), Number(converted[4]));
  }

  const withArea = text.match(/(?:^|[^\d])([1-9])\s*\/\s*([0-9]{1,2})\s*\/\s*([0-9]{1,2})(?=\s+\d{1,4}\s*(?:кв(?:\.?\s*м)?|м²|m²|m2|sqm)(?=$|[^\p{L}\p{N}_]))/iu);
  if (withArea) {
    return validLayout(Number(withArea[1]), Number(withArea[2]), Number(withArea[3]));
  }

  return null;
}

export function parseRoomsFromText(text) {
  return structuredLayout(text)?.rooms ?? baseParseRoomsFromText(text);
}

export function parseFloor(text) {
  const structured = structuredLayout(text);
  return structured ? { floor: structured.floor, totalFloors: structured.totalFloors } : baseParseFloor(text);
}

export function classifyAudience(text) {
  if (!text) return null;
  const both = /(?:qiz(?:lar)?[^\r\n]{0,30}(?:yoki|va|\/|or)[^\r\n]{0,30}yigit(?:lar)?|yigit(?:lar)?[^\r\n]{0,30}(?:yoki|va|\/|or)[^\r\n]{0,30}qiz(?:lar)?|women?[^\r\n]{0,30}(?:or|and|\/)[^\r\n]{0,30}men|men[^\r\n]{0,30}(?:or|and|\/)[^\r\n]{0,30}women?|девушк[а-яё]*[^\r\n]{0,30}(?:или|и|\/)[^\r\n]{0,30}(?:парн|мужчин)|(?:парн|мужчин)[а-яё]*[^\r\n]{0,30}(?:или|и|\/)[^\r\n]{0,30}девушк)/iu;
  if (both.test(text)) return null;
  return baseClassifyAudience(text);
}

const PEARL_NUMERIC_RE = /(?:^|[^\p{L}\p{N}_])([1-9]\d?)\s*(?:[-–—]?\s*(?:я|ая|а|й|st|nd|rd|th))?\s*(?:жемчужин[а-яё]*|перлин[а-яіїґ]*)(?=$|[^\p{L}\p{N}_])/iu;
const PEARL_TENS = new Map([
  ['двадцять', 20], ['тридцять', 30], ['сорок', 40],
  ['двадцать', 20], ['тридцать', 30],
]);
const PEARL_ONES = new Map([
  ['перша', 1], ['друга', 2], ['третя', 3], ['четверта', 4], ["п'ята", 5], ['шоста', 6], ['сьома', 7], ['восьма', 8], ["дев'ята", 9],
  ['первая', 1], ['вторая', 2], ['третья', 3], ['четвертая', 4], ['пятая', 5], ['шестая', 6], ['седьмая', 7], ['восьмая', 8], ['девятая', 9],
]);

function normalizePearlToken(value) {
  return String(value || '').toLowerCase().replace(/[’`ʼ]/g, "'").replace(/ё/g, 'е');
}

function parsePearlComplex(text) {
  if (!text) return null;
  const numeric = String(text).match(PEARL_NUMERIC_RE);
  if (numeric) return `${Number(numeric[1])} Жемчужина`;

  const words = String(text).match(/(?:^|[^\p{L}\p{N}_])(?:жк\s*)?(двадцять|тридцять|сорок|двадцать|тридцать)\s+([\p{L}'’`ʼ-]+)\s+(?:перлин[а-яіїґ]*|жемчужин[а-яё]*)(?=$|[^\p{L}\p{N}_])/iu);
  if (words) {
    const tens = PEARL_TENS.get(normalizePearlToken(words[1]));
    const ones = PEARL_ONES.get(normalizePearlToken(words[2]));
    if (tens && ones) return `${tens + ones} Жемчужина`;
  }

  const single = String(text).match(/(?:^|[^\p{L}\p{N}_])(?:жк\s*)?([\p{L}'’`ʼ-]+)\s+(?:перлин[а-яіїґ]*|жемчужин[а-яё]*)(?=$|[^\p{L}\p{N}_])/iu);
  if (single) {
    const value = PEARL_ONES.get(normalizePearlToken(single[1]));
    if (value) return `${value} Жемчужина`;
  }
  return null;
}

export function parseResidentialComplex(text) {
  const pearl = parsePearlComplex(text);
  if (pearl) return pearl;

  const raw = baseParseResidentialComplex(text);
  if (!raw) return null;
  const cleaned = raw
    .replace(RC_TRAILING_NO_BROKER_RE, '')
    .replace(/\s+[1-9]\s*(?:[вv>]\s*[1-9])?\s*\/\s*[0-9]{1,2}\s*\/\s*[0-9]{1,2}\b[\s\S]*$/iu, '')
    .replace(/\s+(?:глинка|glinka)\s*$/iu, '')
    .replace(/\s*[!|]+\s*$/g, '')
    .trim();
  return /[a-zA-Zа-яёіїґ]{2,}/i.test(cleaned) ? cleaned : null;
}

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
