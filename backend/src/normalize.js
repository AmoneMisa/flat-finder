// Compatibility facade around the historical normalizer. Shared free-text
// housing semantics are resolved by @whiteslove/parsing-lexicon first.
import { parseHousingFeatures } from '@whiteslove/parsing-lexicon';
import { parseHousingPrice } from '@whiteslove/parsing-lexicon/housing-money';
import { makeListing as makeLegacyListing } from './normalize-legacy.js';

export * from './normalize-legacy.js';

export function makeListing(partial) {
  const listing = makeLegacyListing(partial);
  const text = `${partial?.title ?? ''}\n${partial?.description ?? ''}`;
  const features = parseHousingFeatures(text);
  const parsedPrice = parseHousingPrice(text, partial?.currency || listing.currency || '');

  const amenities = [...new Set([
    ...(Array.isArray(listing.amenities) ? listing.amenities : []),
    ...(features.courtyard ? ['courtyard'] : []),
    ...(features.gazebo ? ['gazebo'] : []),
  ])];

  return {
    ...listing,
    price: partial?.price != null ? listing.price : (parsedPrice.price ?? listing.price),
    currency: partial?.price != null && partial?.currency
      ? listing.currency
      : (parsedPrice.currency || listing.currency),
    petsAllowed: partial?.petsAllowed ?? features.petsAllowed ?? listing.petsAllowed,
    internet: partial?.internet ?? features.internet ?? listing.internet,
    amenities,
  };
}
