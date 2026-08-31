export const REALTOR_HOUSING_SOURCES = {
  UZ: [
    {
      key: 'hata-tashkent-rent',
      url: 'https://www.hata.uz/listings/rent/tashkent',
      city: 'Tashkent',
    },
    {
      key: 'realting-tashkent-rent',
      url: 'https://realting.uz/tashkent/property-to-rent/apartments',
      city: 'Tashkent',
    },
    {
      key: 'rentli-tashkent-rent',
      url: 'https://rentli.uz/ru',
      city: 'Tashkent',
    },
    {
      key: 'domza-tashkent-rent',
      url: 'https://domza.uz/offers',
      city: 'Tashkent',
    },
  ],
  UA: [
    {
      key: 'x-estate-ukraine-rent',
      url: 'https://www.x-estate.com/orenduvaty-kvartyru',
      city: null,
    },
    {
      key: 'park-lane-kyiv-rent',
      url: 'https://parklane.ua/uk/realty_search/apartment/rent',
      city: 'Kyiv',
    },
    {
      key: 'blagovist-kyiv-rent',
      url: 'https://blagovist.ua/search/apartment/rent',
      city: 'Kyiv',
    },
    {
      key: 'atlanta-odesa-rent',
      url: 'https://www.atlanta.ua/uk/odessa/filters/arenda/kvartiry',
      city: 'Odesa',
    },
  ],
};

export function realtorHousingSources(countryCode) {
  return REALTOR_HOUSING_SOURCES[String(countryCode || '').toUpperCase()] || [];
}
