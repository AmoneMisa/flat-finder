// Practical Tashkent address dictionary for apartment listings.
//
// Administrative districts and colloquial address areas are deliberately
// separate. A housing massif, numbered quarter or legacy C-code can belong to
// a district with a different name (Chilanzar and Sergeli are the common traps).
// Keep canonical values stable and list Russian/Uzbek/English spellings as
// aliases. Numbered families are resolved below because their district depends
// on the number/suffix.

const area = (name, aliases) => ({ name, aliases });

export const TASHKENT_AREAS = Object.freeze({
  Almazar: [
    area('Sebzar', ['себзар', 'sebzar', 'ц 17', 'ц 18', 'c 17', 'c 18']),
    area('Karakamysh-1/2', ['каракамыш 1 2', 'qoraqamish 1 2', 'karakamish 1 2']),
    area('Karakamysh-2/3', ['каракамыш 2 3', 'qoraqamish 2 3', 'karakamish 2 3']),
    area('Karakamysh-2/4', ['каракамыш 2 4', 'qoraqamish 2 4', 'karakamish 2 4']),
    area('Karakamysh-2/5', ['каракамыш 2 5', 'qoraqamish 2 5', 'karakamish 2 5']),
    area('Olympia', ['олимпия', 'olimpiya', 'olympia']),
    area('Vuzgorodok', ['вузгородок', 'вуз городок', 'vuzgorodok']),
    area('Medgorodok', ['медгородок', 'мед городок', 'medgorodok']),
    area('Shifokorlar-1', ['шифокорлар 1', 'shifokorlar 1']),
    area('Shifokorlar-2', ['шифокорлар 2', 'shifokorlar 2']),
    area('Beruni-3', ['беруни 3', 'beruniy 3', 'beruni 3']),
    area('Takhtapul', ['тахтапуль', 'тахтапул', 'taxtapul', 'takhtapul']),
    area('Hislat', ['хислат', 'hislat', 'xislat']),
    ...[1, 2, 3, 4].map((n) => area(`Beshkurgan-${n}`, [`бешкурган ${n}`, `beshqo rg on ${n}`, `beshkurgan ${n}`])),
    area('Chimbay', ['чимбай', 'chimboy', 'chimbay']),
  ],
  Bektemir: [
    area('Suvsoz-1', ['сувсоз 1', 'водник 1', 'suvsoz 1']),
    area('Suvsoz-2', ['сувсоз 2', 'водник 2', 'suvsoz 2']),
    area('Binokor', ['бинокор', 'binokor']),
    area('Binokor-2', ['бинокор 2', 'binokor 2']),
    area('Majnuntol', ['мажнунтол', 'majnuntol']),
    area('Olima Oshirova', ['олима оширова', 'olima oshirova']),
    area('Bektemir', ['бектемир массив', 'bektemir massivi']),
  ],
  Mirobod: [
    area('Hospitalny', ['госпитальный', 'госпиталка', 'hospitalny']),
    area('Lolazor', ['лолазор', 'lolazor']),
    area('Farovon', ['фаровон', 'farovon']),
    area('Oltinkul', ['алтынкуль', 'олтинкул', 'олтинкўл', 'oltinkol', 'oltinkul']),
    area('Movarounnahr', ['мавераннахр', 'мовароуннахр', 'movarounnahr']),
    area('Abdurauf Fitrat', ['абдурауф фитрат', 'abdurauf fitrat']),
  ],
  'Mirzo Ulugbek': [
    area('Buyuk Ipak Yuli', ['буюк ипак йули', 'buyuk ipak yuli', 'ц 1', 'c 1']),
    area('Alay', ['олой', 'алайский', 'алайск', 'alay', 'ц 2', 'c 2']),
    ...[1, 2, 3, 4, 6].map((n) => area(`Karasu-${n}`, [`карасу ${n}`, `qorasuv ${n}`, `karasu ${n}`])),
    ...[1, 2, 3, 4].map((n) => area(`TTZ-${n}`, [`ттз ${n}`, `ttz ${n}`])),
    area('Yalangach', ['ялангач', 'yalangach', 'yalang och']),
    area('Feruza', ['феруза', 'feruza']),
    area('Feruza-1', ['феруза 1', 'feruza 1']),
    area('Buz-1', ['буз 1', 'бўз 1', 'boz 1', 'bo z 1']),
    area('Turon', ['турон', 'turon']),
    area('Riyoziy', ['риёзий', 'riyoziy']),
    area('Geofizika', ['геофизика', 'поселок геофизиков', 'пос геофизиков', 'geofizika']),
  ],
  Sergeli: [
    area('Sergeli-2 G-40', ['сергели 2 г 40', 'sergeli 2 g 40']),
    area('Sergeli Car Bazaar', ['сергели машинный базар', 'сергели машина бозор', 'sergeli moshina bozor', 'sergile moshena bozor', 'sergele moshina bozor']),
    area('Yangi Sergeli', ['янги сергели', 'yangi sergeli']),
    area('Stroygorod', ['стройгород', 'stroygorod']),
    area('Babur Quarter', ['квартал бабур', 'бабур квартал', 'babur kvartal']),
  ],
  Uchtepa: [
    area('Al-Khorezmi-2', ['аль хорезми 2', 'ал хорезми 2', 'al xorazmiy 2', 'al khorezmi 2']),
    area('Shark', ['массив шарк', 'шарк массив', 'sharq massivi']),
  ],
  Chilanzar: [
    area('Nakkoshlik', ['наккошлык', 'наққошлик', 'naqqoshlik']),
    area('Al-Khorezmi-1', ['аль хорезми 1', 'ал хорезми 1', 'al xorazmiy 1', 'al khorezmi 1']),
    area('Almazar Massif', ['массив алмазар', 'массив олмазор', 'almazar massivi', 'olmazor massivi']),
  ],
  Shaykhantahur: [
    area('Labzak', ['лабзак', 'labzak', 'ц 13', 'c 13']),
    area('Khadra', ['хадра', 'xadra', 'khadra', 'ц 14', 'c 14']),
    area('Jangoh', ['джангох', 'жангох', 'jangoh', 'ц 15', 'c 15']),
    area('Gulabad', ['гульабад', 'гулабад', 'gulobod', 'gulabad', 'ц 26', 'c 26']),
    area('Karatash', ['караташ', 'qoratosh', 'karatash']),
    area('Chorsu', ['чорсу', 'chorsu']),
    area('Beshagach', ['бешагач', 'beshyog och', 'beshagach']),
    area('Aktepa', ['актепа шайхантахур', 'oqtepa shayxontohur']),
    area('Ibn Sino-1', ['ибн сино 1', 'ibn sino 1']),
    area('Ibn Sino-2', ['ибн сино 2', 'ibn sino 2']),
    area('Beltepa', ['белтепа', 'beltepa']),
    area('Jarariq', ['джарарык', 'жарарик', 'jarariq', 'jararik']),
  ],
  Yunusabad: [
    area('Kashgar', ['кашгар', 'qashqar', 'kashgar', 'ц 4', 'c 4']),
    area('Kiyot', ['киёт', 'қиёт', 'qiyot', 'kiyot', 'ц 5', 'c 5']),
    area('Minor', ['минор', 'minor', 'ц 6', 'c 6']),
    area('TashGRES', ['ташгрэс', 'tashgres']),
    area('Dehqonobod', ['дехконобод', 'деҳқонобод', 'dehqonobod']),
    area('Katta Hasanboy', ['катта хасанбой', 'katta hasanboy']),
  ],
  Yakkasaray: [
    area('Bashlyk', ['башлык', 'boshliq', 'bashlyk']),
    area('Kushbegi', ['кушбеги', 'қушбеги', 'qushbegi', 'kushbegi']),
    area('Bobur', ['массив бобур', 'bobur massivi']),
    area('Rakat', ['ракат', 'rakat']),
    area('Rakatboshi', ['ракатбоши', 'rakatboshi']),
    area('Konstitutsiya', ['конституция массив', 'konstitutsiya massivi']),
    area('Hamid Sulaymonov', ['хамид сулаймонов', 'hamid sulaymonov']),
    area('Glinka', ['глинка', 'glinka']),
  ],
  Yangihayot: [
    area('Uzgarish', ['узгарыш', 'ўзгариш', 'o zgarish', 'uzgarish']),
    area('Dustlik-1', ['дустлик 1', 'дўстлик 1', 'do stlik 1', 'dustlik 1']),
    area('Dustlik-2', ['дустлик 2', 'дўстлик 2', 'do stlik 2', 'dustlik 2']),
    area('Yangi Choshtepa', ['янги чоштепа', 'yangi choshtepa', 'yangi cho shtepa']),
    area('Sputnik', ['спутник', 'йулдош', 'йўлдош', 'yo ldosh', 'yoldosh']),
  ],
  Yashnobod: [
    area('Kuylyuk Center', ['куйлюк центр', 'куйлик центр', 'qo yliq markaz', 'kuylyuk center']),
    ...[1, 2, 3, 4].map((n) => area(`Aviasozlar-${n}`, [`авиасозлар ${n}`, `городок авиастроителей ${n}`, `aviasozlar ${n}`])),
    ...[1, 2, 3, 4].map((n) => area(`Tuzel-${n}`, [`тузель ${n}`, `tuzel ${n}`])),
    area('Asalabad-1', ['асалабад 1', 'asalobod 1', 'asalabad 1']),
    area('Asalabad-2', ['асалабад 2', 'asalobod 2', 'asalabad 2']),
    area('Tashselmash', ['ташсельмаш', 'tashselmash']),
    area('Alimkent', ['алимкент', 'olimkent', 'alimkent']),
    area('Shohimardon', ['шохимардон', 'shohimardon']),
    area('Mumtoz', ['мумтаз', 'mumtoz']),
  ],
});

