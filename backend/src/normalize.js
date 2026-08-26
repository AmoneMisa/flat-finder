// Compatibility facade around the historical normalizer. Shared free-text
// housing semantics are resolved by @whiteslove/parsing-lexicon first.
import { parseHousingListingFields } from '@whiteslove/parsing-lexicon';
import { parseHousingPrice } from '@whiteslove/parsing-lexicon/housing-money';
import { makeListing as makeLegacyListing } from './normalize-legacy.js';

export * from './normalize-legacy.js';

export function makeListing(partial) {
  const listing = makeLegacyListing(partial);
  const text = `${partial?.title ?? ''}\n${partial?.description ?? ''}`;
  const fields = parseHousingListingFields(text);
  const parsedPrice = parseHousingPrice(text, partial?.currency || listing.currency || '');

  const amenities = [...new Set([
    ...(Array.isArray(listing.amenities) ? listing.amenities : []),
    ...(fields.courtyard ? ['courtyard'] : []),
    ...(fields.gazebo ? ['gazebo'] : []),
  ])];

  const choose = (key) => partial?.[key] ?? fields[key] ?? listing[key];

  return {
    ...listing,
    price: partial?.price != null ? listing.price : (parsedPrice.price ?? listing.price),
    currency: partial?.price != null && partial?.currency
      ? listing.currency
      : (parsedPrice.currency || listing.currency),
    bedrooms: choose('bedrooms'),
    bathrooms: choose('bathrooms'),
    buildingYear: choose('buildingYear'),
    balcony: choose('balcony'),
    terrace: choose('terrace'),
    privateYard: choose('privateYard'),
    dishwasher: choose('dishwasher'),
    airConditioner: choose('airConditioner'),
    gas: choose('gas'),
    newBuilding: choose('newBuilding'),
    communalSeparated: choose('communalSeparated'),
    parking: choose('parking'),
    elevator: choose('elevator'),
    heating: choose('heating'),
    hotWater: choose('hotWater'),
    internet: choose('internet'),
    petsAllowed: choose('petsAllowed'),
    childrenAllowed: choose('childrenAllowed'),
    smokingAllowed: choose('smokingAllowed'),
    negotiable: choose('negotiable'),
    furnished: choose('furnished'),
    firstRent: partial?.firstRent ?? fields.firstRent ?? listing.firstRent ?? null,
    minRentTerm: partial?.minRentTerm ?? fields.minRentTerm ?? listing.minRentTerm ?? null,
    availableFrom: partial?.availableFrom ?? fields.availableFrom ?? listing.availableFrom ?? null,
    utilitiesAmount: partial?.utilitiesAmount ?? fields.utilitiesAmount ?? listing.utilitiesAmount ?? null,
    amenities,
  };
}
