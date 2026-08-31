// Curated public housing sources that explicitly advertise direct-owner inventory.
// These are kept separate from realtor/agency sources so the queue can enforce
// owner semantics (no commission, no agency flag) without weakening generic
// source classification.

export const OWNER_HOUSING_SOURCES = Object.freeze({
  UZ: Object.freeze([
    Object.freeze({
      key: 'rentli-tashkent-owner-rent',
      url: 'https://rentli.uz/en/listings',
      city: 'Tashkent',
      dealType: 'longRent',
    }),
    Object.freeze({
      key: 'ostona-tashkent-owner-rent',
      url: 'https://ostona.app/en',
      city: 'Tashkent',
      dealType: 'longRent',
    }),
  ]),
  UA: Object.freeze([
    Object.freeze({
      key: 'easyhouse-ukraine-owner-rent',
      url: 'https://easy-house.in.ua/search/',
      city: null,
      dealType: 'longRent',
    }),
  ]),
  RO: Object.freeze([
    Object.freeze({
      key: 'proprietari-pe-bune-bucharest-owner-rent',
      url: 'https://www.proprietaripebune.ro/chirii/bucuresti',
      city: 'Bucharest',
      dealType: 'longRent',
    }),
    Object.freeze({
      key: 'olx-ro-bucharest-direct-owner-rent',
      url: 'https://www.olx.ro/imobiliare/apartamente-garsoniere-de-inchiriat/bucuresti/q-proprietar-direct/',
      city: 'Bucharest',
      dealType: 'longRent',
      olxOwnerSearch: true,
    }),
  ]),
  KG: Object.freeze([
    Object.freeze({
      key: 'arendator-bishkek-owner-rent',
      url: 'https://arendator.kg/',
      city: 'Bishkek',
      dealType: 'longRent',
    }),
  ]),
});

export function ownerHousingSources(countryCode) {
  return OWNER_HOUSING_SOURCES[String(countryCode || '').toUpperCase()] || [];
}
