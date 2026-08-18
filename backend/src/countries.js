// Per-country configuration.
//
// Each country aggregates several sources. Every source is optional and fails
// independently; if ALL sources for a country come back empty, the country
// falls back to generated demo data (see scrapers/index.js).
//
// Sources:
//   olx      - OLX internal JSON API (RO/UA/KZ/UZ)
//   telegram - public Telegram channels via the separate MTProto worker
//
// NOTE: OLX real-estate root category ids differ per portal. Telegram channels
// below are starting points — verify/replace them for your use case.
// Kyrgyzstan is intentionally omitted for now.

export const COUNTRIES = {
  RO: {
    code: 'RO',
    name: 'Romania',
    currency: 'RON',
    center: { lat: 44.4268, lng: 26.1025 }, // Bucharest
    sources: ['olx', 'telegram'],
    olxHost: 'https://www.olx.ro',
    realEstateRoot: 3,
    terms: { flat: 'apartament', house: 'casa' },
    dealTerms: { sale: 'de vanzare', longRent: 'de inchiriat', shortRent: 'regim hotelier' },
    cities: ['Bucharest', 'Cluj-Napoca', 'Timisoara', 'Iasi', 'Brasov', 'Constanta', 'Oradea'],
    // Localized forms OLX/posts actually use, so the city filter matches. The
    // canonical (English) name is always accepted too; diacritics are ignored.
    cityAliases: {
      Bucharest: ['bucuresti', 'bucurești', 'бухарест'],
      'Cluj-Napoca': ['cluj', 'cluj-napoca'],
      Timisoara: ['timisoara', 'timișoara'],
      Iasi: ['iasi', 'iași'],
      Brasov: ['brasov', 'brașov'],
      Constanta: ['constanta', 'constanța'],
      Oradea: ['oradea'],
    },
    telegramChannels: [
      'rent_bucharest', 'arenda_kvartir_bucharest', 'QwertyrRomania', 'arendavbuchareste',
      'apartaments_bucharest', 'rent_ro', 'armonie_agentie_imobiliare_ro',
    ],
  },
  UA: {
    code: 'UA',
    name: 'Ukraine',
    currency: 'UAH',
    center: { lat: 50.4501, lng: 30.5234 }, // Kyiv
    sources: ['olx', 'telegram'],
    olxHost: 'https://www.olx.ua',
    realEstateRoot: 1,
    terms: { flat: 'квартира', house: 'будинок' },
    dealTerms: { sale: 'продаж', longRent: 'оренда', shortRent: 'подобово' },
    cities: ['Kyiv', 'Lviv', 'Odesa', 'Kharkiv', 'Dnipro', 'Vinnytsia', 'Ivano-Frankivsk', 'Mukachevo'],
    cityAliases: {
      Kyiv: ['київ', 'киев', 'kyiv', 'kiev'],
      Lviv: ['львів', 'львов', 'lviv'],
      Odesa: ['одеса', 'одесса', 'odesa', 'odessa'],
      Kharkiv: ['харків', 'харьков', 'kharkiv'],
      Dnipro: ['дніпро', 'днепр', 'dnipro'],
      Vinnytsia: ['вінниця', 'винница', 'vinnytsia'],
      'Ivano-Frankivsk': ['івано-франківськ', 'ивано-франковск', 'ivano-frankivsk'],
      Mukachevo: ['мукачево', 'мукачеве', 'mukachevo', 'mukacheve', 'munkacs']
    },
    telegramChannels: [
      // Kyiv
      { name: 'orenda_kyiv_city', city: 'Kyiv' },
      { name: 'orendaky', city: 'Kyiv' },
      { name: 'arenda_kvartiry_kiev', city: 'Kyiv' },
      { name: 'x_arenda_kyiv', city: 'Kyiv' },
      { name: 'orendakvartyr_kyiv', city: 'Kyiv' },
// Davnich network
      { name: 'davnichK', city: 'Kyiv' },
      { name: 'davnich', city: 'Kharkiv' },

// Продажа квартир, разные города
      { name: 'davnichprodaga', city: null, dealType: 'sale' },
      // Kharkiv
      { name: 'x_arenda_kharkov', city: 'Kharkiv' },
      { name: 'kharkov_apartment', city: 'Kharkiv' },

      // Odesa
      { name: 'x_orenda_odesa', city: 'Odesa' },
      { name: 'arenda_odessaa', city: 'Odesa' },
      { name: 'rentsodessa', city: 'Odesa' },
      { name: 'nedvizhimost_odessa', city: 'Odesa' },

      // Dnipro
      { name: 'x_orenda_dnipro', city: 'Dnipro' },
      { name: 'arenda_dnepr', city: 'Dnipro' },

      // Lviv
      { name: 'orendakvarturlviv', city: 'Lviv' },
      { name: 'orenda_Lviw', city: 'Lviv' },
      { name: 'rentalviv', city: 'Lviv' },
      { name: 'smartin_lviv', city: 'Lviv' },
      { name: 'davnichL', city: 'Lviv' },

      // Vinnytsia
      { name: 'vinnytsia_rent', city: 'Vinnytsia' },
      { name: 'vinnitsia_dom', city: 'Vinnytsia' },
      { name: 'okvinnytsya', city: 'Vinnytsia' },
      { name: 'rentin_vinnitsa', city: 'Vinnytsia' },

      // Ivano-Frankivsk
      { name: 'rent_frankivsk', city: 'Ivano-Frankivsk' },

      // Chernivtsi
      { name: 'direct_rent_cv', city: 'Chernivtsi' },
      { name: 'rentCV', city: 'Chernivtsi' },
      { name: 'RENTIN_CHERNIVTSI', city: 'Chernivtsi' },
      { name: 'neruhomistrus', city: 'Chernivtsi' },

      // Zaporizhzhia
      { name: 'dreamservice_zp', city: 'Zaporizhzhia' },
      { name: 'RENTUA_ZAPORIZHZHIA', city: 'Zaporizhzhia' },

      // Poltava
      { name: 'okpoltava', city: 'Poltava' },
      { name: 'RENTIN_POLTAVA', city: 'Poltava' },

      // Cherkasy
      { name: 'arenda_che', city: 'Cherkasy' },
      { name: 'kvartiri_cherkasy', city: 'Cherkasy' },

      // Ternopil
      { name: 'orenda_ternopill', city: 'Ternopil' },
      { name: 'orenda_ternopil_ua', city: 'Ternopil' },

      // Lutsk
      { name: 'LUTSK_ORENDA', city: 'Lutsk' },

      // Khmelnytskyi
      { name: 'orenda_khmelnytsk', city: 'Khmelnytskyi' },
      { name: 'orendakm', city: 'Khmelnytskyi' },

      // Uzhhorod
      { name: 'smartin_uzhhorod', city: 'Uzhhorod' },
      { name: 'rentin_uzhhorod', city: 'Uzhhorod' },

      // Kropyvnytskyi
      { name: 'RENTIN_KROPYVNYTSKYI', city: 'Kropyvnytskyi' },

      // Mykolaiv
      { name: 'SMARTIN_MYKOLAYIV', city: 'Mykolaiv' },

      // Sumy
      { name: 'sumy_rent', city: 'Sumy' },
      { name: 'premiersumy', city: 'Sumy' },

      // Chernihiv
      { name: 'smartin_chernihiv', city: 'Chernihiv' },

      // Rivne
      { name: 'direct_rent_rivne', city: 'Rivne' },

      // Zhytomyr
      { name: 'RENTIN_ZHYTOMYR', city: 'Zhytomyr' },
    ],
  },
  KZ: {
    code: 'KZ',
    name: 'Kazakhstan',
    currency: 'KZT',
    center: { lat: 43.222, lng: 76.8512 }, // Almaty
    sources: ['olx', 'telegram'],
    olxHost: 'https://www.olx.kz',
    realEstateRoot: 1,
    terms: { flat: 'квартира', house: 'дом' },
    dealTerms: { sale: 'продажа', longRent: 'аренда', shortRent: 'посуточно' },
    cities: ['Almaty', 'Astana', 'Shymkent', 'Karaganda', 'Aktobe', 'Atyrau', 'Oral'],
    cityAliases: {
      Almaty: ['алматы', 'алмата', 'almaty'],
      Astana: ['астана', 'нур-султан', 'astana', 'nur-sultan'],
      Shymkent: ['шымкент', 'shymkent'],
      Karaganda: ['караганда', 'қарағанды', 'karaganda'],
      Aktobe: ['актобе', 'ақтөбе', 'aktobe'],
      Atyrau: ['атырау', 'atyrau'],
      Oral: ['уральск', 'орал', 'oral'],
    },
    // NOTE: KZ is thin after pruning dead channels — needs fresh replacements.
    telegramChannels: [
      'kvartiry2', 'arendakvartirastana2022', 'arendam0',
    ],
  },
  UZ: {
    code: 'UZ',
    name: 'Uzbekistan',
    currency: 'UZS',
    center: { lat: 41.2995, lng: 69.2401 }, // Tashkent
    sources: ['olx', 'telegram'],
    olxHost: 'https://www.olx.uz',
    realEstateRoot: 1,
    terms: { flat: 'квартира', house: 'дом' },
    dealTerms: { sale: 'продажа', longRent: 'аренда', shortRent: 'посуточно' },
    cities: ['Tashkent', 'Samarkand', 'Bukhara', 'Namangan', 'Andijan', 'Fergana', 'Nukus'],
    cityAliases: {
      Tashkent: ['ташкент', 'toshkent', 'tashkent'],
      Samarkand: ['самарканд', 'samarqand', 'samarkand'],
      Bukhara: ['бухара', 'buxoro', 'bukhara'],
      Namangan: ['наманган', 'namangan'],
      Andijan: ['андижан', 'andijon', 'andijan'],
      Fergana: ['фергана', "farg'ona", 'fargona', 'fergana'],
      Nukus: ['нукус', 'nukus'],
    },
    telegramChannels: [
      'nedvizhimost_tashkent', 'arentash', 'kvartira_dom_arenda', 'arendatashkent_uz',
      'bez_makler_kvartira_arenda_ijara', 'TOSHKENT_IJARAGA_UYLAR_SERGELI',
      'kv_arenda_tashken_t', 'ArendaTashkentaa', 'arenduzb',
      'samkvartira', 'arenda_samarkand',
    ],
  },
};

function normalizeCityName(value) {
  return String(value ?? '')
      .trim()
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '');
}

export function canonicalCityName(
    countryCode,
    value,
) {
  const raw =
      String(value ?? '')
          .trim();

  if (!raw) {
    return '';
  }

  const country =
      COUNTRIES[countryCode];

  if (!country) {
    return raw;
  }

  const normalized =
      normalizeCityName(raw);

  for (
      const city
      of country.cities ?? []
      ) {
    const forms = [
      city,
      ...(country.cityAliases?.[city] ?? []),
    ];

    if (
        forms.some(
            (form) =>
                normalizeCityName(form) ===
                normalized,
        )
    ) {
      return city;
    }
  }

  /*
   * Неизвестный нам город сохраняем
   * как его вернул источник.
   *
   * Таким образом новые города OLX
   * автоматически появляются в UI.
   */
  return raw;
}

export const COUNTRY_CODES = Object.keys(COUNTRIES);
