export const UKRAINE_OBLASTS = [
  { region: 'Vinnytsia Oblast', ua: 'Вінницька область' },
  { region: 'Volyn Oblast', ua: 'Волинська область' },
  { region: 'Dnipropetrovsk Oblast', ua: 'Дніпропетровська область' },
  { region: 'Donetsk Oblast', ua: 'Донецька область' },
  { region: 'Zhytomyr Oblast', ua: 'Житомирська область' },
  { region: 'Zakarpattia Oblast', ua: 'Закарпатська область' },
  { region: 'Zaporizhzhia Oblast', ua: 'Запорізька область' },
  { region: 'Ivano-Frankivsk Oblast', ua: 'Івано-Франківська область' },
  { region: 'Kyiv Oblast', ua: 'Київська область' },
  { region: 'Kirovohrad Oblast', ua: 'Кіровоградська область' },
  { region: 'Luhansk Oblast', ua: 'Луганська область' },
  { region: 'Lviv Oblast', ua: 'Львівська область' },
  { region: 'Mykolaiv Oblast', ua: 'Миколаївська область' },
  { region: 'Odesa Oblast', ua: 'Одеська область' },
  { region: 'Poltava Oblast', ua: 'Полтавська область' },
  { region: 'Rivne Oblast', ua: 'Рівненська область' },
  { region: 'Sumy Oblast', ua: 'Сумська область' },
  { region: 'Ternopil Oblast', ua: 'Тернопільська область' },
  { region: 'Kharkiv Oblast', ua: 'Харківська область' },
  { region: 'Kherson Oblast', ua: 'Херсонська область' },
  { region: 'Khmelnytskyi Oblast', ua: 'Хмельницька область' },
  { region: 'Cherkasy Oblast', ua: 'Черкаська область' },
  { region: 'Chernivtsi Oblast', ua: 'Чернівецька область' },
  { region: 'Chernihiv Oblast', ua: 'Чернігівська область' },
];

export const SOCIAL_HOUSING_COUNTRIES = {
  UZ: {
    countryTerms: ['Узбекистан', 'Uzbekistan'],
    cities: [
      ['Tashkent', 'Ташкент'], ['Samarkand', 'Самарканд'], ['Bukhara', 'Бухара'],
      ['Namangan', 'Наманган'], ['Andijan', 'Андижан'], ['Fergana', 'Фергана'],
      ['Qarshi', 'Карши'], ['Nukus', 'Нукус'], ['Jizzakh', 'Джизак'], ['Urgench', 'Ургенч'],
    ],
    topics: ['Аренда', 'Жильё', 'Квартира', 'Недвижимость'],
    localTopics: ['Ijara', 'Kvartira', 'Uy'],
  },
  KZ: {
    countryTerms: ['Казахстан', 'Қазақстан'],
    cities: [
      ['Almaty', 'Алматы'], ['Astana', 'Астана'], ['Shymkent', 'Шымкент'],
      ['Karaganda', 'Караганда'], ['Aktobe', 'Актобе'], ['Atyrau', 'Атырау'],
      ['Pavlodar', 'Павлодар'], ['Kostanay', 'Костанай'], ['Aktau', 'Актау'],
      ['Oskemen', 'Өскемен'],
    ],
    topics: ['Аренда', 'Жильё', 'Квартира', 'Недвижимость'],
    localTopics: ['Пәтер', 'Жалға', 'Үй'],
  },
  RO: {
    countryTerms: ['România'],
    cities: [
      ['Bucharest', 'București'], ['Cluj-Napoca', 'Cluj-Napoca'], ['Timișoara', 'Timișoara'],
      ['Iași', 'Iași'], ['Brașov', 'Brașov'], ['Constanța', 'Constanța'],
      ['Craiova', 'Craiova'], ['Sibiu', 'Sibiu'], ['Oradea', 'Oradea'], ['Ploiești', 'Ploiești'],
    ],
    topics: ['Chirie', 'Apartament', 'Locuință', 'Imobiliare'],
    localTopics: [],
  },
};

function add(targets, country, target, city = null, region = null) {
  targets.push({ country, target, ...(city ? { city } : {}), ...(region ? { region } : {}) });
}

export function buildThreadsHousingCoverage() {
  const targets = [];

  for (const [country, config] of Object.entries(SOCIAL_HOUSING_COUNTRIES)) {
    for (const countryTerm of config.countryTerms) {
      for (const topic of config.topics.slice(0, 2)) add(targets, country, `${topic} ${countryTerm}`);
    }

    for (const [city, localName] of config.cities) {
      for (const topic of config.topics) add(targets, country, `${topic} ${localName}`, city);
      for (const topic of config.localTopics) add(targets, country, `${topic} ${localName}`, city);
    }
  }

  add(targets, 'UA', 'Оренда Україна');
  add(targets, 'UA', 'Житло Україна');
  add(targets, 'UA', 'Нерухомість Україна');
  for (const oblast of UKRAINE_OBLASTS) {
    // Oblast-wide searches must not be stamped with the regional centre as the
    // listing city; the post itself/normalizer can resolve a real city later.
    add(targets, 'UA', `Оренда ${oblast.ua}`, null, oblast.region);
    add(targets, 'UA', `Квартира ${oblast.ua}`, null, oblast.region);
    add(targets, 'UA', `Житло ${oblast.ua}`, null, oblast.region);
    add(targets, 'UA', `Нерухомість ${oblast.ua}`, null, oblast.region);
  }

  const seen = new Set();
  return targets.filter((target) => {
    const key = `${target.country}|${target.city || ''}|${target.region || ''}|${target.target}`.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function rotatingCoverage(targets, { maxPerCycle = 12, slotMinutes = 30 } = {}) {
  if (!Array.isArray(targets) || targets.length <= maxPerCycle) return targets || [];
  const slot = Math.floor(Date.now() / (Math.max(1, slotMinutes) * 60_000));
  const offset = (slot * maxPerCycle) % targets.length;
  return Array.from({ length: maxPerCycle }, (_, index) => targets[(offset + index) % targets.length]);
}
