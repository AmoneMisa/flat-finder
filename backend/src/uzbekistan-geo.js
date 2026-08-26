import { canonicalUzbekistanCity } from '@whiteslove/parsing-lexicon';
import { uzbekistanCoordinateFallback } from '@whiteslove/parsing-lexicon/uz-geo-coordinates';

export function applyUzbekistanCoordinateFallbacks(listings) {
  if (!Array.isArray(listings)) return listings;

  for (const listing of listings) {
    if (!listing) continue;

    const city = canonicalUzbekistanCity(listing.city);
    if (!city) continue;
    listing.city = city;

    const hasCoordinates = Number.isFinite(Number(listing.lat))
      && Number.isFinite(Number(listing.lng));
    if (hasCoordinates) continue;

    const fallback = uzbekistanCoordinateFallback(city);
    if (!fallback) continue;

    listing.lat = fallback.lat;
    listing.lng = fallback.lng;
    listing.locationSource = fallback.source;
    listing.locationAccuracyM = 8000;
  }

  return listings;
}
