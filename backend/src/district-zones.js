// District colour zones for the map's choropleth-style district overlay.
// Ports whiteslove.me's app/composables/flats/useDistrictZones.ts district
// logic to the server so the mobile app can render the same colours/shapes
// without needing a geo-catalog client of its own (Dart can't import it).
import { findGeoEntities, resolveLexiconGeoEntity } from '@whiteslove/geo-catalog';

// Keep in sync with ZONE_PALETTE in the site's useDistrictZones.ts.
export const ZONE_PALETTE = Object.freeze(['#e0679a', '#24a7d6', '#10b981', '#d99a0b', '#8b5cf6']);

const EARTH_RADIUS_M = 6371000;

function distanceM(a, b) {
  const toRad = (v) => (v * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const h = sinLat * sinLat + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinLng * sinLng;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

// Radius is only used for entities that have no real boundary polygon.
function fitNonOverlappingRadii(zones, min, max) {
  return zones.map((zone, index) => {
    if (zone.boundary) return zone;
    let nearest = Infinity;
    for (let other = 0; other < zones.length; other += 1) {
      if (other === index) continue;
      const d = distanceM(zone, zones[other]);
      if (d < nearest) nearest = d;
    }
    const neighborCap = Number.isFinite(nearest) ? (nearest / 2) * 0.9 : max;
    const radiusM = Math.max(min, Math.min(zone.radiusM, neighborCap, max));
    return {...zone, radiusM};
  });
}

function zoneFromEntity(entity, index) {
  return {
    id: entity.id,
    name: entity.canonicalName,
    lat: entity.center.lat,
    lng: entity.center.lng,
    radiusM: entity.accuracyM || 400,
    color: ZONE_PALETTE[index % ZONE_PALETTE.length],
    boundary: entity.boundary || null,
  };
}

function descendantsOf(cityId, country, type) {
  if (!cityId) return [];
  const prefix = `${cityId}:`;
  return findGeoEntities({country, type}).filter(
    (entity) => entity.parentId === cityId || entity.id.startsWith(prefix),
  );
}

/**
 * District colour zones for one city, matching the site's map exactly:
 * each administrative district gets a stable palette colour cycling through
 * ZONE_PALETTE, and its real OSM boundary polygon when the catalog has one
 * (falling back to a non-overlapping circle radius otherwise).
 */
export function districtZonesFor(countryCode, cityName, districtOptions = []) {
  const country = String(countryCode || '').toUpperCase();
  if (!country || !cityName) return [];

  const cityEntity = resolveLexiconGeoEntity({country, type: 'city', canonical: cityName});
  const canonical = descendantsOf(cityEntity?.id ?? null, country, 'district');
  const entities = canonical.length
    ? canonical
    : districtOptions
      .map((name) => resolveLexiconGeoEntity({country, city: cityName, type: 'district', canonical: name}))
      .filter(Boolean);

  const zones = entities.map((entity, index) => zoneFromEntity(entity, index));
  return fitNonOverlappingRadii(zones, 350, 1800);
}
