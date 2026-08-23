import { LOCATION_DICTIONARIES } from './location-dictionaries.js';
import { UA_EXTRA_LOCATION_DICTIONARIES } from './location-dictionaries-ua-extra.js';
import {
  UA_REGIONS,
  UA_SECONDARY_CITIES,
  matchUkraineRegion,
  matchUkraineSecondaryCity,
} from './location-dictionaries-ua-regions.js';
import { TASHKENT_METRO, tashkentMetroLabels } from './tashkent-metro.js';

function mergedCountry(countryCode) {
  const base = LOCATION_DICTIONARIES[countryCode] || {};
  if (countryCode === 'UZ' && base.Tashkent) {
    return {
      ...base,
      Tashkent: {
        ...base.Tashkent,
        // One authoritative list for both parser matching and filter metadata.
        metro: TASHKENT_METRO,
      },
    };
  }
  if (countryCode !== 'UA') return base;
  return { ...UA_EXTRA_LOCATION_DICTIONARIES, ...base };
}

export function dictionaryCities(countryCode) {
  return mergedCountry(countryCode);
}

export function dictionaryCity(countryCode, city) {
  return mergedCountry(countryCode)[city] || null;
}

/**
 * Hashtags run words together — "#метроБИЙ", "#МирзоУлугбекский", "#ЖКNestOne"
 * — and an alias that expects a word boundary never matches inside one. Only
 * hashtag tokens are split, so ordinary CamelCase names are left alone.
 */
function expandHashtags(text) {
  return String(text).replace(/#(\S+)/gu, (match, body) =>
    '#' + body.replace(/(\p{Ll}|\d)(\p{Lu})/gu, '$1 $2'),
  );
}

function normalizeMatchingText(text) {
  return expandHashtags(text)
    // Common Ukrainian/Russian locative/genitive forms used in listing prose.
    // This copy is used only for dictionary matching; listing text stays intact.
    .replace(/([\p{L}]+?)ії(?=$|[^\p{L}\p{N}_])/giu, '$1ія')
    .replace(/([\p{L}]+?)ии(?=$|[^\p{L}\p{N}_])/giu, '$1ия')
    .replace(/([\p{L}]+?)щині(?=$|[^\p{L}\p{N}_])/giu, '$1щина')
    .replace(/([\p{L}]+?)щине(?=$|[^\p{L}\p{N}_])/giu, '$1щина');
}

function matchMetro(text, entries) {
  const value = String(text);
  const matches = [];

  for (const entry of entries || []) {
    const match = value.match(entry.re);
    if (!match) continue;

    const start = match.index ?? 0;
    const end = start + match[0].length;
    const before = value.slice(Math.max(0, start - 16), start);
    const after = value.slice(end, end + 48);
    const contextual =
      /(?:метро|metro|станц(?:ия|ии)?|station)\s*[:\-–—]?\s*$/iu.test(before) ||
      /^\s*(?:метро|metro|station)(?=$|[^\p{L}\p{N}_])/iu.test(after);

    // `Chilonzor 12`, `Yunusobod 19`, etc. are numbered massifs/kvartals,
    // not subway mentions. Bare station-name matching is allowed elsewhere,
    // but a number immediately following the name requires metro context.
    const numberedArea = /^\s*[-№#]?\s*\d{1,3}(?=$|[\s,.;-])/u.test(after);
    if (!contextual && numberedArea) continue;

    // `метро Ташкент Северный вокзал` describes the railway-station landmark;
    // the short `Toshkent` subway match must not hide the more specific legacy
    // rule in locations.js that produces `Tashkent North Railway Station`.
    if (
      entry.name === 'Toshkent' &&
      /северн[а-яё]*\s+(?:железнодорожн[а-яё]*\s+)?вокзал|north\s+(?:railway\s+)?station/iu.test(after)
    ) {
      continue;
    }

    matches.push({entry, contextual});
  }

  return matches.find((item) => item.contextual)?.entry ?? matches[0]?.entry ?? null;
}

export function matchDictionaryEntities(text, countryCode, preferredCity = null) {
  const result = {
    region: null,
    city: null,
    district: null,
    microdistrict: null,
    metro: null,
    residentialComplex: null,
  };
  if (!text || !countryCode) return result;
  text = normalizeMatchingText(text);

  if (countryCode === 'UA') {
    result.region = matchUkraineRegion(text)?.name || null;
    const secondary = matchUkraineSecondaryCity(text);
    if (secondary) {
      result.city = secondary.city;
      const micro = (secondary.microdistricts || []).find((x) => x.re.test(text));
      if (micro) result.microdistrict = micro.name;
    }
  }

  const cities = mergedCountry(countryCode);
  const ordered = preferredCity && cities[preferredCity]
    ? [[preferredCity, cities[preferredCity]], ...Object.entries(cities).filter(([name]) => name !== preferredCity)]
    : Object.entries(cities);

  for (const [cityName, data] of ordered) {
    const district = (data.districts || []).find((x) => x.re.test(text));
    const microdistrict = (data.microdistricts || []).find((x) => x.re.test(text));
    const metro = matchMetro(text, data.metro);
    const residentialComplex = (data.residentialComplexes || []).find((x) => x.re.test(text));

    if (!result.district && district) result.district = district.name;
    if (!result.microdistrict && microdistrict) result.microdistrict = microdistrict.name;
    if (!result.metro && metro) result.metro = metro.name;
    if (!result.residentialComplex && residentialComplex) result.residentialComplex = residentialComplex.name;

    if (!result.city && (district || microdistrict || metro || residentialComplex)) result.city = cityName;
    if (result.district && result.microdistrict && result.metro && result.residentialComplex && result.city) break;
  }

  return result;
}

export function matchDictionaryResidentialComplex(text, countryCode = null, preferredCity = null) {
  if (!text) return null;
  const countries = countryCode ? [countryCode] : Object.keys(LOCATION_DICTIONARIES);
  if (!countryCode) countries.push('UA');
  for (const code of [...new Set(countries)]) {
    const match = matchDictionaryEntities(text, code, preferredCity);
    if (match.residentialComplex) return match.residentialComplex;
  }
  return null;
}

export function canonicalDictionaryDistrict(name, countryCode) {
  if (!name || !countryCode) return null;
  for (const data of Object.values(mergedCountry(countryCode))) {
    const match = (data.districts || []).find((entry) => entry.re.test(name));
    if (match) return match.name;
  }
  return null;
}

export function dictionaryLocationLists(countryCode) {
  const out = {};
  for (const [city, data] of Object.entries(mergedCountry(countryCode))) {
    out[city] = {
      districts: (data.districts || []).map((x) => x.name),
      metro: (data.metro || []).map((x) => x.name),
      microdistricts: (data.microdistricts || []).map((x) => x.name),
      residentialComplexes: (data.residentialComplexes || []).map((x) => x.name),
      ...(countryCode === 'UZ' && city === 'Tashkent' ? { metroLabels: tashkentMetroLabels() } : {}),
    };
  }
  return out;
}

export { UA_REGIONS, UA_SECONDARY_CITIES };
