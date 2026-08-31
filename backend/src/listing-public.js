import {enrichListingDetails} from './listing-enrichment.js';
import {geocodeListings} from './geocode.js';
import {getRates} from './fx.js';
import {attachMarketComparisons} from './market-comparison.js';
import {annotateNearbyTransport} from './transport-nearby.js';

const TRANSIENT_DERIVED_FIELDS = [
  'nearbyMetro',
  'nearbyTransport',
  'metroNearby',
  'metroSource',
  'metroDistanceM',
  'transportSource',
  'marketComparison',
];

function hasFiniteCoordinates(listing) {
  return Number.isFinite(Number(listing?.lat)) && Number.isFinite(Number(listing?.lng));
}

function copyGeoProvenance(target, source) {
  for (const key of ['locationSource', 'locationAccuracyM', 'locationAnchorCount']) {
    if (Object.prototype.hasOwnProperty.call(source || {}, key)) target[key] = source[key];
    else delete target[key];
  }
}

/**
 * Merge a live source refresh with the richer normalized snapshot already kept
 * in PostgreSQL. Fresh source fields win, while fields the source adapter does
 * not know how to produce (vision/provenance/etc.) survive the refresh.
 *
 * Transport and market fields are deliberately removed: they depend on the
 * final coordinates/price and must be recalculated rather than copied stale.
 */
export function mergeStoredFreshListing(stored, fresh) {
  const previous = stored && typeof stored === 'object' ? stored : {};
  const current = fresh && typeof fresh === 'object' ? fresh : {};
  const merged = {...previous, ...current};

  const freshHasCoordinates = hasFiniteCoordinates(current);
  const storedHasCoordinates = hasFiniteCoordinates(previous);

  if (freshHasCoordinates) {
    merged.lat = Number(current.lat);
    merged.lng = Number(current.lng);
    // A fresh source point invalidates provenance belonging to the old point.
    // If a source adapter eventually starts providing its own provenance, keep it.
    copyGeoProvenance(merged, current);
  } else if (storedHasCoordinates && current.sourceCoordinateRejected !== true) {
    // A source that simply omitted coordinates must not erase a previously
    // derived/validated point. geocodeListings can still refine its metadata.
    merged.lat = Number(previous.lat);
    merged.lng = Number(previous.lng);
    copyGeoProvenance(merged, previous);
  }

  for (const key of TRANSIENT_DERIVED_FIELDS) delete merged[key];
  return merged;
}

async function attachMarketComparison(listing) {
  try {
    const {rates} = await getRates();
    const [withMarket] = await attachMarketComparisons([listing], rates);
    return withMarket || listing;
  } catch (error) {
    console.warn('[listing-public] market comparison failed:', error?.message ?? error);
    return listing;
  }
}

async function attachTransport(listing, country) {
  if (!listing || !country) return listing;
  try {
    await annotateNearbyTransport([listing], country);
  } catch (error) {
    console.warn('[listing-public] transport enrichment failed:', error?.message ?? error);
  }
  return listing;
}

/**
 * Final response pipeline shared by every single-listing endpoint.
 * A live source refresh opts into geo refinement so source coordinates receive
 * the same locationAccuracyM/provenance used by the normal ingestion pipeline
 * before transport eligibility is evaluated.
 */
export async function preparePublicListing(listing, country, {refreshGeo = false} = {}) {
  if (!listing) return listing;
  let prepared = enrichListingDetails(listing);
  if (refreshGeo && country) {
    try {
      [prepared] = await geocodeListings([prepared], country);
    } catch (error) {
      console.warn('[listing-public] geo refinement failed:', error?.message ?? error);
    }
  }
  prepared = await attachMarketComparison(prepared);
  await attachTransport(prepared, country);
  return prepared;
}

export const __listingPublicTest = {
  hasFiniteCoordinates,
  TRANSIENT_DERIVED_FIELDS,
};
