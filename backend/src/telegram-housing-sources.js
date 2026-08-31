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

    // Lviv: one owner-only network feed plus a mixed feed with a reliable
    // #власник/direct-owner convention. Wanted posts are rejected downstream.
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

    // Kharkiv.
    { name: 'KH_Rent', city: 'Kharkiv' },
    { name: 'kh_rent_apartment', city: 'Kharkiv' },
    { name: 'xaarenda', city: 'Kharkiv' },
    { name: 'RENTUA_KHARKIV', city: 'Kharkiv' },

    // Ivano-Frankivsk: channel is mixed owners + agencies, but owner listings
    // consistently carry #власник/direct-owner wording.
    {
      name: 'rent_frankivsk',
      city: 'Ivano-Frankivsk',
      ownerOnly: true,
      dealType: 'longRent',
      ownerMarkers: ['#власник', 'від власника', 'власник', 'без комісії'],
    },
    { name: 'ivano_frankivsk_dom', city: 'Ivano-Frankivsk' },
    { name: 'RENTIN_FRANKIVSK', city: 'Ivano-Frankivsk' },

    // Lutsk.
    { name: 'lutskrent', city: 'Lutsk' },
    { name: 'rentin_lutsk', city: 'Lutsk' },

    // Mukachevo.
    { name: 'orendari_mukachevo', city: 'Mukachevo' },

    // Chernivtsi: the direct_rent network feed explicitly publishes rentals
    // from owners without realtor commission.
    { name: 'direct_rent_cv', city: 'Chernivtsi', ownerOnly: true, dealType: 'longRent' },
    { name: 'centralne', city: 'Chernivtsi' },
    { name: 'housecv', city: 'Chernivtsi' },
    { name: 'realestatechernivtsiID', city: 'Chernivtsi' },

    // Rivne direct-owner network feed.
    { name: 'direct_rent_rivne', city: 'Rivne', ownerOnly: true, dealType: 'longRent' },

    // Khmelnytskyi mixed feed: only retain posts with explicit owner/no-commission
    // wording. Deal type remains inferred because the feed carries long + daily.
    {
      name: 'rentin_khmelnytskyi',
      city: 'Khmelnytskyi',
      ownerOnly: true,
      ownerMarkers: [
        'без комісії ріелтора',
        'без комісії',
        'від власника',
        'власник',
        'от собственника',
        'без посредников',
      ],
    },

    // Mykolaiv SMARTIN is mixed; accept only explicitly owner-marked offers.
    {
      name: 'SMARTIN_MYKOLAYIV',
      city: 'Mykolaiv',
      ownerOnly: true,
      ownerMarkers: [
        'від власника',
        'власник',
        'от собственника',
        'собственник',
        'свою квартиру',
        'сдаю свою',
        'без комісії ріелтора',
        'без посредников',
      ],
    },

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
    // Mixed owner/roommate feed: require an explicit owner phrase per post.
    {
      name: 'kvartira_v_almaty',
      city: 'Almaty',
      ownerOnly: true,
      dealType: 'longRent',
      ownerMarkers: [
        'хозяин, не риелтор',
        'не риелтор и не агенство',
        'не риелтор и не агентство',
        'я сама хозяйка',
        'сама хозяйка',
        'без риелтора — хозяйка',
        'без риелтора - хозяйка',
        'собственник',
        'от хозяина',
      ],
    },
  ],
  KG: [
    // Mixed Bishkek housing stream: accept only posts that explicitly identify
    // the owner/direct relationship. Wanted posts are rejected downstream too.
    {
      name: 'bishkekarendakv',
      city: 'Bishkek',
      ownerOnly: true,
      dealType: 'longRent',
      ownerMarkers: [
        'от собственника',
        'собственник',
        'от хозяина',
        'хозяин',
        'без риэлтор',
        'без риелтор',
        'риелторов просьба не беспокоить',
        'үй ээсинин',
      ],
    },
  ],
  UZ: [
    // Mixed Tashkent feed: only accept posts marked as owners (or with a direct-
    // owner phrase) and explicitly reject the realtor section.
    {
      name: 'arentash',
      city: 'Tashkent',
      ownerOnly: true,
      ownerMarkers: ['#хозяева'],
      ownerRejectMarkers: ['#риелтор'],
    },
    // Tashkent: additional active public housing feeds.
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
  // Extras are curated overrides. If a base channel later becomes known to be
  // owner-only, its richer object config must replace the old bare string.
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
