// Turns a coordinate into "what is around here", using only rows already loaded
// from the places table. No network, no per-listing cost — a batch of listings
// shares one load and each one is a pass over an array.

const EARTH_RADIUS_M = 6_371_000;

// How far each kind is still worth mentioning. A supermarket 300 m away matters;
// a supermarket 2 km away is not "nearby". Landmarks and metro carry further —
// people describe a flat as being "at Tashkent City" from a fair distance.
const KIND_RADIUS_M = {
  metro: 2500,
  landmark: 3000,
  mall: 2000,
  supermarket: 900,
  market: 1500,
  pharmacy: 700,
  clinic: 1500,
  school: 1000,
  kindergarten: 800,
  park: 1200,
  historic: 2000,
  cinema: 2000,
  transport: 600,
};

const DEFAULT_RADIUS_M = 1000;
const DEFAULT_PER_KIND = 3;

function toRadians(degrees) {
  return (degrees * Math.PI) / 180;
}

export function distanceM(a, b) {
  const dLat = toRadians(b.lat - a.lat);
  const dLng = toRadians(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(a.lat)) * Math.cos(toRadians(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Groups places by kind once per batch. Also keeps a flat list so a caller can
 * ask across kinds without re-walking the groups.
 */
export function indexPlaces(rows) {
  const byKind = new Map();
  for (const row of rows || []) {
    if (!Number.isFinite(row?.lat) || !Number.isFinite(row?.lng)) continue;
    const bucket = byKind.get(row.kind);
    if (bucket) bucket.push(row);
    else byKind.set(row.kind, [row]);
  }
  return byKind;
}

/** The closest `limit` places of one kind, nearest first. */
export function nearestOfKind(point, index, kind, { limit = DEFAULT_PER_KIND, radiusM } = {}) {
  const rows = index.get(kind) || [];
  const max = radiusM ?? KIND_RADIUS_M[kind] ?? DEFAULT_RADIUS_M;
  const hits = [];

  for (const row of rows) {
    // Cheap rejection before the trigonometry: one degree of latitude is ~111 km,
    // and at Tashkent's latitude a degree of longitude is ~83 km.
    if (Math.abs(row.lat - point.lat) * 111_000 > max) continue;
    if (Math.abs(row.lng - point.lng) * 83_000 > max) continue;

    const distance = distanceM(point, row);
    if (distance <= max) {
      hits.push({ name: row.name, nameRu: row.nameRu || null, kind, distanceM: Math.round(distance) });
    }
  }

  // OSM carries a node per platform and per entrance, so one bus stop can
  // appear three times under the same name. Keep the closest of each name.
  const byName = new Map();
  for (const hit of hits.sort((a, b) => a.distanceM - b.distanceM)) {
    const key = hit.name.toLowerCase();
    if (!byName.has(key)) byName.set(key, hit);
  }

  return [...byName.values()].slice(0, limit);
}

/**
 * Everything worth naming around a point, grouped by kind and flattened into a
 * distance-sorted list for display.
 */
export function placesNear(point, index, { perKind = DEFAULT_PER_KIND, kinds } = {}) {
  const wanted = kinds || [...index.keys()];
  const grouped = {};
  const flat = [];

  for (const kind of wanted) {
    const hits = nearestOfKind(point, index, kind, { limit: perKind });
    if (!hits.length) continue;
    grouped[kind] = hits;
    flat.push(...hits);
  }

  return { grouped, flat: flat.sort((a, b) => a.distanceM - b.distanceM) };
}

/**
 * Annotates one listing with its surroundings. Metro keeps its own fields for
 * backwards compatibility: `metro` stays the single closest station, and never
 * overwrites a station the post itself named.
 */
export function annotateListing(listing, index, { perKind = DEFAULT_PER_KIND } = {}) {
  if (!Number.isFinite(listing?.lat) || !Number.isFinite(listing?.lng)) return false;
  const point = { lat: listing.lat, lng: listing.lng };

  const stations = nearestOfKind(point, index, 'metro', { limit: perKind });
  if (stations.length) {
    listing.metroNearby = stations.map(({ name, nameRu, distanceM: distance }) => ({
      name,
      nameRu,
      distanceM: distance,
    }));
    if (!listing.metro) {
      listing.metro = stations[0].name;
      listing.metroSource = 'coordinates';
      listing.metroDistanceM = stations[0].distanceM;
    }
  }

  const { grouped, flat } = placesNear(point, index, {
    perKind,
    kinds: [...index.keys()].filter((kind) => kind !== 'metro'),
  });

  if (flat.length) {
    listing.nearbyPlaces = flat.slice(0, 15);
    listing.nearbyByKind = grouped;
    listing.landmarksNearby = grouped.landmark || [];
    listing.placesSource = 'coordinates';
  }

  return Boolean(stations.length || flat.length);
}

/** Annotates a whole batch from one loaded place list. */
export function annotateListings(listings, rows, options) {
  const index = indexPlaces(rows);
  if (!index.size) return 0;
  let annotated = 0;
  for (const listing of listings || []) {
    if (annotateListing(listing, index, options)) annotated += 1;
  }
  return annotated;
}
