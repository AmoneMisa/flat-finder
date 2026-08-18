// Ukraine-wide regional and secondary-city parser dictionary.
// Covers all 24 oblasts + AR Crimea + Kyiv + Sevastopol aliases as regional
// entities, and frequently searched secondary cities used in property listings.
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

export const UA_REGIONS = entries([
  ['Vinnytsia Oblast','Вінницька область','Винницкая область'],
  ['Volyn Oblast','Волинська область','Волынская область'],
  ['Dnipropetrovsk Oblast','Дніпропетровська область','Днепропетровская область'],
  ['Donetsk Oblast','Донецька область','Донецкая область'],
  ['Zhytomyr Oblast','Житомирська область','Житомирская область'],
  ['Zakarpattia Oblast','Закарпатська область','Закарпатская область'],
  ['Zaporizhzhia Oblast','Запорізька область','Запорожская область'],
  ['Ivano-Frankivsk Oblast','Івано-Франківська область','Ивано-Франковская область'],
  ['Kyiv Oblast','Київська область','Киевская область'],
  ['Kirovohrad Oblast','Кіровоградська область','Кировоградская область'],
  ['Luhansk Oblast','Луганська область','Луганская область'],
  ['Lviv Oblast','Львівська область','Львовская область'],
  ['Mykolaiv Oblast','Миколаївська область','Николаевская область'],
  ['Odesa Oblast','Одеська область','Одесская область'],
  ['Poltava Oblast','Полтавська область','Полтавская область'],
  ['Rivne Oblast','Рівненська область','Ровенская область'],
  ['Sumy Oblast','Сумська область','Сумская область'],
  ['Ternopil Oblast','Тернопільська область','Тернопольская область'],
  ['Kharkiv Oblast','Харківська область','Харьковская область'],
  ['Kherson Oblast','Херсонська область','Херсонская область'],
  ['Khmelnytskyi Oblast','Хмельницька область','Хмельницкая область'],
  ['Cherkasy Oblast','Черкаська область','Черкасская область'],
  ['Chernivtsi Oblast','Чернівецька область','Черновицкая область'],
  ['Chernihiv Oblast','Чернігівська область','Черниговская область'],
  ['Autonomous Republic of Crimea','Автономна Республіка Крим','Автономная Республика Крым','АР Крим','АР Крым'],
  ['Kyiv City','місто Київ','м. Київ','город Киев','г. Киев'],
  ['Sevastopol City','місто Севастополь','м. Севастополь','город Севастополь','г. Севастополь'],
]);

