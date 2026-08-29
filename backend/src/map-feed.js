import { searchPostgresListings } from './postgres-search.js';
import { attachMarketComparisons } from './market-comparison.js';

const MAP_PAGE_SIZE = 60;
const MAP_MAX_POINTS = Math.max(60, Math.min(Number(process.env.MAP_FEED_MAX_POINTS) || 3000, 10000));

function finiteCoordinate(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function mapPointFromListing(listing) {
  const lat = finiteCoordinate(listing?.lat);
  const lng = finiteCoordinate(listing?.lng);
  if (lat == null || lng == null || Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;

  return {
    id: String(listing?.id ?? ''),
    source: String(listing?.source || ''),
    country: String(listing?.country || '').toUpperCase(),
    lat,
    lng,
    title: String(listing?.title || ''),
    price: listing?.price != null && Number.isFinite(Number(listing.price)) ? Number(listing.price) : null,
    currency: String(listing?.currency || ''),
    publicId: Number.isInteger(Number(listing?.publicId)) ? Number(listing.publicId) : null,
    city: String(listing?.city || ''),
    district: listing?.district ? String(listing.district) : null,
    dealType: listing?.dealType ? String(listing.dealType) : null,
    roomOnly: listing?.roomOnly === true,
    byAgency: listing?.byAgency === true,
    propertyType: String(listing?.propertyType || 'flat'),
    rooms: listing?.rooms == null ? null : Number(listing.rooms),
    areaSqm: listing?.areaSqm == null ? null : Number(listing.areaSqm),
    photo: listing?.photo ? String(listing.photo) : null,
    createdAt: listing?.createdAt || null,
  };
}

/**
 * Reuses the authoritative PostgreSQL search path so map points and cards have
 * exactly the same filters and dedupe semantics. Pages are consumed internally
 * and only a compact point shape leaves the backend.
 */
export async function searchPostgresMapPoints({ filters, countries, rates = null, searchMatches = null }) {
  const startedAt = performance.now();
  const points = [];
  const seen = new Set();
  let cursor = '';
  let count = 0;
  let pages = 0;
  let truncated = false;

  do {
    const pageFilters = {
      ...filters,
      includeStats: false,
      statsOnly: false,
      offset: 0,
      limit: MAP_PAGE_SIZE,
      cursor,
      sort: 'newest',
    };

    const result = await searchPostgresListings({
      filters: pageFilters,
      countries,
      rates,
      searchMatches,
    });
    if (pages === 0) count = Number(result.count) || 0;
    pages += 1;

    for (const listing of result.listings || []) {
      const point = mapPointFromListing(listing);
      if (!point?.id) continue;
      const key = `${point.source}:${point.country}:${point.id}`;
      if (seen.has(key)) continue;
      seen.add(key);
      points.push(point);
      if (points.length >= MAP_MAX_POINTS) break;
    }

    cursor = String(result.nextCursor || '');
    if (points.length >= MAP_MAX_POINTS) {
      truncated = Boolean(cursor) || count > points.length;
      break;
    }
  } while (cursor);

  let enrichedPoints = points;
  if (points.length && rates) {
    try {
      enrichedPoints = await attachMarketComparisons(points, rates);
    } catch (err) {
      console.warn('[map-feed] market comparison failed:', err?.message ?? err);
    }
  }

  return {
    count,
    points: enrichedPoints,
    truncated,
    pages,
    maxPoints: MAP_MAX_POINTS,
    queryMs: Math.round((performance.now() - startedAt) * 10) / 10,
  };
}
