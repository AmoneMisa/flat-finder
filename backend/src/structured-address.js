import {
  composeHousingAddress,
  parseHousingAddress,
} from '@whiteslove/parsing-lexicon/housing-address';

function text(value) {
  const out = String(value ?? '').trim();
  return out || null;
}

export function applyStructuredAddressFields(listing) {
  if (!listing || typeof listing !== 'object') return listing;

  const knownStreet = text(listing.street);
  const sourceAddress = text(listing.address)
    ? parseHousingAddress(listing.address, { allowBare: true, knownStreet })
    : null;
  const prose = `${listing.title || ''}\n${listing.description || ''}`.trim();
  const parsedText = prose
    ? parseHousingAddress(prose, { knownStreet: knownStreet || sourceAddress?.street || null })
    : null;

  const street = knownStreet || sourceAddress?.street || parsedText?.street || null;
  const houseNumber = text(listing.houseNumber)
    || sourceAddress?.houseNumber
    || parsedText?.houseNumber
    || null;
  const building = text(listing.building)
    || sourceAddress?.building
    || parsedText?.building
    || null;

  const canonicalAddress = composeHousingAddress({ street, houseNumber, building });

  listing.street = street;
  listing.houseNumber = houseNumber;
  listing.building = building;
  listing.address = canonicalAddress
    || sourceAddress?.address
    || text(listing.address)
    || parsedText?.address
    || null;

  return listing;
}

export function applyStructuredAddressFieldsBatch(listings) {
  if (!Array.isArray(listings)) return listings;
  for (const listing of listings) applyStructuredAddressFields(listing);
  return listings;
}
