import { FULL_TASHKENT_AREAS, normalizeForMatch } from '@whiteslove/parsing-lexicon';

// Compatibility export: data is owned by the shared package; this module keeps
// only Flat Finder's ambiguity/district inference rules for numbered massifs.
export const TASHKENT_AREAS = FULL_TASHKENT_AREAS;

const normalize = (value) => normalizeForMatch(value);

const phraseIn = (normalizedText, alias) =>
  ` ${normalizedText} `.includes(` ${normalize(alias)} `);

const STATIC_MATCHERS = Object.entries(TASHKENT_AREAS)
  .flatMap(([district, entries]) => entries.flatMap((entry) =>
    entry.aliases.map((alias) => ({ district, area: entry.name, alias }))))
  .sort((a, b) => normalize(b.alias).length - normalize(a.alias).length);

const result = (areaName, district, confidence = 1, ambiguous = false) => ({
  area: areaName,
  district,
  confidence,
  ambiguous,
  requireExactAddress: ambiguous,
});

function numberedMatch(text, names) {
  const alternatives = names.map(normalize).join('|').replace(/ /g, '\\s+');
  return text.match(new RegExp(
    `(?:^|\\s)(?:${alternatives})(?:\\s+(?:tumani|тумани|district|район|massiv|массив))?\\s+(\\d{1,2})(?:\\s*([adад]))?(?:\\s+(?:chi|чи|й|квартал|kvartal|hudud|худуд))*(?:\\s|$)`,
    'iu',
  ));
}

const latinSuffix = (value) => ({ А: 'A', Д: 'D' }[String(value || '').toUpperCase()] || String(value || '').toUpperCase());

export function resolveTashkentArea(value) {
  const text = normalize(value);
  if (!text) return null;

  let match = numberedMatch(text, ['чиланзар', 'чилонзор', 'chilanzar', 'chilonzor']);
  if (!match) {
    const reverse = text.match(/(?:^|\s)(\d{1,2})\s+(?:квартал|кв л)\s+(?:чиланзара|чилонзора|chilanzar|chilonzor)(?:\s|$)/iu);
    if (reverse) match = [reverse[0], reverse[1], ''];
  }
  if (match) {
    const number = Number(match[1]);
    const suffix = latinSuffix(match[2]);
    const district = ((number >= 11 && number <= 15) || (number >= 21 && number <= 25))
      ? 'Uchtepa'
      : ((number >= 1 && number <= 10) || (number >= 16 && number <= 20))
        ? 'Chilanzar'
        : null;
    return result(`Chilanzar-${number}${suffix}`, district, district ? 1 : 0.5, !district);
  }

  match = numberedMatch(text, ['куйлюк', 'куйлик', 'kuylyuk', 'kuyliq', 'qoyliq', 'qo yliq']);
  if (match) {
    const number = Number(match[1]);
    const district = number >= 1 && number <= 4 ? 'Mirobod' : number >= 5 && number <= 7 ? 'Sergeli' : null;
    return result(`Kuylyuk-${number}`, district, district ? 1 : 0.5, !district);
  }

  match = numberedMatch(text, ['сергели', 'sergeli', 'sergile', 'sergele']);
  if (match) {
    const number = Number(match[1]);
    const suffix = latinSuffix(match[2]);
    const legacyYangihayot = number === 1 || (suffix === 'A' && [3, 5, 7].includes(number));
    const knownSergeli = [2, 4, 5, 6, 7, 8].includes(number);
    const district = legacyYangihayot ? 'Yangihayot' : 'Sergeli';
    return result(`Sergeli-${number}${suffix}`, district, legacyYangihayot || knownSergeli ? 1 : 0.75, !(legacyYangihayot || knownSergeli));
  }

  for (const [names, canonical, max, district] of [
    [['юнусабад', 'yunusabad', 'yunusobod'], 'Yunusabad', 22, 'Yunusabad'],
    [['янгихаёт', 'янгихаят', 'yangihayot'], 'Yangihayot', 6, 'Yangihayot'],
  ]) {
    match = numberedMatch(text, names);
    if (match) {
      const number = Number(match[1]);
      if (number >= 1 && number <= max) return result(`${canonical}-${number}`, district);
    }
  }

  for (const candidate of STATIC_MATCHERS) {
    if (phraseIn(text, candidate.alias)) return result(candidate.area, candidate.district);
  }

  const explicitSergeliDistrict = /(?:сергелийск\p{L}*\s+район|сергели\s+туман\p{L}*|serg(?:eli|ile|ele)\s+(?:tumani|district))/iu.test(value);
  if (!explicitSergeliDistrict && /(?:^|\s)(?:сергели|sergeli|sergile|sergele)(?:\s|$)/iu.test(text)) {
    return result('Sergeli', null, 0.35, true);
  }
  if (/(?:^|\s)(?:куйлюк|куйлик|kuylyuk|kuyliq|qoyliq)(?:\s|$)/iu.test(text)) {
    return result('Kuylyuk', null, 0.25, true);
  }
  const explicitChilanzarDistrict = /(?:чиланзарск\p{L}*\s+район|чиланзар\s+туман\p{L}*|chilanzar\s+district)/iu.test(value);
  if (!explicitChilanzarDistrict && /(?:^|\s)(?:чиланзар|чилонзор|chilanzar|chilonzor)(?:\s|$)/iu.test(text)) {
    return result('Chilanzar', null, 0.35, true);
  }

  return null;
}
