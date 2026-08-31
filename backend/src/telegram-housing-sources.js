const EXTRA_TELEGRAM_HOUSING_CHANNELS = {
  UA: [
    // Kyiv: additional active public housing feeds.
    { name: 'OrendakvartyrKyiv_UK', city: 'Kyiv' },
    { name: 'ArendaKyiva', city: 'Kyiv' },
    { name: 'ArendaUA', city: 'Kyiv' },
    { name: 'arendakyiv_ua', city: 'Kyiv' },
    { name: 'rentapartmentkyiv', city: 'Kyiv' },
    // Dedicated daily/hourly apartment feed.
    { name: 'kyiv_kvartira', city: 'Kyiv', dealType: 'shortRent' },

    // Kharkiv.
    { name: 'KH_Rent', city: 'Kharkiv' },
    { name: 'kh_rent_apartment', city: 'Kharkiv' },
    { name: 'xaarenda', city: 'Kharkiv' },
    { name: 'RENTUA_KHARKIV', city: 'Kharkiv' },

    // Ivano-Frankivsk.
    { name: 'ivano_frankivsk_dom', city: 'Ivano-Frankivsk' },
    { name: 'RENTIN_FRANKIVSK', city: 'Ivano-Frankivsk' },

    // Lutsk.
    { name: 'lutskrent', city: 'Lutsk' },
    { name: 'rentin_lutsk', city: 'Lutsk' },

    // Mukachevo.
    { name: 'orendari_mukachevo', city: 'Mukachevo' },

    // Chernivtsi: additional active public housing feeds.
    { name: 'centralne', city: 'Chernivtsi' },
    { name: 'housecv', city: 'Chernivtsi' },
    { name: 'realestatechernivtsiID', city: 'Chernivtsi' },

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
  UZ: [
    // Tashkent: additional active public housing feeds.
    { name: 'kvartira_maklersiz_bezmakler', city: 'Tashkent' },
    { name: 'kvartira_bez_posrednika', city: 'Tashkent' },
    { name: 'nedvij_tashkent', city: 'Tashkent' },
    { name: 'iHometashkent', city: 'Tashkent' },
    // Dedicated daily-rent feeds (Russian and Uzbek wording).
    { name: 'posutochnotashkent', city: 'Tashkent', dealType: 'shortRent' },
    { name: 'kunlik_kvartira_toshkent_arenda', city: 'Tashkent', dealType: 'shortRent' },
  ],
};

function channelKey(value) {
  if (typeof value === 'string') return value.trim().toLowerCase();
  return String(value?.name || '').trim().toLowerCase();
}

export function telegramHousingChannels(countryCode, baseChannels = []) {
  const merged = [];
  const seen = new Set();

  for (const item of [...baseChannels, ...(EXTRA_TELEGRAM_HOUSING_CHANNELS[countryCode] || [])]) {
    const key = channelKey(item);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    merged.push(item);
  }

  return merged;
}

export { EXTRA_TELEGRAM_HOUSING_CHANNELS };
