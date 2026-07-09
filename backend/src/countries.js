// Per-country configuration.
//
// Each country aggregates several sources. Every source is optional and fails
// independently; if ALL sources for a country come back empty, the country
// falls back to generated demo data (see scrapers/index.js).
//
// Sources:
//   olx      - OLX internal JSON API (RO/UA/KZ/UZ)
//   reddit   - Reddit public JSON API, searched across the listed subreddits
//   telegram - public Telegram channels via the t.me/s/<channel> web preview
//   threads  - Meta Threads (best-effort; usually needs official API access)
//
// NOTE: OLX real-estate root category ids differ per portal. Subreddits and
// Telegram channels below are starting points — verify/replace them for your
// use case. Kyrgyzstan is intentionally omitted for now.

export const COUNTRIES = {
  RO: {
    code: 'RO',
    name: 'Romania',
    currency: 'RON',
    center: { lat: 44.4268, lng: 26.1025 }, // Bucharest
    sources: ['olx', 'reddit', 'telegram', 'threads'],
    olxHost: 'https://www.olx.ro',
    realEstateRoot: 3,
    terms: { flat: 'apartament', house: 'casa' },
    dealTerms: { sale: 'de vanzare', longRent: 'de inchiriat', shortRent: 'regim hotelier' },
    cities: ['Bucharest', 'Cluj-Napoca', 'Timisoara', 'Iasi', 'Brasov', 'Constanta', 'Oradea'],
    subreddits: ['Romania', 'Bucuresti', 'cluj', 'Timisoara', 'iasi', 'brasov', 'constanta'],
    telegramChannels: [
      'imobiliare_ro', 'chirii_bucuresti', 'apartamente_bucuresti', 'imobiliare_cluj',
      'rent_bucharest', 'arenda_kvartir_bucharest', 'QwertyrRomania', 'arendavbuchareste',
      'apartaments_bucharest', 'chirii_cluj', 'imobiliare_timisoara', 'chirii_iasi',
    ],
    threadsTags: ['imobiliare', 'apartamentdevanzare', 'chirie', 'garsoniera', 'deinchiriat'],
  },
  UA: {
    code: 'UA',
    name: 'Ukraine',
    currency: 'UAH',
    center: { lat: 50.4501, lng: 30.5234 }, // Kyiv
    sources: ['olx', 'reddit', 'telegram', 'threads'],
    olxHost: 'https://www.olx.ua',
    realEstateRoot: 1,
    terms: { flat: 'квартира', house: 'будинок' },
    dealTerms: { sale: 'продаж', longRent: 'оренда', shortRent: 'подобово' },
    cities: ['Kyiv', 'Lviv', 'Odesa', 'Kharkiv', 'Dnipro', 'Vinnytsia', 'Ivano-Frankivsk'],
    subreddits: ['ukraine', 'Kyiv', 'lviv', 'Kharkiv', 'Odessa', 'Dnipro'],
    telegramChannels: [
      'kvartira_kiev', 'arenda_kiev_kvartir', 'nedvizhimost_kiev', 'kvartiry_lvov',
      'davnich', 'davnichprodaga', 'davnichK', 'davnichL', 'kharkov_apartment',
      'arenda_lviv', 'nedvizhimost_odessa', 'arenda_dnepr',
    ],
    threadsTags: ['нерухомість', 'оренда', 'квартира', 'продажквартири', 'орендаквартири'],
  },
  KZ: {
    code: 'KZ',
    name: 'Kazakhstan',
    currency: 'KZT',
    center: { lat: 43.222, lng: 76.8512 }, // Almaty
    sources: ['olx', 'reddit', 'telegram', 'threads'],
    olxHost: 'https://www.olx.kz',
    realEstateRoot: 1,
    terms: { flat: 'квартира', house: 'дом' },
    dealTerms: { sale: 'продажа', longRent: 'аренда', shortRent: 'посуточно' },
    cities: ['Almaty', 'Astana', 'Shymkent', 'Karaganda', 'Aktobe', 'Atyrau', 'Oral'],
    subreddits: ['Kazakhstan', 'almaty', 'Astana'],
    telegramChannels: [
      'nedvizhimost_almaty', 'krisha_almaty', 'arenda_astana', 'kvartiry_shymkent',
      'arenda_almaty_kz', 'nedvizhimost_astana', 'kvartiry_almaty',
    ],
    threadsTags: ['недвижимость', 'квартира', 'аренда', 'продажаквартир', 'арендаквартир'],
  },
  UZ: {
    code: 'UZ',
    name: 'Uzbekistan',
    currency: 'UZS',
    center: { lat: 41.2995, lng: 69.2401 }, // Tashkent
    sources: ['olx', 'reddit', 'telegram', 'threads'],
    olxHost: 'https://www.olx.uz',
    realEstateRoot: 1,
    terms: { flat: 'квартира', house: 'дом' },
    dealTerms: { sale: 'продажа', longRent: 'аренда', shortRent: 'посуточно' },
    cities: ['Tashkent', 'Samarkand', 'Bukhara', 'Namangan', 'Andijan', 'Fergana', 'Nukus'],
    subreddits: ['Uzbekistan', 'Tashkent', 'Samarkand'],
    telegramChannels: [
      'kvartiri_tashkent', 'nedvizhimost_tashkent', 'arenda_tashkenta', 'uybor_uz',
      'arentash', 'kvartira_dom_arenda', 'arendatashkent_uz', 'bez_makler_kvartira_arenda_ijara',
      'TOSHKENT_IJARAGA_UYLAR_SERGELI', 'ijara_tashkent', 'kvartira_samarkand',
    ],
    threadsTags: ['недвижимость', 'ташкент', 'kvartira', 'arenda', 'uysotiladi'],
  },
};

export const COUNTRY_CODES = Object.keys(COUNTRIES);
