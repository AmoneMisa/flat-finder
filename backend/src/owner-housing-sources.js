// Curated public housing sources that explicitly advertise direct-owner inventory.
// These are kept separate from realtor/agency sources so the queue can enforce
// owner semantics (no commission, no agency flag) without weakening generic
// source classification. OLX owner search is intentionally not here: OLX uses
// its dedicated curl_cffi sidecar because ordinary server fetches are WAF-blocked.

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
    Object.freeze({
      key: 'turar-tashkent-owner-daily',
      url: 'https://turar.uz/ru/tashkent',
      city: 'Tashkent',
      dealType: 'shortRent',
    }),
  ]),
  UA: Object.freeze([
    Object.freeze({
      key: 'easyhouse-ukraine-owner-rent',
      url: 'https://easy-house.in.ua/search/',
      city: null,
      dealType: 'longRent',
    }),
    Object.freeze({
      key: 'kvarto-ukraine-owner-rent',
      url: 'https://kvarto.app/uk',
      city: null,
      dealType: 'longRent',
    }),
  ]),
  KZ: Object.freeze([
    Object.freeze({
      key: 'kn-almaty-owner-rent',
      url: 'https://www.kn.kz/almaty/arenda-kvartir-bez-posrednikov-s-foto',
      city: 'Almaty',
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
      key: 'proprietar-direct-romania-owner-rent',
      url: 'https://proprietar-direct.ro/categorii-anunturi/oferte-de-inchiriat/',
      city: null,
      dealType: 'longRent',
    }),
  ]),
  KG: Object.freeze([
    Object.freeze({
      key: 'arendator-bishkek-owner-rent',
      url: 'https://arendator.kg/',
      city: 'Bishkek',
      dealType: 'longRent',
    }),
    Object.freeze({
      key: 'sutochno-bishkek-owner-daily',
      url: 'https://sutochno.kg/bishkek/',
      city: 'Bishkek',
      dealType: 'shortRent',
    }),
  ]),
});

export function ownerHousingSources(countryCode) {
  return OWNER_HOUSING_SOURCES[String(countryCode || '').toUpperCase()] || [];
}
