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
  text = expandHashtags(text);

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
    const metro = (data.metro || []).find((x) => x.re.test(text));
    const residentialComplex = (data.residentialComplexes || []).find((x) => x.re.test(text));

    if (!result.district && district) result.district = district.name;
    if (!result.microdistrict && microdistrict) result.microdistrict = microdistrict.name;
    if (!result.metro && metro) result.metro = metro.name;
    if (!result.residentialComplex && residentialComplex) result.residentialComplex = residentialComplex.name;

    if (!result.city && (district || metro || residentialComplex)) result.city = cityName;
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