const normalize = (value) => String(value || '')
  .normalize('NFKC')
  .toLocaleLowerCase()
  .replace(/ё/g, 'е')
  .replace(/[‘’ʻʼ'`]/g, ' ')
  .replace(/[^\p{L}\p{N}]+/gu, ' ')
  .replace(/\s+/g, ' ')
  .trim();

const phraseIn = (normalizedText, alias) =>
  ` ${normalizedText} `.includes(` ${normalize(alias)} `);

const STATIC_MATCHERS = Object.entries(TASHKENT_AREAS)
  .flatMap(([district, entries]) => entries.flatMap((entry) =>
    entry.aliases.map((alias) => ({ district, area: entry.name, alias }))))
  .sort((a, b) => normalize(b.alias).length - normalize(a.alias).length);

const result = (areaName, district, confidence = 1, ambiguous = false) => ({
  area: areaName,
  district,
  confidence,
  ambiguous,
  requireExactAddress: ambiguous,
});

function numberedMatch(text, names) {
  const alternatives = names.map(normalize).join('|').replace(/ /g, '\\s+');
  return text.match(new RegExp(
    `(?:^|\\s)(?:${alternatives})(?:\\s+(?:tumani|тумани|district|район|massiv|массив))?\\s+(\\d{1,2})(?:\\s*([adад]))?(?:\\s+(?:chi|чи|й|квартал|kvartal|hudud|худуд))*(?:\\s|$)`,
    'iu',
  ));
}

const latinSuffix = (value) => ({ А: 'A', Д: 'D' }[String(value || '').toUpperCase()] || String(value || '').toUpperCase());

export function resolveTashkentArea(value) {
  const text = normalize(value);
  if (!text) return null;

  let match = numberedMatch(text, ['чиланзар', 'чилонзор', 'chilanzar', 'chilonzor']);
  if (!match) {
    const reverse = text.match(/(?:^|\s)(\d{1,2})\s+(?:квартал|кв л)\s+(?:чиланзара|чилонзора|chilanzar|chilonzor)(?:\s|$)/iu);
    if (reverse) match = [reverse[0], reverse[1], ''];
  }
  if (match) {
    const number = Number(match[1]);
    const suffix = latinSuffix(match[2]);
    const district = ((number >= 11 && number <= 15) || (number >= 21 && number <= 25))
      ? 'Uchtepa'
      : ((number >= 1 && number <= 10) || (number >= 16 && number <= 20))
        ? 'Chilanzar'
        : null;
    return result(`Chilanzar-${number}${suffix}`, district, district ? 1 : 0.5, !district);
  }

  match = numberedMatch(text, ['куйлюк', 'куйлик', 'kuylyuk', 'kuyliq', 'qoyliq', 'qo yliq']);
  if (match) {
    const number = Number(match[1]);
    const district = number >= 1 && number <= 4 ? 'Mirobod' : number >= 5 && number <= 7 ? 'Sergeli' : null;
    return result(`Kuylyuk-${number}`, district, district ? 1 : 0.5, !district);
  }

  match = numberedMatch(text, ['сергели', 'sergeli', 'sergile', 'sergele']);
  if (match) {
    const number = Number(match[1]);
    const suffix = latinSuffix(match[2]);
    const legacyYangihayot = number === 1 || (suffix === 'A' && [3, 5, 7].includes(number));
    const knownSergeli = [2, 4, 5, 6, 7, 8].includes(number);
    const district = legacyYangihayot ? 'Yangihayot' : knownSergeli ? 'Sergeli' : 'Sergeli';
    return result(`Sergeli-${number}${suffix}`, district, legacyYangihayot || knownSergeli ? 1 : 0.75, !(legacyYangihayot || knownSergeli));
  }

  for (const [names, canonical, max, district] of [
    [['юнусабад', 'yunusabad', 'yunusobod'], 'Yunusabad', 19, 'Yunusabad'],
    [['янгихаёт', 'янгихаят', 'yangihayot'], 'Yangihayot', 6, 'Yangihayot'],
  ]) {
    match = numberedMatch(text, names);
    if (match) {
      const number = Number(match[1]);
      if (number >= 1 && number <= max) return result(`${canonical}-${number}`, district);
    }
  }

  for (const candidate of STATIC_MATCHERS) {
    if (phraseIn(text, candidate.alias)) return result(candidate.area, candidate.district);
  }

  const explicitSergeliDistrict = /(?:сергелийск\p{L}*\s+район|сергели\s+туман\p{L}*|serg(?:eli|ile|ele)\s+(?:tumani|district))/iu.test(value);
  if (!explicitSergeliDistrict && /(?:^|\s)(?:сергели|sergeli|sergile|sergele)(?:\s|$)/iu.test(text)) {
    return result('Sergeli', null, 0.35, true);
  }
  if (/(?:^|\s)(?:куйлюк|куйлик|kuylyuk|kuyliq|qoyliq)(?:\s|$)/iu.test(text)) {
    return result('Kuylyuk', null, 0.25, true);
  }
  const explicitChilanzarDistrict = /(?:чиланзарск\p{L}*\s+район|чиланзар\s+туман\p{L}*|chilanzar\s+district)/iu.test(value);
  if (!explicitChilanzarDistrict && /(?:^|\s)(?:чиланзар|чилонзор|chilanzar|chilonzor)(?:\s|$)/iu.test(text)) {
    return result('Chilanzar', null, 0.35, true);
  }

  return null;
}
