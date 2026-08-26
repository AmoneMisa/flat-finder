const EXTRA_TELEGRAM_HOUSING_CHANNELS = {
  UA: [
    // Odesa: additional active public housing feeds.
    { name: 'odessa_housing', city: 'Odesa' },
    { name: 'okodesa', city: 'Odesa' },
    { name: 'arenda_odessa_oblast', city: 'Odesa' },
    { name: 'arenda_kv_odessa', city: 'Odesa' },
    { name: 'arenda_odesa_kvartiry', city: 'Odesa' },
  ],
  UZ: [
    // Tashkent: additional active public housing feeds.
    { name: 'kvartira_maklersiz_bezmakler', city: 'Tashkent' },
    { name: 'kvartira_bez_posrednika', city: 'Tashkent' },
    { name: 'nedvijemosttashkent', city: 'Tashkent' },
    { name: 'nedvij_tashkent', city: 'Tashkent' },
    { name: 'iHometashkent', city: 'Tashkent' },
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
