import { canonicalCityName } from './countries.js';
import { geocodeBbox, geocodeQuery } from './geocode.js';

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
  // Only cross-check source coordinates when the parser found an actual house
  // number. A bare street geocodes to a street centroid and must not be allowed to
  // "correct" a valid source pin elsewhere on the same street.
  if (!listing?.addressStreet || !listing?.addressHouseNumber) return '';
  const address = [listing.addressStreet, listing.addressHouseNumber, listing.addressBuilding]
    .filter(Boolean)
    .join(' ');
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
 * OLX and other source feeds can expose deliberately rough or simply bad
 * coordinates. First keep the existing city-bbox guard for obvious outliers.
 * Then, when the shared parser extracted an exact street + house number, compare
 * the source pin with Nominatim's exact-address result. A materially different
 * exact address is stronger evidence than a marketplace's approximate pin, so
 * replace the source point directly instead of leaving the card on the wrong block.
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

    // Keep the listing's structured location fields: unlike a city-bbox outlier,
    // this correction is derived from those fields themselves. Reverse-geocoding
    // later in the enrichment pipeline can still normalize district/microdistrict.
    listing.sourceCoordinateRejected = true;
    listing.sourceCoordinateDistanceM = Math.round(discrepancyM);
    listing.lat = exact.lat;
    listing.lng = exact.lng;
    listing.locationSource = 'address';
    listing.locationAccuracyM = 40;
  }

  return rejected;
}
