// Fills the `places` table for a city: one Overpass pull for everyday POIs,
// plus the named destinations people actually mention in listings ("рядом
// Tashkent City", "возле IT Park") and the metro stations.
//
// Run on a schedule, not on the request path — a city's shops do not move
// between refreshes.

import { upsertPlaces } from './places-db.js';
import { TASHKENT_METRO } from './tashkent-metro.js';

const OVERPASS_URL = process.env.OVERPASS_URL || 'https://overpass-api.de/api/interpreter';
const UA = 'flat-finder/1.0 (housing aggregator; contact: admin@whiteslove.me)';
const OVERPASS_TIMEOUT_MS = 180_000;

// Cities we enrich, with the box the Overpass query covers.
export const PLACE_CITIES = [
  {
    country: 'UZ',
    city: 'Tashkent',
    bbox: [41.15, 69.1, 41.4, 69.45],
    // Big destinations by name: OSM tags them inconsistently (a business
    // centre, a landuse area, an office), so they are resolved by name rather
    // than by tag and kept as `landmark`.
    landmarks: [
      'Tashkent City',
      'IT Park',
      'Legion',
      'Magic City',
      'Chorsu Bazaar',
      'Alay Bazaar',
      'Mega Planet',
      'Samarqand Darvoza',
      'Compass Mall',
      'Next Mall',
      'Amir Timur Square',
      'Hazrati Imam Complex',
      'Minor Mosque',
      'Tashkent Botanical Garden',
      'Japanese Garden Tashkent',
      'Tashkent Railway Station',
      'Islam Karimov Tashkent International Airport',
    ],
  },
];

// Overpass tag -> our kind. Everything here is something a renter or buyer
// would count as "what is around this flat".
const KIND_RULES = [
  { kind: 'mall', match: (t) => t.shop === 'mall' || t.shop === 'department_store' },
  { kind: 'supermarket', match: (t) => t.shop === 'supermarket' || t.shop === 'convenience' },
  { kind: 'market', match: (t) => t.amenity === 'marketplace' },
  { kind: 'pharmacy', match: (t) => t.amenity === 'pharmacy' },
  { kind: 'clinic', match: (t) => t.amenity === 'hospital' || t.amenity === 'clinic' || t.amenity === 'doctors' },
  { kind: 'school', match: (t) => t.amenity === 'school' || t.amenity === 'university' || t.amenity === 'college' },
  { kind: 'kindergarten', match: (t) => t.amenity === 'kindergarten' },
  { kind: 'park', match: (t) => t.leisure === 'park' || t.leisure === 'garden' },
  { kind: 'historic', match: (t) => Boolean(t.historic) || t.tourism === 'museum' || t.tourism === 'attraction' },
  { kind: 'cinema', match: (t) => t.amenity === 'cinema' || t.amenity === 'theatre' },
  { kind: 'transport', match: (t) => t.highway === 'bus_stop' || t.railway === 'station' || t.public_transport === 'station' },
];

function overpassQuery([south, west, north, east]) {
  const box = `(${south},${west},${north},${east})`;
  // Split per category and raise the cap: a single mixed query hit the 3000
  // element limit and silently dropped whole categories.
  return `[out:json][timeout:180];
(
  node["shop"~"^(supermarket|convenience|mall|department_store)$"]${box};
  way["shop"~"^(supermarket|mall|department_store)$"]${box};
  node["amenity"~"^(marketplace|pharmacy|hospital|clinic|doctors|school|university|college|kindergarten|cinema|theatre)$"]${box};
  way["amenity"~"^(marketplace|hospital|school|university)$"]${box};
  node["leisure"~"^(park|garden)$"]${box};
  way["leisure"~"^(park|garden)$"]${box};
  node["historic"]${box};
  way["historic"]${box};
  node["tourism"~"^(attraction|museum)$"]${box};
  node["railway"="station"]${box};
  node["highway"="bus_stop"]${box};
);
out center tags 12000;`;
}

function elementToRow(element, { country, city }) {
  const tags = element.tags || {};
  const name = tags['name:en'] || tags.name || tags['name:ru'] || '';
  if (!name) return null;

  const lat = element.lat ?? element.center?.lat;
  const lng = element.lon ?? element.center?.lon;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;

  const rule = KIND_RULES.find((candidate) => candidate.match(tags));
  if (!rule) return null;

  return {
    country,
    city,
    kind: rule.kind,
    name,
    name_ru: tags['name:ru'] || null,
    lat,
    lng,
    source: 'overpass',
    external_id: `${element.type}/${element.id}`,
    tags: {},
  };
}

async function fetchOverpass(bbox) {
  const res = await fetch(OVERPASS_URL, {
    method: 'POST',
    headers: { 'User-Agent': UA, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ data: overpassQuery(bbox) }),
    signal: AbortSignal.timeout(OVERPASS_TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`overpass ${res.status}`);
  const data = await res.json();
  return Array.isArray(data?.elements) ? data.elements : [];
}

/**
 * Named destinations and metro stations, resolved through the geocoder.
 * `lookup(query)` is the same cached+throttled resolver the geocoder uses.
 */
async function namedRows(config, lookup) {
  if (typeof lookup !== 'function') return [];
  const rows = [];

  for (const name of config.landmarks || []) {
    const coords = await lookup(`${name}, ${config.city}, ${config.country === 'UZ' ? 'Uzbekistan' : ''}`);
    if (!coords) continue;
    rows.push({
      country: config.country,
      city: config.city,
      kind: 'landmark',
      name,
      name_ru: null,
      lat: coords.lat,
      lng: coords.lng,
      source: 'curated',
      external_id: name.toLowerCase().replace(/\s+/g, '-'),
      tags: {},
    });
  }

  if (config.country === 'UZ' && config.city === 'Tashkent') {
    for (const station of TASHKENT_METRO) {
      const coords =
        (await lookup(`${station.labels?.en || station.name}, Tashkent, Uzbekistan`)) ||
        (station.labels?.ru ? await lookup(`метро ${station.labels.ru} Ташкент`) : null);
      if (!coords) continue;
      rows.push({
        country: 'UZ',
        city: 'Tashkent',
        kind: 'metro',
        name: station.name,
        name_ru: station.labels?.ru || null,
        lat: coords.lat,
        lng: coords.lng,
        source: 'curated',
        external_id: station.name.toLowerCase().replace(/\s+/g, '-'),
        tags: { line: station.line || null },
      });
    }
  }

  return rows;
}

/** Refills one city. Returns how many rows were written, per source. */
export async function syncCityPlaces(config, lookup) {
  const elements = await fetchOverpass(config.bbox);
  const overpassRows = elements
    .map((element) => elementToRow(element, config))
    .filter(Boolean);

  const named = await namedRows(config, lookup);
  const saved = await upsertPlaces([...overpassRows, ...named]);

  console.log(
    `[places] ${config.country}/${config.city}: ${overpassRows.length} from overpass, ` +
    `${named.length} named, ${saved} saved`,
  );
  return { overpass: overpassRows.length, named: named.length, saved };
}

export async function syncAllPlaces(lookup) {
  const results = [];
  for (const config of PLACE_CITIES) {
    try {
      results.push({ city: config.city, ...(await syncCityPlaces(config, lookup)) });
    } catch (error) {
      console.error(`[places] ${config.city} sync failed:`, error?.message || error);
    }
  }
  return results;
}
