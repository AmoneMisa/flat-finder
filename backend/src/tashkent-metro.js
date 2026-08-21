// Canonical Tashkent Metro catalog used by parsing, filtering and UI metadata.
// `name` is a stable language-independent API/filter value. `labels` are only
// for presentation. Aliases include Russian/Uzbek/English spellings plus common
// historical and colloquial names found in property listings.

function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function aliasRegex(aliases) {
  const parts = aliases
    .filter(Boolean)
    .map((alias) => escapeRegex(String(alias).trim()).replace(/[\s\-–—'’‘`ʻʼ]+/g, "[\\s\\-–—'’‘`ʻʼ]*"))
    .sort((a, b) => b.length - a.length);
  return new RegExp(`(?:^|[^\\p{L}\\p{N}_])(?:${parts.join('|')})(?:$|[^\\p{L}\\p{N}_])`, 'iu');
}

function station(name, ru, en, line, aliases = []) {
  const allAliases = [...new Set([name, ru, en, ...aliases])];
  return {
    name,
    line,
    labels: { ru, en },
    aliases: allAliases,
    re: aliasRegex(allAliases),
  };
}

export const TASHKENT_METRO = Object.freeze([
  // Chilonzor line — 17 stations
  station('Buyuk Ipak Yoli', 'Буюк Ипак Йули', 'Buyuk Ipak Yoli', 'chilonzor', [
    'Buyuk Ipak Yuli', "Buyuk Ipak Yo'li", 'Buyuk Ipak Yo‘li', 'Буюк Ипак Йўли',
    'БИЙ', 'Максим Горький', 'Максима Горького', 'Горького', 'Maxim Gorky', 'Maksim Gorkiy',
  ]),
  station('Pushkin', 'Пушкин', 'Pushkin', 'chilonzor'),
  station('Hamid Olimjon', 'Хамид Алимджан', 'Hamid Olimjon', 'chilonzor', [
    'Хамид Олимжон', 'Hamid Alimjan', 'Hamid Alimjon',
  ]),
  station('Amir Temur Xiyoboni', 'Амир Темур Хиёбони', 'Amir Temur Xiyoboni', 'chilonzor', [
    'Сквер', 'Amir Timur Square', 'Amir Temur',
  ]),
  station('Mustaqillik Maydoni', 'Мустакиллик майдони', 'Mustaqillik Maydoni', 'chilonzor', [
    'Площадь Независимости', 'Independence Square',
  ]),
  station('Paxtakor', 'Пахтакор', 'Paxtakor', 'chilonzor', ['Pakhtakor']),
  station('Xalqlar Dostligi', 'Халклар Дустлиги', 'Xalqlar Dostligi', 'chilonzor', [
    "Xalqlar Do'stligi", 'Xalqlar Do‘stligi', 'Халклар Дўстлиги', 'Дружба народов',
    'Bunyodkor', 'Бунёдкор',
  ]),
  station('Milliy Bog', 'Миллий Бог', 'Milliy Bog', 'chilonzor', [
    "Milliy Bog'", 'Milliy Bog‘', 'Миллий Боғ', 'Yoshlik', 'Ёшлик',
  ]),
  station('Novza', 'Новза', 'Novza', 'chilonzor', [
    'Хамза', 'Hamza', 'Hamza metro', 'метро Хамза',
  ]),
  station('Mirzo Ulugbek', 'Мирзо Улугбек', 'Mirzo Ulugbek', 'chilonzor', [
    "Mirzo Ulug'bek", 'Mirzo Ulug‘bek', 'М. Улугбек', 'метро М. Улугбек',
  ]),
  station('Chilonzor', 'Чиланзар', 'Chilonzor', 'chilonzor', [
    'Чилонзор', 'Chilanzar', 'метро Чиланзар', 'Chilonzor metro',
  ]),
  station('Olmazor', 'Алмазар', 'Olmazor', 'chilonzor', [
    'Олмазор', 'Almazar', 'Сабир Рахимов', 'Собир Рахимов', 'Sobir Raximov', 'Sabir Rakhimov',
  ]),
  station('Choshtepa', 'Чаштепа', 'Choshtepa', 'chilonzor', ['Чоштепа']),
  station('Ozgarish', 'Узгариш', 'Ozgarish', 'chilonzor', [
    "O'zgarish", 'O‘zgarish', 'Ўзгариш',
  ]),
  station('Sergeli', 'Сергели', 'Sergeli', 'chilonzor', ['метро Сергели', 'Sergeli metro']),
  station('Yangihayot', 'Янгихаёт', 'Yangihayot', 'chilonzor', ['Янгихаят']),
  station('Chinor', 'Чинар', 'Chinor', 'chilonzor', ['Чинор']),

  // O‘zbekiston line — 11 stations
  station('Beruniy', 'Беруни', 'Beruniy', 'ozbekiston', ['Beruni']),
  station('Tinchlik', 'Тинчлик', 'Tinchlik', 'ozbekiston'),
  station('Chorsu', 'Чорсу', 'Chorsu', 'ozbekiston'),
  station('Gafur Gulom', 'Гафур Гулям', 'Gafur Gulom', 'ozbekiston', [
    "G'afur G'ulom", 'Gʻafur Gʻulom', 'Ғафур Ғулом',
  ]),
  station('Alisher Navoi', 'Алишер Навои', 'Alisher Navoi', 'ozbekiston', ['Alisher Navoiy']),
  station('Ozbekiston', 'Узбекистан', 'Ozbekiston', 'ozbekiston', [
    "O'zbekiston", 'O‘zbekiston', 'Ўзбекистон',
  ]),
  station('Kosmonavtlar', 'Космонавтлар', 'Kosmonavtlar', 'ozbekiston', ['Космонавты']),
  station('Oybek', 'Ойбек', 'Oybek', 'ozbekiston'),
  station('Toshkent', 'Ташкент', 'Toshkent', 'ozbekiston', ['Tashkent metro', 'метро Ташкент']),
  station('Mashinasozlar', 'Машинасозлар', 'Mashinasozlar', 'ozbekiston'),
  station('Dostlik', 'Дустлик', 'Dostlik', 'ozbekiston', [
    "Do'stlik", 'Do‘stlik', 'Дўстлик',
  ]),

  // Yunusobod line — 8 stations
  station('Turkiston', 'Туркистон', 'Turkiston', 'yunusobod', ['Туркестан']),
  station('Yunusobod', 'Юнусабад', 'Yunusobod', 'yunusobod', [
    'Юнусобод', 'Yunusabad', 'метро Юнусабад', 'Yunusobod metro',
  ]),
  station('Shahriston', 'Шахристан', 'Shahriston', 'yunusobod', ['Шахристон']),
  station('Bodomzor', 'Бадамзар', 'Bodomzor', 'yunusobod', ['Бодомзор']),
  station('Minor', 'Минор', 'Minor', 'yunusobod'),
  station('Abdulla Qodiriy', 'Абдулла Кадыри', 'Abdulla Qodiriy', 'yunusobod', [
    'Абдулла Кодири', 'Abdulla Kadiri',
  ]),
  station('Yunus Rajabiy', 'Юнус Раджаби', 'Yunus Rajabiy', 'yunusobod', ['Yunus Rajabi']),
  station('Ming Orik', 'Мингурик', 'Ming Orik', 'yunusobod', [
    "Ming O'rik", 'Ming O‘rik', 'Минг Урик', 'Мингўрик',
  ]),

  // Circle line / 30th Anniversary of Independence line — 14 stations
  station('Texnopark', 'Технопарк', 'Texnopark', 'circle', ['Technopark']),
  station('Yashnobod', 'Яшнабад', 'Yashnobod', 'circle', ['Яшнобод']),
  station('Tuzel', 'Тузель', 'Tuzel', 'circle'),
  station('Olmos', 'Алмас', 'Olmos', 'circle', ['Олмос']),
  station('Rohat', 'Рохат', 'Rohat', 'circle'),
  station('Yangiobod', 'Янгиабад', 'Yangiobod', 'circle', ['Янгиобод']),
  station('Qoyliq', 'Куйлюк', 'Qoyliq', 'circle', [
    'Qo‘yliq', "Qo'yliq", 'Qoʻyliq', 'Куйлик', 'Қўйлиқ', 'Куйлюк метро',
  ]),
  station('Matonat', 'Матонат', 'Matonat', 'circle'),
  station('Qiyot', 'Кият', 'Qiyot', 'circle', ['Киёт']),
  station('Tolariq', 'Толарык', 'Tolariq', 'circle', ['Толарик', 'Толариқ']),
  station('Xonobod', 'Хонабад', 'Xonobod', 'circle', ['Ханабад']),
  station('Quruvchilar', 'Курувчилар', 'Quruvchilar', 'circle'),
  station('Turon', 'Туран', 'Turon', 'circle', ['Турон']),
  station('Qipchoq', 'Кипчак', 'Qipchoq', 'circle', ['Қипчоқ']),
]);

export const TASHKENT_METRO_BY_NAME = new Map(TASHKENT_METRO.map((item) => [item.name, item]));

export function canonicalTashkentMetro(value) {
  if (!value) return null;
  const direct = TASHKENT_METRO_BY_NAME.get(String(value));
  if (direct) return direct.name;
  const text = String(value);
  return TASHKENT_METRO.find((item) => item.re.test(text))?.name || null;
}

export function tashkentMetroLabels() {
  return Object.fromEntries(TASHKENT_METRO.map((item) => [item.name, {
    ru: item.labels.ru,
    en: item.labels.en,
    line: item.line,
  }]));
}
