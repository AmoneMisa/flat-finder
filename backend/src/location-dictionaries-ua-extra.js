// Extended Ukraine parser dictionary. Kept separate from the core dictionary
// because Ukrainian city coverage is intentionally broad and will continue to grow.
function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
function aliasRegex(aliases) {
  const parts = aliases.filter(Boolean).map((alias) => escapeRegex(alias.trim()).replace(/[\s\-–—]+/g, '[\\s\\-–—]*')).sort((a,b)=>b.length-a.length);
  return new RegExp(`(?:^|[^\\p{L}\\p{N}_])(?:${parts.join('|')})(?:$|[^\\p{L}\\p{N}_])`, 'iu');
}
function entries(rows) {
  return rows.map(([name, ...aliases]) => ({ name, aliases: [...new Set([name, ...aliases])], re: aliasRegex([name, ...aliases]) }));
}

export const UA_EXTRA_LOCATION_DICTIONARIES = {
  Zaporizhzhia: {
    districts: entries([
      ['Oleksandrivskyi','Олександрівський район','Александровский район'],['Zavodskyi','Заводський район','Заводской район'],['Komunarskyi','Комунарський район','Коммунарский район'],['Dniprovskyi','Дніпровський район','Днепровский район'],['Voznesenivskyi','Вознесенівський район','Вознесеновский район'],['Khortytskyi','Хортицький район','Хортицкий район'],['Shevchenkivskyi','Шевченківський район','Шевченковский район'],
    ]),
    microdistricts: entries([
      ['Khortytsia','Хортиця','Хортица'],['Baburka','Бабурка'],['Borodynskyi','Бородинський','Бородинский'],['Osypenkivskyi','Осипенківський','Осипенковский'],['Pivdennyi','Південний','Южный'],['Kosmichnyi','Космічний','Космический'],['Shevchenkivskyi','Шевченківський','Шевченковский'],
    ]),
    residentialComplexes: entries([
      ['River Hall','Рівер Холл','Ривер Холл'],['Aleksandrovsky 1','Олександрівський 1','Александровский 1'],['Comfort City','Комфорт Сіті','Комфорт Сити'],['Borodino','ЖК Бородіно','ЖК Бородино'],
    ]),
  },
  Vinnytsia: {
    microdistricts: entries([
      ['Vyshenka','Вишенька'],['Podillia','Поділля','Подолье'],['Slovianska','Слов’янка','Славянка'],['Zamostia','Замостя'],['Tyazhyliv','Тяжилів','Тяжилов'],['Stare Misto','Старе місто','Старый город'],['Akademichnyi','Академічний','Академический'],['Piatnychany','П’ятничани','Пятничаны'],
    ]),
    residentialComplexes: entries([
      ['Turkish City','Турецьке містечко','Турецкий городок'],['Premier Tower','Прем’єр Тауер','Премьер Тауэр'],['Family House','Фемілі Хаус','Family House Vinnytsia'],['Podillia City','Поділля Сіті','Подолье Сити'],['Andorra','ЖК Андорра'],
    ]),
  },
  'Ivano-Frankivsk': {
    microdistricts: entries([
      ['Pasichna','Пасічна','Пасечная'],['BAM','БАМ'],['Kaskad','Каскад'],['Pozniaky','Позитрон'],['Knyahynyn','Княгинин'],['Vovchynets','Вовчинець','Вовчинец'],['Hirka','Гірка','Горка'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Manhattan UP','Манхеттен UP'],['Main House','Мейн Хаус'],['Parus','ЖК Парус'],['Family Plaza','Фемілі Плаза'],['Central Park','Централ Парк'],['Millennium','Міленіум','Миллениум'],['Knyahynyn','ЖК Княгинин'],
    ]),
  },
  Chernivtsi: {
    microdistricts: entries([
      ['Prospekt','Проспект'],['Komarova','Комарова'],['Hraviton','Гравітон','Гравитон'],['Sadgora','Садгора'],['Roscha','Роша'],['Kalynivskyi Rynok','Калинівський ринок','Калиновский рынок'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Vodohrai','Водограй'],['Comfort Hall','Комфорт Холл'],['Family House','Фемілі Хаус Чернівці','Family House Chernivtsi'],['City Park','Сіті Парк','Сити Парк'],['Compass','Компас'],
    ]),
  },
  Uzhhorod: {
    microdistricts: entries([
      ['Bozdosh','Боздош'],['Novyi Raion','Новий район','Новый район'],['Shakhta','Шахта'],['Radanka','Радванка'],['Domanyntsi','Доманиці','Доманицы'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Park Land','Парк Ленд'],['Crystal','Крістал','Кристал'],['Sherwood','Шервуд'],['Green Land','Грін Ленд','Грин Ленд'],['Resident','Резидент'],['Bavaria','Баварія','Бавария'],
    ]),
  },
  Mukachevo: {
    microdistricts: entries([
      ['Rosvyhovo','Росвигово'],['Pidhoriany','Підгоряни','Подгоряны'],['Palanka','Паланок'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Central Park Mukachevo','Централ Парк Мукачево'],['Dream City','Дрім Сіті','Дрим Сити'],['Green Yard','Грін Ярд','Грин Ярд'],
    ]),
  },
  Lutsk: {
    microdistricts: entries([
      ['33rd District','33 мікрорайон','33 микрорайон'],['40th District','40 мікрорайон','40 микрорайон'],['55th District','55 мікрорайон','55 микрорайон'],['Teremnivskyi','Теремнівський','Теремновский'],['Hnidava','Гнідава','Гнидава'],['Kichkarivka','Кічкарівка','Кичкаревка'],['Vysypanka','Вишків','Вышков'],
    ]),
    residentialComplexes: entries([
      ['Caramel Residence','Карамель Резиденс'],['Dream Town','Дрім Таун','Дрим Таун'],['Style Up','Стайл Ап'],['Oselya Park','Оселя Парк'],['Supernova','Супернова'],
    ]),
  },
  Rivne: {
    microdistricts: entries([
      ['Pivnichnyi','Північний','Северный'],['Yuvileinyi','Ювілейний','Юбилейный'],['Boyarka','Боярка'],['Basiv Kut','Басів Кут','Басов Кут'],['Schaslyve','Щасливе','Счастливое'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Shchaslyve','ЖК Щасливе','ЖК Счастливое'],['Spectrum','Спектрум'],['Pokrovskyi','Покровський','Покровский'],['Riverside','Ріверсайд','Риверсайд'],['Family City','Фемілі Сіті','Фемили Сити'],
    ]),
  },
  Ternopil: {
    microdistricts: entries([
      ['Bam','БАМ'],['Druzhba','Дружба'],['Skhidnyi','Східний','Восточный'],['Kanada','Канада'],['Alaska','Аляска'],['Novyi Svit','Новий Світ','Новый Свет'],['Kutkivtsi','Кутківці','Кутковцы'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Manhattan','Манхеттен Тернопіль','Манхеттен Тернополь'],['Varshavskyi','Варшавський','Варшавский'],['Panorama','Панорама'],['Beverly Hills','Беверлі Хіллз','Беверли Хиллз'],['Krona Park','Крона Парк'],
    ]),
  },
  Khmelnytskyi: {
    microdistricts: entries([
      ['Ozerna','Озерна'],['Vystavka','Виставка'],['Pivdennyi-Zakhid','Південно-Західний','Юго-Западный'],['Rakove','Ракове'],['Hrechany','Гречани'],['Dubove','Дубове'],['Lezneve','Лезневе'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Urban House','Урбан Хаус'],['Dream Park','Дрім Парк','Дрим Парк'],['Avila','Авіла','Авила'],['Harmony Garden','Гармоні Гарден'],['Spring Town','Спрінг Таун','Спринг Таун'],
    ]),
  },
  Zhytomyr: {
    microdistricts: entries([
      ['Korbutivka','Корбутівка','Корбутовка'],['Polova','Польова','Полевая'],['Kroshnia','Крошня'],['Bohuniia','Богунія','Богуния'],['Malovanka','Мальованка','Малеванка'],['Smolianka','Смолянка'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Grand City Dombrovskyi','Гранд Сіті Домбровський','Гранд Сити Домбровский'],['Domashnii 2','Домашній 2','Домашний 2'],['River City','Рівер Сіті','Ривер Сити'],['Premiere Hall','Прем’єр Холл','Премьер Холл'],
    ]),
  },
  Cherkasy: {
    microdistricts: entries([
      ['Mytnytsia','Митниця'],['Pivdenno-Zakhidnyi','Південно-Західний','Юго-Западный'],['Kazbet','Казбет'],['Khimpaselyshche','Хімселище','Химпоселок'],['D','Мікрорайон Д','Микрорайон Д'],['Lunacharskyi','Луначарський','Луначарский'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Andorra','Андорра Черкаси','Андорра Черкассы'],['Symfonia','Симфонія','Симфония'],['City Park Cherkasy','Сіті Парк Черкаси','Сити Парк Черкассы'],['Pershyi Parkovyi','Перший Парковий','Первый Парковый'],
    ]),
  },
  Poltava: {
    microdistricts: entries([
      ['Almaznyi','Алмазний','Алмазный'],['Levada','Левада'],['Polovky','Половки'],['Brailky','Браїлки','Браилки'],['Ohnivka','Огнівка','Огневка'],['Podil','Поділ','Подол'],['Dublianshchyna','Дублянщина'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['City Park Poltava','Сіті Парк Полтава','Сити Парк Полтава'],['Petrivskyi Kvartal','Петрівський квартал','Петровский квартал'],['Standard','Стандарт ЖК'],['European','Європейський','Европейский'],['Family Park','Фемілі Парк','Фемили Парк'],
    ]),
  },
  Chernihiv: {
    microdistricts: entries([
      ['Masany','Масани'],['Rokossovskoho','Рокоссовського','Рокоссовского'],['Sherstianka','Шерстянка'],['Bobrovytsia','Бобровиця'],['Podusivka','Подусівка','Подусовка'],['ZAZ','ЗАЗ'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Forest','Форест Чернігів','Форест Чернигов'],['Art House','Арт Хаус'],['Kyevske','Київське','Киевское'],['Rich Town','Річ Таун','Рич Таун'],['Parus','Парус Чернігів','Парус Чернигов'],
    ]),
  },
  Sumy: {
    microdistricts: entries([
      ['Kharkivska','Харківська','Харьковская'],['Prokofieve','Прокоф’єва','Прокофьева'],['Zarichnyi','Зарічний','Заречный'],['Kurskyi','Курський','Курский'],['Romenska','Роменська','Роменская'],['Himnasii','Хіммістечко','Химгородок'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Premier','Прем’єр Суми','Премьер Сумы'],['Eurodom','Євродім','Евродом'],['Panorama','Панорама Суми','Панорама Сумы'],['Nova Budova','Нова Будова Суми','Новая Стройка Сумы'],
    ]),
  },
  Mykolaiv: {
    districts: entries([
      ['Tsentralnyi','Центральний район','Центральный район'],['Zavodskyi','Заводський район','Заводской район'],['Inhulskyi','Інгульський район','Ингульский район'],['Korabelnyi','Корабельний район','Корабельный район'],
    ]),
    microdistricts: entries([
      ['Namiv','Намив','Намыв'],['Pivnichnyi','Північний','Северный'],['Soliani','Соляні','Соляные'],['Raketne Urochyshche','Ракетне Урочище','Ракетное Урочище'],['Velyka Korenykha','Велика Корениха','Большая Корениха'],['Kulbakyne','Кульбакине'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Riviera','Рів’єра','Ривьера'],['Admiral','Адмірал','Адмирал'],['Ukrainskyi','Український','Украинский'],['Potomkinskyi','Потьомкінський','Потемкинский'],
    ]),
  },
  Kropyvnytskyi: {
    microdistricts: entries([
      ['Kovalivka','Ковалівка','Ковалевка'],['Balashivka','Балашівка','Балашовка'],['Nova Balashivka','Нова Балашівка','Новая Балашовка'],['Cheremushky','Черемушки'],['Hirnychyi','Гірничий','Горняцкий'],['Ozernyi','Озерний','Озерный'],['Tsentr','Центр'],
    ]),
    residentialComplexes: entries([
      ['Kryla','Крила','Крылья'],['European','Європейський Кропивницький','Европейский Кропивницкий'],['City Park Kropyvnytskyi','Сіті Парк Кропивницький','Сити Парк Кропивницкий'],
    ]),
  },
};
