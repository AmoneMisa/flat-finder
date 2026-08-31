const EXTRA_TELEGRAM_HOUSING_CHANNELS = {
  UA: [
    // Kyiv: additional active public housing feeds.
    // These two communities explicitly describe themselves as direct/no-realtor.
    { name: 'orenda_kyiv_city', city: 'Kyiv', ownerOnly: true, dealType: 'longRent' },
    { name: 'OrendakvartyrKyiv_UK', city: 'Kyiv' },
    { name: 'ArendaKyiva', city: 'Kyiv' },
    { name: 'ArendaUA', city: 'Kyiv' },
    { name: 'arendakyiv_ua', city: 'Kyiv', ownerOnly: true, dealType: 'longRent' },
    { name: 'rentapartmentkyiv', city: 'Kyiv' },
    // Direct-owner feeds: no agencies/commission by channel policy.
    { name: 'kievrentfree', city: 'Kyiv', ownerOnly: true },
    { name: 'orenda_bez_rieltora', city: 'Kyiv', ownerOnly: true },
    // Dedicated daily/hourly apartment feed.
    { name: 'kyiv_kvartira', city: 'Kyiv', dealType: 'shortRent' },

    // Lviv direct-owner feeds. General Lviv channels stay available separately.
    { name: 'direct_rent', city: 'Lviv', ownerOnly: true, dealType: 'longRent' },
    {
      name: 'lviv_no_maklers',
      city: 'Lviv',
      ownerOnly: true,
      dealType: 'longRent',
      ownerMarkers: [
        '#власник',
        'від власника',
        'від власниці',
        'пряма оренда від власниці',
        'без комісії',
      ],
    },

    // Kharkiv. Keep the general stream: owner and realtor listings can coexist.
    { name: 'KH_Rent', city: 'Kharkiv' },
    { name: 'kh_rent_apartment', city: 'Kharkiv' },
    { name: 'xaarenda', city: 'Kharkiv' },
    { name: 'RENTUA_KHARKIV', city: 'Kharkiv' },

    // Dnipro: dedicated no-realtor feed in addition to the existing mixed feeds.
    { name: 'BEZ_rieltoriv_DP', city: 'Dnipro', ownerOnly: true },

    // Ivano-Frankivsk mixed feeds remain mixed by design.
    { name: 'ivano_frankivsk_dom', city: 'Ivano-Frankivsk' },
    { name: 'RENTIN_FRANKIVSK', city: 'Ivano-Frankivsk' },

    // Lutsk: keep general feeds, and additionally mark the channel whose own
    // policy says listings are from owners. Wanted posts are rejected downstream.
    { name: 'lutskrent', city: 'Lutsk' },
    { name: 'rentin_lutsk', city: 'Lutsk' },
    { name: 'LUTSK_ORENDA', city: 'Lutsk', ownerOnly: true },

    // Ternopil: add a separate direct-owner network feed while preserving the
    // existing general Ternopil channels from the country registry.
    { name: 'Ternopol_arenda', city: 'Ternopil', ownerOnly: true, dealType: 'longRent' },

    // Mukachevo.
    { name: 'orendari_mukachevo', city: 'Mukachevo' },

    // Chernivtsi: direct-owner network feed, alongside general city feeds.
    { name: 'direct_rent_cv', city: 'Chernivtsi', ownerOnly: true, dealType: 'longRent' },
    { name: 'centralne', city: 'Chernivtsi' },
    { name: 'housecv', city: 'Chernivtsi' },
    { name: 'realestatechernivtsiID', city: 'Chernivtsi' },

    // Rivne direct-owner network feed, alongside the general city coverage.
    { name: 'direct_rent_rivne', city: 'Rivne', ownerOnly: true, dealType: 'longRent' },

    // Khmelnytskyi: this source contains both owner and realtor inventory, so
    // keep the full stream and let normal classification set byAgency/commission.
    { name: 'rentin_khmelnytskyi', city: 'Khmelnytskyi' },

    // Odesa: additional active public housing feeds.
    { name: 'odessa_housing', city: 'Odesa' },
    { name: 'okodesa', city: 'Odesa' },
    { name: 'arenda_odessa_oblast', city: 'Odesa' },
    { name: 'arenda_kv_odessa', city: 'Odesa' },
    { name: 'arenda_odesa_kvartiry', city: 'Odesa' },
    // Dedicated daily-rent feeds verified as public Telegram channels.
    { name: 'posutochnaya_arenda_odessa', city: 'Odesa', dealType: 'shortRent' },
    { name: 'OdessaDailyRentUar', city: 'Odesa', dealType: 'shortRent' },
  ],
  KZ: [
    // These channels explicitly advertise direct/verified owners and no agents.
    { name: 'kvartiry2', city: 'Almaty', ownerOnly: true },
    { name: 'kvartiralmaty1', city: 'Almaty', ownerOnly: true },
    { name: 'freehomekz_Almaty', city: 'Almaty', ownerOnly: true, dealType: 'shortRent' },

    // Mixed Almaty feed: preserve owners, agencies and roommate listings.
    { name: 'kvartira_v_almaty', city: 'Almaty', dealType: 'longRent' },

    // Astana: one owner-only channel plus one large mixed channel. Both are kept
    // so users can see direct-owner and realtor/roommate inventory.
    { name: 'arenda_kvartiry_astana', city: 'Astana', ownerOnly: true, dealType: 'longRent' },
    { name: 'rentinastana', city: 'Astana' },
  ],
  KG: [
    // Bishkek stream is mixed; keep both owner and realtor inventory and rely on
    // the existing wanted/agency classifiers instead of suppressing either side.
    { name: 'bishkekarendakv', city: 'Bishkek', dealType: 'longRent' },
  ],
  UZ: [
    // Mixed Tashkent feed: keep both #хозяева and #риелтор sections.
    // Direct-owner-only channels below remain separately available.
    { name: 'kvartira_maklersiz_bezmakler', city: 'Tashkent', ownerOnly: true },
    { name: 'kvartira_bez_posrednika', city: 'Tashkent', ownerOnly: true },
    { name: 'ijaraga_kvartiralar_Bezmakler', city: 'Tashkent', ownerOnly: true, dealType: 'longRent' },
    {
      name: 'bezmakler_ijara',
      city: 'Tashkent',
      ownerOnly: true,
      dealType: 'longRent',
      ownerMarkers: [
        'egasi',
        'bezmakler',
        'без маклера',
        'без посредников',
        'собственник',
        'от собственника',
      ],
    },
    {
      name: 'Maklersiz',
      city: 'Tashkent',
      ownerOnly: true,
      dealType: 'longRent',
      ownerMarkers: ['без маклер', 'makler yo‘q', "makler yo'q", '#maklersiz'],
    },
    {
      name: 'bez_makler',
      city: 'Tashkent',
      ownerOnly: true,
      dealType: 'longRent',
      ownerMarkers: ['без маклер', 'bezmakler', 'maklersiz', "makler yo'q"],
    },
    { name: 'nedvij_tashkent', city: 'Tashkent' },
    { name: 'iHometashkent', city: 'Tashkent' },
    // Dedicated daily-rent feeds (Russian and Uzbek wording).
    { name: 'posutochnotashkent', city: 'Tashkent', dealType: 'shortRent' },
    { name: 'kunlik_kvartira_toshkent_arenda', city: 'Tashkent', dealType: 'shortRent' },
    {
      name: 'kunlik_kvartira_1',
      city: 'Tashkent',
      ownerOnly: true,
      dealType: 'shortRent',
      ownerMarkers: ['egasi', 'bezmakler', 'без маклера', 'без посредников'],
    },
  ],
};

function channelKey(value) {
  if (typeof value === 'string') return value.trim().toLowerCase();
  return String(value?.name || '').trim().toLowerCase();
}

export function telegramHousingChannels(countryCode, baseChannels = []) {
  // Extras are curated overrides. Rich configs replace older bare channel
  // configs only when we intentionally know more about that exact feed.
  const merged = new Map();
  for (const item of baseChannels) {
    const key = channelKey(item);
    if (key) merged.set(key, item);
  }
  for (const item of EXTRA_TELEGRAM_HOUSING_CHANNELS[countryCode] || []) {
    const key = channelKey(item);
    if (key) merged.set(key, item);
  }
  return [...merged.values()];
}

export { EXTRA_TELEGRAM_HOUSING_CHANNELS };