export const UA_SECONDARY_CITIES = {
  // Kyiv oblast
  Irpin: { aliases: ['Ірпінь','Ирпень','Irpin'], microdistricts: entries([['Central','Центр'],['Rich Town area','Річ Таун','Рич Таун'],['Synergia area','Синергія','Синергия']]) },
  Bucha: { aliases: ['Буча','Bucha'], microdistricts: entries([['Central','Центр'],['Lisova Bucha','Лісова Буча','Лесная Буча']]) },
  Brovary: { aliases: ['Бровари','Бровары','Brovary'], microdistricts: entries([['Massyv','Масив','Массив'],['Torhmash','Торгмаш']]) },
  Vyshhorod: { aliases: ['Вишгород','Вышгород','Vyshhorod'], microdistricts: entries([['Central','Центр'],['Naberezhna','Набережна','Набережная']]) },
  'Bila Tserkva': { aliases: ['Біла Церква','Белая Церковь','Bila Tserkva'], microdistricts: entries([['Levanevskyi','Леваневського','Леваневского'],['Tarashchanskyi','Таращанський','Таращанский'],['Pishchanyi','Піщаний','Песчаный']]) },
  Boryspil: { aliases: ['Бориспіль','Борисполь','Boryspil'], microdistricts: entries([['Central','Центр'],['Aeromist area','Аероміст','Аэромист']]) },
  Fastiv: { aliases: ['Фастів','Фастов','Fastiv'] },

  // Odesa oblast
  Izmail: { aliases: ['Ізмаїл','Измаил','Izmail'], microdistricts: entries([['BAM','БАМ'],['Fortetsia','Фортеця','Крепость'],['Tsentr','Центр']]) },
  Chornomorsk: { aliases: ['Чорноморськ','Черноморск','Chornomorsk','Іллічівськ','Ильичевск','Illichivsk'], microdistricts: entries([['Primorskyi','Приморський','Приморский'],['Tsentr','Центр']]) },
  Yuzhne: { aliases: ['Південне','Южне','Yuzhne','Pivdenne'] },
  BilhorodDnistrovskyi: { aliases: ['Білгород-Дністровський','Белгород-Днестровский','Bilhorod-Dnistrovskyi'] },

  // Zakarpattia
  Mukachevo: { aliases: ['Мукачево','Мукачеве','Mukachevo','Mukacheve'], microdistricts: entries([['Rosvyhovo','Росвигово'],['Pidhoriany','Підгоряни','Подгоряны'],['Palanka','Паланок']]) },
  Khust: { aliases: ['Хуст','Khust'] },
  Berehove: { aliases: ['Берегове','Берегово','Berehove','Beregszasz'] },
  Vynohradiv: { aliases: ['Виноградів','Виноградов','Vynohradiv'] },

  // Lviv oblast
  Truskavets: { aliases: ['Трускавець','Трускавец','Truskavets'] },
  Drohobych: { aliases: ['Дрогобич','Дрогобыч','Drohobych'] },
  Stryi: { aliases: ['Стрий','Stryi'] },
  Chervonohrad: { aliases: ['Шептицький','Червоноград','Sheptytskyi','Chervonohrad'] },

  // Khmelnytskyi oblast
  'Kamianets-Podilskyi': { aliases: ['Кам’янець-Подільський','Каменец-Подольский','Kamianets-Podilskyi'] },
  Shepetivka: { aliases: ['Шепетівка','Шепетовка','Shepetivka'] },

  // Dnipropetrovsk oblast
  KryvyiRih: { aliases: ['Кривий Ріг','Кривой Рог','Kryvyi Rih','Krivoy Rog'], microdistricts: entries([['95 Kvartal','95 квартал'],['Sotsmisto','Соцмісто','Соцгород'],['Veseli Terny','Веселі Терни','Веселые Терны'],['Soniachnyi','Сонячний','Солнечный']]) },
  Kamianske: { aliases: ['Кам’янське','Каменское','Kamianske','Дніпродзержинськ','Днепродзержинск','Dniprodzerzhynsk'] },
  Nikopol: { aliases: ['Нікополь','Никополь','Nikopol'] },
  Pavlohrad: { aliases: ['Павлоград','Pavlohrad'] },

  // Donetsk oblast
  Kramatorsk: { aliases: ['Краматорськ','Краматорск','Kramatorsk'] },
  Sloviansk: { aliases: ['Слов’янськ','Славянск','Sloviansk'] },
  Mariupol: { aliases: ['Маріуполь','Мариуполь','Mariupol'] },

  // Kharkiv oblast
  Lozova: { aliases: ['Лозова','Lozova'] },
  Chuhuiv: { aliases: ['Чугуїв','Чугуев','Chuhuiv'] },

  // Zaporizhzhia oblast
  Melitopol: { aliases: ['Мелітополь','Мелитополь','Melitopol'] },
  Berdyansk: { aliases: ['Бердянськ','Бердянск','Berdiansk','Berdyansk'] },

  // Mykolaiv oblast
  Pervomaisk: { aliases: ['Первомайськ','Первомайск','Pervomaisk'] },
  Voznesensk: { aliases: ['Вознесенськ','Вознесенск','Voznesensk'] },

  // Kherson oblast
  Kherson: { aliases: ['Херсон','Kherson'], microdistricts: entries([['Tavriiskyi','Таврійський','Таврический'],['Shumenskyi','Шуменський','Шуменский'],['KhBK','ХБК'],['Ostriv','Острів','Остров']]) },
  NovaKakhovka: { aliases: ['Нова Каховка','Новая Каховка','Nova Kakhovka'] },

  // Volyn
  Kovel: { aliases: ['Ковель','Kovel'] },
  Novovolynsk: { aliases: ['Нововолинськ','Нововолынск','Novovolynsk'] },

  // Rivne
  Dubno: { aliases: ['Дубно','Dubno'] },
  Varash: { aliases: ['Вараш','Кузнецовськ','Кузнецовск','Varash'] },

  // Ivano-Frankivsk oblast
  Kolomyia: { aliases: ['Коломия','Kolomyia'] },
  Yaremche: { aliases: ['Яремче','Yaremche'] },
  Kalush: { aliases: ['Калуш','Kalush'] },

  // Chernivtsi
  Khotyn: { aliases: ['Хотин','Khotyn'] },

  // Poltava
  Kremenchuk: { aliases: ['Кременчук','Kremenchuk'], microdistricts: entries([['Molodizhnyi','Молодіжний','Молодежный'],['Rakivka','Раківка','Раковка'],['Nagorna','Нагірна','Нагорная']]) },
  Myrhorod: { aliases: ['Миргород','Myrhorod'] },

  // Cherkasy
  Uman: { aliases: ['Умань','Uman'] },
  Smila: { aliases: ['Сміла','Смела','Smila'] },

  // Chernihiv
  Nizhyn: { aliases: ['Ніжин','Нежин','Nizhyn'] },
  Pryluky: { aliases: ['Прилуки','Pryluky'] },

  // Sumy
  Konotop: { aliases: ['Конотоп','Konotop'] },
  Shostka: { aliases: ['Шостка','Shostka'] },

  // Kirovohrad
  Oleksandriia: { aliases: ['Олександрія','Александрия','Oleksandriia'] },

  // Zhytomyr
  Berdychiv: { aliases: ['Бердичів','Бердичев','Berdychiv'] },
  Korosten: { aliases: ['Коростень','Korosten'] },

  // Ternopil
  Chortkiv: { aliases: ['Чортків','Чортков','Chortkiv'] },

  // Luhansk
  Sievierodonetsk: { aliases: ['Сєвєродонецьк','Северодонецк','Sievierodonetsk'] },
  Lysychansk: { aliases: ['Лисичанськ','Лисичанск','Lysychansk'] },

  // Crimea and Sevastopol aliases retained for parser completeness.
  Simferopol: { aliases: ['Сімферополь','Симферополь','Simferopol'] },
  Yalta: { aliases: ['Ялта','Yalta'] },
  Sevastopol: { aliases: ['Севастополь','Sevastopol'] },
};

for (const data of Object.values(UA_SECONDARY_CITIES)) {
  data.re = aliasRegex(data.aliases || []);
}

export function matchUkraineRegion(text) {
  return UA_REGIONS.find((entry) => entry.re.test(text)) || null;
}

export function matchUkraineSecondaryCity(text) {
  for (const [city, data] of Object.entries(UA_SECONDARY_CITIES)) {
    if (data.re.test(text)) return { city, ...data };
  }
  return null;
}
