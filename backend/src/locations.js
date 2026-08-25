import {
  GENERIC_LANDMARK_TERMS,
  aliasesOf,
  aliasesToRegex,
} from '@whiteslove/parsing-lexicon';
import { resolveTashkentArea } from './tashkent-areas.js';
import { TASHKENT_METRO } from './tashkent-metro.js';
import {
  canonicalDictionaryDistrict,
  dictionaryLocationLists,
  matchDictionaryEntities,
} from './location-dictionary-resolver.js';

const GENERIC_NEARBY = GENERIC_LANDMARK_TERMS.map((item) => ({
  name: item.canonical,
  re: aliasesToRegex([item.canonical, ...aliasesOf(item)]),
}));

const TASHKENT_COMPAT_LANDMARKS = [
  ['Bobur Park', /(?:^|[^\p{L}\p{N}_])(?:bobur\s+bog['’`i]*|бобур\s+парк)(?=$|[^\p{L}\p{N}_])/iu],
  ['Bus stop', /(?:avtobus|автобус)[^\r\n,;]{0,18}(?:kanichkasi|bekati|остановк)/iu],
  ['Clinic', /(?:poleklinika|poliklinika|поликлиник)/iu],
  ['School', /(?:^|[^\p{L}\p{N}_])(?:maktab|мактаб|школа)(?=$|[^\p{L}\p{N}_])/iu],
  ['Alay Bazaar', /(?:^|[^\p{L}\p{N}_])(?:алайск(?:ий|ого)|алай|alay)(?=$|[^\p{L}\p{N}_])/iu],
  ['C-2', /(?:^|[^\p{L}\p{N}_])(?:ц|c)\s*[-–]?\s*2(?=$|[^\p{L}\p{N}_])/iu],
  ['Darkhan', /(?:^|[^\p{L}\p{N}_])(?:дархан|darkhan)(?=$|[^\p{L}\p{N}_])/iu],
  ['Novomoskovskaya', /(?:^|[^\p{L}\p{N}_])(?:новомосковск(?:ая|ой)|novomoskovskaya)(?=$|[^\p{L}\p{N}_])/iu],
  ['Yangi Choshtepa', /(?:^|[^\p{L}\p{N}_])(?:янги\s+чоштепа|yangi\s+choshtepa)(?=$|[^\p{L}\p{N}_])/iu],
  ['Sergeli Car Bazaar', /(?:^|[^\p{L}\p{N}_])(?:serg(?:eli|ile|ele)|сергели)[^\r\n]{0,24}(?:mashina|moshena|машин)[^\r\n]{0,12}(?:bozor|бозор|базар|рынок)(?=$|[^\p{L}\p{N}_])/iu],
  ['Nizami Pedagogical University', /(?:низомий|nizomiy)[^\r\n]{0,35}(?:universitet|университет)/iu],
  ['World Languages University', /(?:жахон|жаҳон|jahon)[^\r\n]{0,35}(?:tillar|тиллар)[^\r\n]{0,25}(?:universitet|университет)/iu],
];

function explicitTashkentMetro(text) {
  if (/(?:ташкент|toshkent)\s+северн\p{L}*\s+вокзал/iu.test(text)) return 'Tashkent North Railway Station';
  const explicit = String(text).match(/(?:метро|metro|м\.)\s*[:\-–—]?\s*([^\n,.;]{2,52})/iu)?.[1] || '';
  if (explicit) {
    for (const station of TASHKENT_METRO) {
      if (station.re.test(explicit)) return station.name;
    }
  }
  const beforeMarker = String(text).match(/(?:^|[^\p{L}\p{N}_])([\p{L}'’`-]{3,28})\s+metro(?:da|ga)?(?=$|[^\p{L}\p{N}_])/iu)?.[1] || '';
  if (beforeMarker) {
    if (/^serg(?:eli|ile|ele)$/iu.test(beforeMarker)) return 'Sergeli';
    for (const station of TASHKENT_METRO) {
      if (station.re.test(beforeMarker)) return station.name;
    }
  }
  return null;
}

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

    const explicitMetro = explicitTashkentMetro(text);
    if (explicitMetro) {
      result.metro = explicitMetro;
      result.nearby = result.nearby.filter((name) => name !== explicitMetro && !(explicitMetro === 'Tashkent North Railway Station' && name === 'Railway station'));
    }
    if (result.metro === 'Chilonzor' && /(?:чилонзор|chilonzor|чиланзар|chilanzar)\s*[-№#]?\s*\d{1,2}(?!\d)/iu.test(text) && !/(?:чилонзор|chilonzor|чиланзар|chilanzar)\s+metro/iu.test(text)) {
      result.metro = null;
    }

    for (const [name, re] of TASHKENT_COMPAT_LANDMARKS) {
      if (!re.test(text)) continue;
      result.city ||= 'Tashkent';
      if (!result.nearby.includes(name)) result.nearby.push(name);
    }
  }

  for (const item of GENERIC_NEARBY) {
    if (item.name === 'Metro') continue;
    if (item.name === 'Railway station' && result.metro === 'Tashkent North Railway Station') continue;
    if (item.name === 'Market' && result.nearby.some((name) => /Bazaar$/i.test(name))) continue;
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
