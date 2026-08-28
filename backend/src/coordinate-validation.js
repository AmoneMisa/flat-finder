import { canonicalCityName } from './countries.js';
import { geocodeBbox, geocodeQuery } from './geocode.js';
import { applyStructuredAddressFields } from './structured-address.js';

const DEFAULT_PADDING_DEG = 0.02;
const DEFAULT_EXACT_ADDRESS_MAX_DISTANCE_M = 150;
const EARTH_RADIUS_M = 6_371_000;
const bboxPromises = new Map();
const exactAddressPromises = new Map();

export function coordinateInsideBbox(lat, lng, bbox, padding = DEFAULT_PADDING_DEG) {
  if (!Number.isFinite(Number(lat)) || !Number.isFinite(Number(lng))) return false;
  if (!Array.isArray(bbox) || bbox.length !== 4 || !bbox.every(Number.isFinite)) return true;

  const [south, west, north, east] = bbox;
  return Number(lat) >= south - padding
    && Number(lat) <= north + padding
    && Number(lng) >= west - padding
    && Number(lng) <= east + padding;
}

function distanceM(a, b) {
  const toRad = (value) => (Number(value) * Math.PI) / 180;
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const dLat = lat2 - lat1;
  const dLng = toRad(b.lng) - toRad(a.lng);
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

async function bboxFor(country, area) {
  const query = [area, country?.name].filter(Boolean).join(', ');
  if (!query) return null;

  const key = `${country?.code || ''}:${String(area).toLowerCase()}`;
  if (!bboxPromises.has(key)) {
    bboxPromises.set(key, geocodeBbox(query).catch(() => null));
  }
  return bboxPromises.get(key);
}

function exactAddressQuery(listing, country, city) {
  // The structured-address adapter delegates the actual prose interpretation to
  // parsing-lexicon. Cross-check only when it resolved a house number; a bare
  // street would geocode to a centroid and is not strong enough to move a pin.
  const street = listing?.street || listing?.addressStreet;
  const houseNumber = listing?.houseNumber || listing?.addressHouseNumber;
  const building = listing?.building || listing?.addressBuilding;
  if (!street || !houseNumber) return '';
  const address = [street, houseNumber, building].filter(Boolean).join(' ');
  return [address, listing.district, city, country?.name].filter(Boolean).join(', ');
}

async function exactAddressCoordinate(listing, country, city) {
  const query = exactAddressQuery(listing, country, city);
  if (!query) return null;
  const key = query.toLocaleLowerCase();
  if (!exactAddressPromises.has(key)) {
    exactAddressPromises.set(key, geocodeQuery(query).catch(() => null));
  }
  return exactAddressPromises.get(key);
}

/**
 * Marketplace coordinates can be deliberately rough or simply wrong. Keep the
 * city-bbox guard for obvious outliers, then cross-check an existing source pin
 * against an exact street + house number parsed by the shared lexicon. When the
 * exact address disagrees materially, the address wins and is persisted as the
 * map point instead of treating every source coordinate as 25 m accurate.
 */
export async function rejectOutOfAreaCoordinates(
  listings,
  country,
  { areaHint = null } = {},
) {
  if (!Array.isArray(listings) || !country) return [];

  const configured = Number(process.env.SOURCE_COORD_BBOX_PADDING_DEG);
  const padding = Number.isFinite(configured) && configured >= 0
    ? configured
    : DEFAULT_PADDING_DEG;
  const configuredAddressDistance = Number(process.env.SOURCE_COORD_ADDRESS_MAX_DISTANCE_M);
  const exactAddressMaxDistanceM = Number.isFinite(configuredAddressDistance) && configuredAddressDistance >= 0
    ? configuredAddressDistance
    : DEFAULT_EXACT_ADDRESS_MAX_DISTANCE_M;
  const rejected = [];

  for (const listing of listings) {
    // Run the shared address parser before coordinate validation. The persistent
    // geocoder also does this later, but OLX validation intentionally happens first.
    applyStructuredAddressFields(listing);

    // makeListing has a cheap synchronous Odesa guard for the legacy cache path.
    // Keep those rows in this return set even though their bad coordinates have
    // already been cleared, so the durable queue immediately repairs them too.
    if (listing?.sourceCoordinateRejected === true && (listing.lat == null || listing.lng == null)) {
      rejected.push(listing);
      continue;
    }

    if (!Number.isFinite(Number(listing?.lat)) || !Number.isFinite(Number(listing?.lng))) {
      continue;
    }

    const area = areaHint || canonicalCityName(country.code, listing.city || '');
    if (!area) continue;

    const bbox = await bboxFor(country, area);
    if (bbox && !coordinateInsideBbox(listing.lat, listing.lng, bbox, padding)) {
      listing.sourceCoordinateRejected = true;
      listing.lat = null;
      listing.lng = null;

      // The same source location block supplied the contradictory district. Once
      // its map point is impossible, let repaired coordinates rebuild finer admin
      // fields instead of preserving e.g. Arcadia + Kyivskyi district.
      listing.district = null;
      listing.microdistrict = null;
      listing.locationSource = 'source-coordinate-rejected';
      listing.locationAccuracyM = null;
      rejected.push(listing);
      continue;
    }

    const exact = await exactAddressCoordinate(listing, country, area);
    if (!exact) continue;
    const discrepancyM = distanceM(
      { lat: Number(listing.lat), lng: Number(listing.lng) },
      exact,
    );
    if (!Number.isFinite(discrepancyM) || discrepancyM <= exactAddressMaxDistanceM) continue;

    // This is a repair rather than an outlier rejection, so keep structured admin
    // fields and let the normal reverse-geo pass normalize them later.
    listing.sourceCoordinateRejected = true;
    listing.sourceCoordinateDistanceM = Math.round(discrepancyM);
    listing.lat = exact.lat;
    listing.lng = exact.lng;
    listing.locationSource = 'address';
    listing.locationAccuracyM = 40;
  }

  return rejected;
}
