// Curated location dictionaries for parser matching. These are deliberately
// separate from locations.js so the core parser stays readable and the data can
// grow without turning location logic into one giant file.
//
// Each entry stores a canonical name plus aliases commonly seen in property
// listings. Regexes are generated from aliases with tolerant whitespace/hyphens.

function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function aliasRegex(aliases) {
  const parts = aliases
    .filter(Boolean)
    .map((alias) => escapeRegex(alias.trim()).replace(/[\s\-–—]+/g, '[\\s\\-–—]*'))
    .sort((a, b) => b.length - a.length);
  return new RegExp(`(?:^|[^\\p{L}\\p{N}_])(?:${parts.join('|')})(?:$|[^\\p{L}\\p{N}_])`, 'iu');
}

function entries(rows) {
  return rows.map(([name, ...aliases]) => ({
    name,
    aliases: [...new Set([name, ...aliases])],
    re: aliasRegex([name, ...aliases]),
  }));
}

export const LOCATION_DICTIONARIES = {
  UZ: {
    Tashkent: {
      microdistricts: entries([
        ['Chilanzar-1', 'Чиланзар 1', 'Чилонзор 1', 'Chilonzor 1'],
        ['Chilanzar-2', 'Чиланзар 2', 'Чилонзор 2', 'Chilonzor 2'],
        ['Chilanzar-3', 'Чиланзар 3', 'Чилонзор 3', 'Chilonzor 3'],
        ['Chilanzar-5', 'Чиланзар 5', 'Чилонзор 5', 'Chilonzor 5'],
        ['Chilanzar-6', 'Чиланзар 6', 'Чилонзор 6', 'Chilonzor 6'],
        ['Chilanzar-7', 'Чиланзар 7', 'Чилонзор 7', 'Chilonzor 7'],
        ['Chilanzar-8', 'Чиланзар 8', 'Чилонзор 8', 'Chilonzor 8'],
        ['Chilanzar-9', 'Чиланзар 9', 'Чилонзор 9', 'Chilonzor 9'],
        ['Chilanzar-10', 'Чиланзар 10', 'Чилонзор 10', 'Chilonzor 10'],
        ['Chilanzar-11', 'Чиланзар 11', 'Чилонзор 11', 'Chilonzor 11'],
        ['Chilanzar-12', 'Чиланзар 12', 'Чилонзор 12', 'Chilonzor 12'],
        ['Chilanzar-13', 'Чиланзар 13', 'Чилонзор 13', 'Chilonzor 13'],
        ['Chilanzar-14', 'Чиланзар 14', 'Чилонзор 14', 'Chilonzor 14'],
        ['Chilanzar-15', 'Чиланзар 15', 'Чилонзор 15', 'Chilonzor 15'],
        ['Chilanzar-16', 'Чиланзар 16', 'Чилонзор 16', 'Chilonzor 16'],
        ['Chilanzar-17', 'Чиланзар 17', 'Чилонзор 17', 'Chilonzor 17'],
        ['Chilanzar-18', 'Чиланзар 18', 'Чилонзор 18', 'Chilonzor 18'],
        ['Chilanzar-19', 'Чиланзар 19', 'Чилонзор 19', 'Chilonzor 19'],
        ['Chilanzar-20', 'Чиланзар 20', 'Чилонзор 20', 'Chilonzor 20'],
        ['Yunusabad-4', 'Юнусабад 4', 'Юнусобод 4', 'Yunusobod 4'],
        ['Yunusabad-5', 'Юнусабад 5', 'Юнусобод 5', 'Yunusobod 5'],
        ['Yunusabad-6', 'Юнусабад 6', 'Юнусобод 6', 'Yunusobod 6'],
        ['Yunusabad-7', 'Юнусабад 7', 'Юнусобод 7', 'Yunusobod 7'],
        ['Yunusabad-8', 'Юнусабад 8', 'Юнусобод 8', 'Yunusobod 8'],
        ['Yunusabad-9', 'Юнусабад 9', 'Юнусобод 9', 'Yunusobod 9'],
        ['Yunusabad-11', 'Юнусабад 11', 'Юнусобод 11', 'Yunusobod 11'],
        ['Yunusabad-12', 'Юнусабад 12', 'Юнусобод 12', 'Yunusobod 12'],
        ['Yunusabad-13', 'Юнусабад 13', 'Юнусобод 13', 'Yunusobod 13'],
        ['Yunusabad-14', 'Юнусабад 14', 'Юнусобод 14', 'Yunusobod 14'],
        ['Yunusabad-15', 'Юнусабад 15', 'Юнусобод 15', 'Yunusobod 15'],
        ['Yunusabad-16', 'Юнусабад 16', 'Юнусобод 16', 'Yunusobod 16'],
        ['Yunusabad-17', 'Юнусабад 17', 'Юнусобод 17', 'Yunusobod 17'],
        ['Yunusabad-18', 'Юнусабад 18', 'Юнусобод 18', 'Yunusobod 18'],
        ['Yunusabad-19', 'Юнусабад 19', 'Юнусобод 19', 'Yunusobod 19'],
        ['Yunusabad-20', 'Юнусабад 20', 'Юнусобод 20', 'Yunusobod 20'],
        ['Yunusabad-21', 'Юнусабад 21', 'Юнусобод 21', 'Yunusobod 21'],
        ['Yunusabad-22', 'Юнусабад 22', 'Юнусобод 22', 'Yunusobod 22'],
        ['Karakamysh', 'Каракамыш', 'Qoraqamish'],
        ['Sebzar', 'Себзар'],
        ['Tashselmash', 'Ташсельмаш'],
        ['Aviasozlar', 'Авиасозлар', 'Авиагородок'],
        ['Kuylyuk', 'Куйлюк', 'Qo‘yliq', "Qo'yliq"],
        ['Sergeli', 'Сергели массив', 'Sergeli massivi'],
        ['Sputnik', 'Спутник', 'Sputnik massivi'],
        ['Yangi Choshtepa', 'Янги Чоштепа', 'Yangi Choshtepa'],
      ]),
      metro: entries([
        ['Buyuk Ipak Yoli', 'Буюк Ипак Йули', 'Buyuk Ipak Yo‘li', "Buyuk Ipak Yo'li"],
        ['Pushkin', 'Пушкин'], ['Hamid Olimjon', 'Хамид Олимжон'], ['Amir Temur Xiyoboni', 'Амир Темур хиёбони', 'Сквер'],
        ['Mustaqillik Maydoni', 'Мустакиллик майдони', 'Площадь Независимости'], ['Paxtakor', 'Пахтакор'],
        ['Bunyodkor', 'Бунёдкор'], ['Milliy Bog', 'Миллий бог', 'Миллий Боғ'], ['Novza', 'Новза'],
        ['Mirzo Ulugbek', 'Мирзо Улугбек'], ['Chilonzor', 'Чиланзар метро', 'Чилонзор метро'], ['Olmazor', 'Алмазар метро', 'Олмазор метро'],
        ['Choshtepa', 'Чоштепа'], ['Ozgarish', 'Узгариш', 'O‘zgarish'], ['Sergeli', 'Сергели метро'], ['Yangihayot', 'Янгихаёт'], ['Chinor', 'Чинор'],
        ['Beruniy', 'Беруни'], ['Tinchlik', 'Тинчлик'], ['Chorsu', 'Чорсу'], ['Gafur Gulom', 'Гафур Гулям'], ['Alisher Navoi', 'Алишер Навои'],
        ['Ozbekiston', 'Узбекистан метро', 'O‘zbekiston'], ['Kosmonavtlar', 'Космонавтлар', 'Космонавты'], ['Oybek', 'Ойбек'], ['Toshkent', 'Ташкент метро'], ['Mashinasozlar', 'Машинасозлар'], ['Dostlik', 'Дустлик', 'Do‘stlik'],
        ['Ming Orik', 'Минг Урик', 'Ming O‘rik'], ['Yunus Rajabiy', 'Юнус Раджаби'], ['Abdulla Qodiriy', 'Абдулла Кодири'], ['Minor', 'Минор'], ['Bodomzor', 'Бодомзор'], ['Shahriston', 'Шахристан'], ['Yunusobod', 'Юнусабад метро'], ['Turkiston', 'Туркистон'],
        ['Texnopark', 'Технопарк'], ['Yashnobod', 'Яшнабад метро'], ['Tuzel', 'Тузель'], ['Olmos', 'Олмос'], ['Rohat', 'Рохат'], ['Yangiobod', 'Янгиобод'], ['Qo‘yliq', 'Куйлюк метро', "Qo'yliq"], ['Matonat', 'Матонат'], ['Qiyot', 'Киёт'], ['Tolariq', 'Толарик'], ['Xonobod', 'Ханабад'], ['Quruvchilar', 'Курувчилар'], ['Turon', 'Турон'], ['Qipchoq', 'Кипчак'],
      ]),
      residentialComplexes: entries([
        ['Nest One', 'Нест Ван'], ['Gardens Residence', 'Гарденс Резиденс'], ['Boulevard', 'Boulevard Residence', 'Бульвар'],
        ['NRG Oybek', 'NRG Ойбек'], ['NRG U-Tower', 'U Tower', 'Ю Тауэр'], ['Mirabad Avenue', 'Мирабад Авеню'],
        ['Darkhan Residence', 'Дархан Резиденс'], ['Tashkent City', 'Ташкент Сити'], ['Assalom Sohil', 'Ассалом Сохил'],
        ['Assalom Jomiy', 'Ассалом Жомий'], ['Xon Saroy', 'Хон Сарой', 'Khon Saroy'], ['Cambridge Residence', 'Кембридж Резиденс'],
        ['Infinity', 'Инфинити ЖК'], ['Do‘stlar', 'Дустлар ЖК', "Do'stlar"], ['Olmazor City', 'Алмазар Сити'],
      ]),
    },
    Samarkand: {
      microdistricts: entries([
        ['Sogdiana', 'Согдиана', 'So‘g‘diyona', "So'g'diyona"], ['Sartepa', 'Сартепа'], ['Sat-Tepo', 'Саттепо', 'Sat Tepo'],
        ['Kimyogarlar', 'Химиков', 'Кимёгарлар'], ['Vokzal', 'Вокзал район'], ['Universitet', 'Университетский район'],
        ['Registan', 'Регистан'], ['Dagbitskaya', 'Дагбитская'], ['Rudaki', 'Рудаки'],
      ]),
      residentialComplexes: entries([
        ['Samarkand City', 'Самарканд Сити'], ['Bogishamol City', 'Богишамол Сити'], ['Marokand Avenue', 'Мароканд Авеню'],
        ['Silk Road Residence', 'Силк Роуд Резиденс'], ['Registan Residence', 'Регистан Резиденс'],
      ]),
    },
  },

  KZ: {
    Almaty: {
      microdistricts: entries([
        ['Samal-1', 'Самал 1'], ['Samal-2', 'Самал 2'], ['Samal-3', 'Самал 3'], ['Orbita-1', 'Орбита 1'], ['Orbita-2', 'Орбита 2'], ['Orbita-3', 'Орбита 3'], ['Orbita-4', 'Орбита 4'],
        ['Aksai-1', 'Аксай 1'], ['Aksai-2', 'Аксай 2'], ['Aksai-3', 'Аксай 3'], ['Aksai-4', 'Аксай 4'], ['Aksai-5', 'Аксай 5'],
        ['Mamyr-1', 'Мамыр 1'], ['Mamyr-2', 'Мамыр 2'], ['Mamyr-3', 'Мамыр 3'], ['Mamyr-4', 'Мамыр 4'],
        ['Zhetysu-1', 'Жетысу 1', 'Жетісу 1'], ['Zhetysu-2', 'Жетысу 2', 'Жетісу 2'], ['Zhetysu-3', 'Жетысу 3', 'Жетісу 3'], ['Zhetysu-4', 'Жетысу 4', 'Жетісу 4'],
        ['Taugul', 'Таугуль', 'Таугүл'], ['Kazakhfilm', 'Казахфильм'], ['Koktem', 'Коктем', 'Көктем'], ['Atakent', 'Атакент'],
      ]),
      metro: entries([
        ['Raiymbek Batyr', 'Райымбек батыра', 'Райымбек батыр'], ['Zhibek Zholy', 'Жибек жолы', 'Жібек жолы'], ['Almaly', 'Алмалы'], ['Abay', 'Абая', 'Абай'], ['Baikonur', 'Байконур', 'Байқоңыр'], ['Auezov Theatre', 'Театр имени М. Ауэзова', 'Мухтара Ауэзова'], ['Alatau', 'Алатау'], ['Sairan', 'Сайран'], ['Moskva', 'Москва'], ['Saryarka', 'Сарыарка', 'Сарыарқа'], ['Bauyrzhan Momyshuly', 'Б. Момышулы', 'Бауыржан Момышулы'],
      ]),
      residentialComplexes: entries([
        ['Esentai City', 'Есентай Сити'], ['Mega Towers', 'Мега Тауэрс'], ['Gagarin Park', 'Гагарин Парк'], ['4YOU', '4 Ю', 'Фор Ю'], ['Central Avenue', 'Централ Авеню'], ['Metropole', 'Метрополь'], ['Remizovka', 'Ремизовка ЖК'], ['Al-Farabi 27', 'Аль-Фараби 27'], ['Exclusive Time', 'Эксклюзив Тайм'], ['Auezov City', 'Ауэзов Сити'],
      ]),
    },
    Astana: {
      districts: entries([
        ['Almaty', 'Алматы район', 'Алматы ауданы'], ['Saryarka', 'Сарыарка район', 'Сарыарқа ауданы'], ['Esil', 'Есиль район', 'Есіл ауданы'], ['Baikonur', 'Байконур район', 'Байқоңыр ауданы'], ['Nura', 'Нура район', 'Нұра ауданы'], ['Saraishyk', 'Сарайшык район', 'Сарайшық ауданы'],
      ]),
      microdistricts: entries([
        ['Samal', 'Самал'], ['Chubary', 'Чубары'], ['Koktal', 'Коктал', 'Көктал'], ['Urker', 'Уркер', 'Үркер'], ['Ilyinka', 'Ильинка'], ['Komsomolsky', 'Комсомольский'], ['South-East', 'Юго-Восток', 'ЮВ'], ['Tselinny', 'Целинный'],
      ]),
      residentialComplexes: entries([
        ['Highvill', 'Хайвилл', 'Highvill Astana'], ['Grand Alatau', 'Гранд Алатау'], ['Northern Lights', 'Северное Сияние'], ['Diplomatic Town', 'Дипломатический городок'], ['Expo Boulevard', 'Экспо Бульвар'], ['Promenade Expo', 'Променад Экспо'], ['Green Quarter', 'Зеленый квартал', 'Green Quarter Astana'], ['BI City Seoul', 'БИ Сити Сеул'], ['Nova City', 'Нова Сити'], ['Millennium Park', 'Миллениум Парк'],
      ]),
    },
  },

  RO: {
    Bucharest: {
      microdistricts: entries([
        ['Baneasa', 'Băneasa'], ['Aviatiei', 'Aviației'], ['Dorobanti', 'Dorobanți'], ['Floreasca'], ['Pipera'], ['Herastrau', 'Herăstrău'],
        ['Colentina'], ['Pantelimon'], ['Iancului'], ['Tei'], ['Vitan'], ['Dristor'], ['Titan'], ['Balta Alba', 'Balta Albă'],
        ['Berceni'], ['Tineretului'], ['Giurgiului'], ['Cotroceni'], ['Rahova'], ['Ferentari'], ['Drumul Taberei'], ['Militari'], ['Crangasi', 'Crângași'], ['Giulesti', 'Giulești'], ['Grozavesti', 'Grozăvești'], ['Regie'],
      ]),
      metro: entries([
        ['Pipera'], ['Aurel Vlaicu'], ['Aviatorilor'], ['Piata Victoriei', 'Piața Victoriei'], ['Gara de Nord'], ['Piata Romana', 'Piața Romană'], ['Universitate'], ['Piata Unirii', 'Piața Unirii'], ['Tineretului'], ['Eroii Revolutiei', 'Eroii Revoluției'], ['Dristor'], ['Titan'], ['Nicolae Grigorescu'], ['Anghel Saligny'], ['Politehnica'], ['Grozavesti', 'Grozăvești'], ['Eroilor'], ['Izvor'], ['Piata Iancului', 'Piața Iancului'], ['Obor'], ['Stefan cel Mare', 'Ștefan cel Mare'], ['Crangasi', 'Crângași'], ['Basarab'], ['Lujerului'], ['Gorjului'], ['Pacii', 'Păcii'], ['Preciziei'], ['Valea Ialomitei', 'Valea Ialomiței'], ['Romancierilor'], ['Parc Drumul Taberei'], ['Favorit'], ['Orizont'], ['Academia Militara', 'Academia Militară'],
      ]),
      residentialComplexes: entries([
        ['One Herastrau Park', 'One Herăstrău Park'], ['One Floreasca City'], ['One Verdi Park'], ['Up-site Bucharest', 'Up Site Bucharest'], ['Aviatiei Park', 'Aviației Park'], ['Cortina North'], ['Cortina Academy'], ['Cloud9 Residence'], ['Luxuria Residence'], ['Exigent Plaza Residence'], ['Plaza Residence'], ['21 Residence'], ['Novum Residence'], ['Belvedere Residences'], ['Global Residence Monolitului'],
      ]),
    },
    Brasov: {
      microdistricts: entries([
        ['Tractorul'], ['Coresi'], ['Astra'], ['Racadau', 'Răcădău'], ['Bartolomeu'], ['Noua'], ['Darste', 'Dârste'], ['Schei', 'Șchei'], ['Centrul Civic'], ['Centrul Vechi'], ['Florilor'], ['Scriitorilor'], ['Craiter'], ['Stupini'],
      ]),
      residentialComplexes: entries([
        ['Coresi Avantgarden', 'Avantgarden Coresi'], ['Avantgarden3', 'Avantgarden 3'], ['Urban Plaza'], ['Qualis', 'Qualis Residence'], ['Isaran Residence'], ['Maurer Residence Brasov', 'Maurer Residence Brașov'], ['Grandis Residence', 'Grandis'], ['Cosmopolit Residence'], ['Alphaville Arena'], ['Mountain View Residence'],
      ]),
    },
  },

  UA: {
    Kyiv: {
      microdistricts: entries([
        ['Pozniaky', 'Позняки'], ['Osokorky', 'Осокорки'], ['Kharkivskyi', 'Харківський масив', 'Харьковский массив'], ['Troyeshchyna', 'Троєщина', 'Троещина'], ['Vynohradar', 'Виноградар'], ['Obolon', 'Оболонь'], ['Teremky', 'Теремки'], ['Holosiiv', 'Голосіїв', 'Голосеево'], ['Solomianka', 'Солом’янка', 'Соломенка'], ['Lukianivka', 'Лук’янівка', 'Лукьяновка'], ['Nyvky', 'Нивки'], ['Sviatoshyn', 'Святошин'], ['Borshchahivka', 'Борщагівка', 'Борщаговка'], ['Pechersk', 'Печерськ', 'Печерск'], ['Podil', 'Поділ', 'Подол'],
      ]),
      residentialComplexes: entries([
        ['Respublika', 'Республіка ЖК', 'Республика ЖК'], ['Fayna Town', 'Файна Таун'], ['UNIT.Home', 'Юнит Хоум'], ['Rybalsky', 'Рибальський', 'Рыбальский'], ['Tetris Hall', 'Тетрис Холл'], ['French Quarter 2', 'Французький квартал 2', 'Французский квартал 2'], ['Novopecherski Lypky', 'Новопечерські Липки', 'Новопечерские Липки'], ['Great', 'ЖК Great'], ['Seven', 'ЖК Seven'], ['Comfort Town', 'Комфорт Таун', 'Комфорт Таун'], ['Warszawski Plus', 'Варшавський Плюс', 'Варшавский Плюс'], ['Creator City', 'Креатор Сіті'],
      ]),
    },
    Kharkiv: {
      districts: entries([
        ['Shevchenkivskyi', 'Шевченківський район', 'Шевченковский район'], ['Kyivskyi', 'Київський район', 'Киевский район'], ['Saltivskyi', 'Салтівський район', 'Салтовский район'], ['Nemyshlianskyi', 'Немишлянський район', 'Немышлянский район'], ['Industrialnyi', 'Індустріальний район', 'Индустриальный район'], ['Slobidskyi', 'Слобідський район', 'Слободской район'], ['Osnovianskyi', 'Основ’янський район', 'Основянский район'], ['Novobavarskyi', 'Новобаварський район', 'Новобаварский район'], ['Kholodnohirskyi', 'Холодногірський район', 'Холодногорский район'],
      ]),
      microdistricts: entries([
        ['Saltivka', 'Салтівка', 'Салтовка'], ['Oleksiivka', 'Олексіївка', 'Алексеевка'], ['Pavlove Pole', 'Павлове Поле', 'Павлово Поле'], ['Kholodna Hora', 'Холодна Гора', 'Холодная Гора'], ['HTZ', 'ХТЗ'], ['Nova Bavariia', 'Нова Баварія', 'Новая Бавария'], ['Zhykhar', 'Жихор'], ['Odeska', 'Одеська', 'Одесская'], ['Rohan', 'Рогань'], ['Horizont', 'Горизонт'],
      ]),
      metro: entries([
        ['Kholodna Hora', 'Холодна гора', 'Холодная гора'], ['Vokzalna', 'Вокзальна', 'Южный вокзал'], ['Tsentralnyi Rynok', 'Центральний ринок', 'Центральный рынок'], ['Maidan Konstytutsii', 'Майдан Конституції', 'Площадь Конституции'], ['Sportyvna', 'Спортивна'], ['Zavod imeni Malysheva', 'Завод імені Малишева', 'Завод имени Малышева'], ['Turboatom', 'Турбоатом'], ['Palats Sportu', 'Палац Спорту', 'Дворец Спорта'], ['Studentska', 'Студентська', 'Студенческая'], ['Heroiv Pratsi', 'Героїв Праці', 'Героев Труда'], ['Peremoha', 'Перемога', 'Победа'], ['Oleksiivska', 'Олексіївська', 'Алексеевская'], ['Naukova', 'Наукова', 'Научная'], ['Derzhprom', 'Держпром'], ['Arkhitektora Beketova', 'Архітектора Бекетова', 'Архитектора Бекетова'],
      ]),
      residentialComplexes: entries([
        ['Manhattan', 'ЖК Манхеттен'], ['River Town', 'Ривер Таун'], ['Hydropark', 'ЖК Гідропарк', 'ЖК Гидропарк'], ['Sokolnyky', 'ЖК Сокільники', 'ЖК Сокольники'], ['Pavlovsky Kvartal', 'Павлівський квартал', 'Павловский квартал'], ['Levada', 'ЖК Левада'], ['Mira', 'ЖК Миру', 'ЖК Мира'], ['Nimeckyi Proekt', 'Німецький проект', 'Немецкий проект'],
      ]),
    },
    Odesa: {
      microdistricts: entries([
        ['Arkadia', 'Аркадія', 'Аркадия'], ['Moldavanka', 'Молдаванка'], ['Tairova', 'Таїрова', 'Таирова'], ['Cheryomushky', 'Черемушки'], ['Fontan', 'Фонтан'], ['Luzanivka', 'Лузанівка', 'Лузановка'], ['Peresyp', 'Пересип', 'Пересыпь'], ['Slobidka', 'Слобідка', 'Слободка'], ['Kotivskoho', 'селище Котовського', 'поселок Котовского'],
      ]),
      residentialComplexes: entries([
        ['Kadorr City', 'Кадорр Сіті', 'Кадорр Сити'], ['44 Pearl', '44 Жемчужина', '44 Перлина'], ['51 Pearl', '51 Жемчужина', '51 Перлина'], ['Elegia Park', 'Елегія Парк', 'Элегия Парк'], ['Sea View', 'Сі Вью', 'Си Вью'], ['Unity Towers', 'Юніті Тауерс', 'Юнити Тауэрс'], ['Gagarin Plaza', 'Гагарін Плаза', 'Гагарин Плаза'], ['Otrada Sky', 'Отрада Скай'],
      ]),
    },
    Dnipro: {
      microdistricts: entries([
        ['Peremoha', 'Перемога', 'Победа'], ['Topolia', 'Тополя'], ['Sokil', 'Сокіл', 'Сокол'], ['Parus', 'Парус'], ['Pokrovskyi', 'Покровський', 'Коммунар'], ['Livoberezhnyi', 'Лівобережний', 'Левобережный'], ['Soniachnyi', 'Сонячний', 'Солнечный'], ['Kalinovskyi', 'Калиновський', 'Калиновский'], ['Pivnichnyi', 'Північний', 'Северный'],
      ]),
      residentialComplexes: entries([
        ['Bartolomeo Resort Town', 'Бартоломео'], ['River Park', 'Рівер Парк', 'Ривер Парк'], ['Felicita', 'Феліціта', 'Феличита'], ['Geneva', 'Женева ЖК'], ['Mayak', 'ЖК Маяк'], ['Manhattan', 'Манхеттен Дніпро', 'Манхеттен Днепр'], ['Salyut', 'ЖК Салют'],
      ]),
    },
    Lviv: {
      microdistricts: entries([
        ['Sykhiv', 'Сихів', 'Сихов'], ['Levandivka', 'Левандівка', 'Левандовка'], ['Riasne', 'Рясне'], ['Pidzamche', 'Підзамче', 'Подзамче'], ['Holosko', 'Голоско'], ['Pasichna', 'Пасічна', 'Пасечная'], ['Pohulianka', 'Погулянка'], ['Znesinnia', 'Знесіння', 'Знесенье'], ['Klepariv', 'Клепарів', 'Клепаров'],
      ]),
      residentialComplexes: entries([
        ['Great', 'ЖК Велика Британія', 'Велика Британія'], ['Avalon Yard', 'Авалон Ярд'], ['Avalon Flex', 'Авалон Флекс'], ['Semitsvit', 'Семицвіт', 'Семицвет'], ['Parus City', 'Парус Сіті', 'Парус Сити'], ['Viking Park', 'Вікінг Парк', 'Викинг Парк'], ['Misto Trav', 'Місто Трав', 'Город Трав'], ['Washington City', 'Вашингтон Сіті'],
      ]),
    },
  },
};

export function dictionaryFor(countryCode, city) {
  return LOCATION_DICTIONARIES[countryCode]?.[city] || null;
}

export function matchDictionaryLocation(text, countryCode, city = null) {
  const country = LOCATION_DICTIONARIES[countryCode] || {};
  const cities = city && country[city] ? [[city, country[city]]] : Object.entries(country);
  for (const [cityName, data] of cities) {
    for (const type of ['districts', 'microdistricts', 'metro', 'residentialComplexes']) {
      const match = (data[type] || []).find((entry) => entry.re.test(text));
      if (match) return { city: cityName, type, name: match.name, aliases: match.aliases };
    }
  }
  return null;
}
