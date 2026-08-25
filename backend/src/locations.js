import {
  GENERIC_LANDMARK_TERMS,
  aliasesOf,
  aliasesToRegex,
} from '@whiteslove/parsing-lexicon';
import { resolveTashkentArea } from './tashkent-areas.js';
import {
  canonicalDictionaryDistrict,
  dictionaryLocationLists,
  matchDictionaryEntities,
} from './location-dictionary-resolver.js';

const GENERIC_NEARBY = GENERIC_LANDMARK_TERMS.map((item) => ({
  name: item.canonical,
  re: aliasesToRegex([item.canonical, ...aliasesOf(item)]),
}));

export function parseLocation(text, countryCode, preferredCity = null) {
  const result = {
    region: null,
    district: null,
    microdistrict: null,
    residentialComplex: null,
    street: null,
    area: null,
    areaAmbiguous: false,
    locationConfidence: null,
    requireExactAddress: false,
    metro: null,
    landmarkCategory: null,
    nearby: [],
    city: null,
    locality: null,
    mahallas: [],
    localAreas: [],
    suburbs: [],
    settlements: [],
    informalAreas: [],
    developmentAreas: [],
    searchClusters: [],
    locationEntities: [],
  };
  if (!text) return result;

  const dictionary = matchDictionaryEntities(text, countryCode, preferredCity);
  result.region = dictionary.region;
  result.microdistrict = dictionary.microdistrict;
  result.residentialComplex = dictionary.residentialComplex;
  result.street = dictionary.street;
  result.city = dictionary.city;
  result.district = dictionary.district;
  result.metro = dictionary.metro;
  result.landmarkCategory = dictionary.landmarkCategory || null;
  result.locality = dictionary.locality || null;
  result.mahallas = [...(dictionary.mahallas || [])];
  // Existing Listing persistence already stores localAreas and locationEntities.
  // Mirror mahallas into localAreas for backward-compatible filtering while
  // retaining the precise `mahalla` type in locationEntities.
  result.localAreas = [...new Set([...(dictionary.localAreas || []), ...(dictionary.mahallas || [])])];
  result.suburbs = [...(dictionary.suburbs || [])];
  result.settlements = [...(dictionary.settlements || [])];
  result.informalAreas = [...(dictionary.informalAreas || [])];
  result.developmentAreas = [...(dictionary.developmentAreas || [])];
  result.searchClusters = [...(dictionary.searchClusters || [])];
  result.locationEntities = [...(dictionary.locationEntities || [])];
  if (dictionary.landmark) result.nearby.push(dictionary.landmark);

  // Tashkent's colloquial area resolver also handles legacy/historical place names
  // and remains domain logic; its lexical source is separate from generic geo entities.
  if (countryCode === 'UZ') {
    const resolvedArea = resolveTashkentArea(text);
    if (resolvedArea) {
      result.area = resolvedArea.area;
      result.district = resolvedArea.district || result.district;
      result.areaAmbiguous = resolvedArea.ambiguous;
      result.locationConfidence = resolvedArea.confidence;
      result.requireExactAddress = resolvedArea.requireExactAddress;
      result.city = 'Tashkent';
    }
  }

  for (const item of GENERIC_NEARBY) {
    if (result.nearby.length >= 6) break;
    if (item.name === 'Park' && result.nearby.some((name) => /Park$/i.test(name))) continue;
    if (item.re.test(text) && !result.nearby.includes(item.name)) result.nearby.push(item.name);
  }
  return result;
}

export function canonicalDistrict(name, countryCode) {
  if (!name || typeof name !== 'string') return name || null;
  return canonicalDictionaryDistrict(name, countryCode) || name;
}

export function cityLocations(countryCode) {
  const extended = dictionaryLocationLists(countryCode);
  return Object.fromEntries(Object.entries(extended).map(([city, data]) => [city, {
    districts: [...new Set(data.districts || [])],
    metro: [...new Set(data.metro || [])],
    microdistricts: [...new Set(data.microdistricts || [])],
    mahallas: [...new Set(data.mahallas || [])],
    localAreas: [...new Set(data.localAreas || [])],
    suburbs: [...new Set(data.suburbs || [])],
    settlements: [...new Set(data.settlements || [])],
    residentialComplexes: [...new Set(data.residentialComplexes || [])],
    streets: [...new Set(data.streets || [])],
    landmarks: [...new Set(data.landmarks || [])],
    ...(data.metroLabels ? { metroLabels: data.metroLabels } : {}),
    ...(data.poiGroups ? { poiGroups: data.poiGroups } : {}),
    ...(data.metropolitanEntities ? { metropolitanEntities: data.metropolitanEntities } : {}),
    ...(data.searchClusters ? { searchClusters: data.searchClusters } : {}),
  }]));
}
