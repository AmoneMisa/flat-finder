// Structured intra-city locations. Legacy curated data is kept for backwards
// compatibility; the dictionary resolver adds broad multilingual coverage.
import { resolveTashkentArea } from './tashkent-areas.js';
import {
  canonicalDictionaryDistrict,
  dictionaryLocationLists,
  matchDictionaryEntities,
} from './location-dictionary-resolver.js';

export const LOCATIONS = {
  UA: {
    Kyiv: {
      districts: [
        { name: 'Podil', re: /под[іi]л|подол|podil/i }, { name: 'Pechersk', re: /печерськ|печерск|pechersk/i },
        { name: 'Obolon', re: /оболон|obolon/i }, { name: 'Shevchenkivskyi', re: /шевченк[іi]вськ|шевченковск|shevchenki?v/i },
        { name: 'Solomianskyi', re: /солом[’'я]?янськ|соломенск|solomian/i }, { name: 'Darnytskyi', re: /дарниц|дарниць|darnyts/i },
        { name: 'Holosiivskyi', re: /голос[іi][їй]вськ|голосеевск|holosiiv/i }, { name: 'Dniprovskyi', re: /дн[іi]провськ|днепровск|dniprovs/i },
        { name: 'Sviatoshynskyi', re: /святошинськ|святошинск|sviatoshyn/i }, { name: 'Desnianskyi', re: /десн[’'я]?янськ|деснянск|desnian/i },
      ],
      metro: [
        { name: 'Khreshchatyk', re: /хрещатик|крещатик|khreshchatyk/i }, { name: 'Maidan Nezalezhnosti', re: /майдан незалежн|maidan nezalezhn/i },
        { name: 'Zoloti Vorota', re: /золот[іi] ворота|золотые ворота|zoloti vorota/i }, { name: 'Universytet', re: /ун[іi]верситет|университет|universytet/i },
        { name: 'Vokzalna', re: /вокзальна|вокзальная|vokzalna/i }, { name: 'Osokorky', re: /осокорки|osokorky/i },
        { name: 'Pozniaky', re: /позняки|pozniaky/i }, { name: 'Livoberezhna', re: /л[іi]вобережна|левобережная|livoberezhna/i },
        { name: 'Lukianivska', re: /лук[’'я]?ян[іi]вська|лукьяновская|lukianivska/i },
      ],
      landmarks: [
        { name: 'Maidan Nezalezhnosti', re: /майдан|maidan/i }, { name: 'Kyiv-Pechersk Lavra', re: /лавр[аи]|lavra/i },
        { name: 'Golden Gate', re: /золот[іi] ворота|золотые ворота|golden gate/i }, { name: 'Olimpiyskiy Stadium', re: /ол[іi]мп[іi]йськ|олимпийск|olimpiysk/i },
        { name: 'Andriyivskyy Descent', re: /андр[іi][ії]вськ|андреевск спуск|andriyiv/i },
      ],
    },
  },
  RO: {
    Bucharest: {
      districts: [
        { name: 'Sector 1', re: /sector\s*1\b/i }, { name: 'Sector 2', re: /sector\s*2\b/i }, { name: 'Sector 3', re: /sector\s*3\b/i },
        { name: 'Sector 4', re: /sector\s*4\b/i }, { name: 'Sector 5', re: /sector\s*5\b/i }, { name: 'Sector 6', re: /sector\s*6\b/i },
        { name: 'Pipera', re: /pipera/i }, { name: 'Militari', re: /militari/i }, { name: 'Drumul Taberei', re: /drumul taberei/i },
        { name: 'Titan', re: /\btitan\b/i }, { name: 'Berceni', re: /berceni/i }, { name: 'Floreasca', re: /floreasca/i },
        { name: 'Dorobanti', re: /doroban[țt]i/i }, { name: 'Cotroceni', re: /cotroceni/i },
      ],
      metro: [
        { name: 'Piata Unirii', re: /pia[țt]a unirii|unirii/i }, { name: 'Piata Victoriei', re: /pia[țt]a victoriei|victoriei/i },
        { name: 'Universitate', re: /universitate/i }, { name: 'Aviatorilor', re: /aviatorilor/i }, { name: 'Pipera', re: /\bpipera\b/i },
        { name: 'Dristor', re: /dristor/i }, { name: 'Politehnica', re: /politehnica/i }, { name: 'Gara de Nord', re: /gara de nord/i },
      ],
      landmarks: [
        { name: 'Palace of Parliament', re: /casa poporului|palace of parliament|parlament/i }, { name: 'Old Town', re: /centrul vechi|old town|lipscani/i },
        { name: 'Herastrau Park', re: /her[ăa]str[ăa]u|parcul her/i }, { name: 'AFI Cotroceni', re: /afi cotroceni|afi mall/i },
      ],
    },
  },
  KZ: {
    Almaty: {
      districts: [
        { name: 'Almaly', re: /алмалинск|almaly|алмалы/i }, { name: 'Bostandyk', re: /бостандык|бостандық|bostandyk/i },
        { name: 'Medeu', re: /медеу|medeu/i }, { name: 'Auezov', re: /ауэзов|[әa]уезов|auezov/i }, { name: 'Turksib', re: /турксиб|t[uü]rksib/i },
        { name: 'Nauryzbay', re: /наурызбай|nauryzbay/i }, { name: 'Alatau', re: /алатау(?:ский)?|alatau/i }, { name: 'Zhetysu', re: /жетысу|жетісу|zhetysu/i },
      ],
      metro: [
        { name: 'Abay', re: /абая|abay/i }, { name: 'Almaly', re: /алмалы|almaly/i }, { name: 'Baikonur', re: /байконур|baikonur/i },
        { name: 'Zhibek Zholy', re: /жибек жолы|жібек жолы|zhibek zholy/i }, { name: 'Raiymbek Batyr', re: /райымбек|raiymbek/i },
        { name: 'Moskva', re: /москва(?: станц)?|moskva/i }, { name: 'Sairan', re: /сайран|sairan/i }, { name: 'Alatau', re: /алатау(?: станц)?|alatau/i },
      ],
      landmarks: [
        { name: 'Kok-Tobe', re: /кок-?тобе|k[oö]k-?tobe/i }, { name: 'Medeu', re: /медеу|medeu/i },
        { name: 'Republic Square', re: /площад[ьи] республики|republic square/i }, { name: 'Green Bazaar', re: /зелен[ыои]й базар|green bazaar/i },
        { name: 'Panfilov Park', re: /панфилов|panfilov/i },
      ],
    },
  },
  UZ: {
    Tashkent: {
      districts: [
        { name: 'Almazar', re: /алмазарск|олмазор|almazar|olmazor/i }, { name: 'Bektemir', re: /бектемир|bektemir/i },
        { name: 'Chilanzar', re: /чиланзарск[а-яё]*\s+район|чиланзар\s+туман[а-яё]*|chilanzar\s+district/i }, { name: 'Yunusabad', re: /юнусабад|yunusobod|yunusabad/i },
        { name: 'Mirzo Ulugbek', re: /мирзо[\s-]?улугбек|mirzo[\s-]?ulug'?bek/i }, { name: 'Yakkasaray', re: /яккасарай|yakkasaroy|yakkasaray/i },
        { name: 'Shaykhantahur', re: /шайхантахур|shayxontohur|shaykhantahur/i }, { name: 'Yashnobod', re: /яшнабад|yashnobod|yashnabad/i },
        { name: 'Sergeli', re: /сергелийск[а-яё]*\s+район|сергели\s+туман[а-яё]*|serg(?:eli|ile|ele)\s+(?:tumani|district)/i },
        { name: 'Uchtepa', re: /уч\s*теп|uch\s*tepa/i }, { name: 'Mirobod', re: /мир[оа]б[оа]д|mirobod|mirabad/i }, { name: 'Yangihayot', re: /янгиха[её]т|янгихаят|yangihayot/i },
      ],
      metro: [
        { name: 'Chilonzor', re: /(?:метро|станц(?:ия|ии)?|metro|station)\s*чиланзар|чиланзар\s*(?:метро|станц(?:ия|ии)?)|(?:metro|station)\s*chilonzor|chilonzor\s*(?:metro|station)/i },
        { name: 'Mustaqillik Maydoni', re: /мустакиллик|mustaqillik maydoni/i }, { name: 'Kosmonavtlar', re: /космонавт|kosmonavtlar/i },
        { name: 'Alisher Navoi', re: /алишер навои|alisher navoi/i }, { name: 'Buyuk Ipak Yuli', re: /буюк ипак|buyuk ipak yuli/i },
        { name: 'Pushkin', re: /пушкин|pushkin/i }, { name: 'Bodomzor', re: /бодомзор|bodomzor/i }, { name: 'Yunusobod', re: /юнусабад(?: станц)?|yunusobod/i },
        { name: 'Sergeli', re: /(?:метро|станц(?:ия|ии)?|metro|station)\s*сергели|сергели\s*(?:метро|станц(?:ия|ии)?)|(?:metro|station)\s*serg(?:eli|ile|ele)|serg(?:eli|ile|ele)\s*(?:metro|station)/i },
        { name: 'Tashkent North Railway Station', re: /(?:метро\s*)?(?:ташкент\s*)?(?:северн[а-яё]*\s+вокзал|toshkent\s+shimoliy\s+vokzal|tashkent\s+north\s+(?:railway\s+)?station)/i },
      ],
      landmarks: [
        { name: 'Chorsu Bazaar', re: /чорсу|chorsu/i }, { name: 'Alay Bazaar', re: /алайск|олой\s+бозор|alay\s+bazaar/i },
        { name: 'C-2', re: /(?:^|[^\p{L}\p{N}_])(?:ц|c)\s*[-–]?\s*2(?:$|[^\p{L}\p{N}_])/iu }, { name: 'Darkhan', re: /дархан|darhan|darkhan/i },
        { name: 'Novomoskovskaya', re: /новомосковск|novomoskovsk/i }, { name: 'Amir Timur Square', re: /амир тимур|амира темура|amir timur/i },
        { name: 'Independence Square', re: /площад[ьи] независимости|mustaqillik maydoni|independence square/i }, { name: 'Minor Mosque', re: /мечет[ьи] минор|minor masjid|minor mosque/i },
        { name: 'Bobur Park', re: /(?:парк\s*(?:имени\s*)?бобур|бобур\w*\s*парк|bobur\s*(?:bog[‘’'`ʻʼ]?i|park)|park\s*bobur)/i },
        { name: 'Farhod Bazaar', re: /farhod\s+bozor|фархадск[а-яё]*\s+базар|фарход\s+бозор/i },
        { name: 'Nizami Pedagogical University', re: /(?:^|[^\p{L}\p{N}_])nizomiy(?:$|[^\p{L}\p{N}_])|низамий\s+(?:педагогик[а-яё]*\s+)?университет/iu },
        { name: 'World Languages University', re: /jahon\s+tillar(?:i)?\s+universitet|жа[ҳх]он\s+тиллар[а-яё]*\s+университет|(?:^|[^\p{L}\p{N}_])иняз(?:$|[^\p{L}\p{N}_])/iu },
        { name: 'Yangi Choshtepa', re: /yangi\s+cho['’`ʻʼ]?shtepa|янги\s+чоштепа/i },
        { name: 'Sergeli Car Bazaar', re: /serg(?:eli|ile|ele)\s+(?:m[oa]sh[ei]na|avto)\s+bozor|сергели\s+(?:машин|авто)[а-яё]*\s+(?:бозор|базар)/i },
      ],
    },
  },
};

const GENERIC_NEARBY = [
  { name: 'Park', re: /(?:^|[^\p{L}\p{N}_])(?:парк|park|bog[‘’'`ʻʼ]?i?)(?:$|[^\p{L}\p{N}_])/iu },
  { name: 'Bus stop', re: /автобусн\w*\s+(?:останов|конеч)|остановк\w*\s+автобус|avtobus\s+(?:bekat\w*|kanichka\w*|konichka\w*)/iu },
  { name: 'Clinic', re: /пол[иe]клиник|pol[ei]klinik/iu },
  { name: 'School', re: /(?:^|[^\p{L}\p{N}_])(?:школ[а-яё]*|maktab[a-z]*)(?:$|[^\p{L}\p{N}_])/iu },
  { name: 'Kindergarten', re: /детск\w*\s+сад|bolalar\s+bog[‘’'`ʻʼ]?chasi/iu },
  { name: 'Shopping center', re: /(?:^|[^\p{L}\p{N}_])(?:тц|трц|shopping\s+cent(?:er|re)|savdo\s+markazi)(?:$|[^\p{L}\p{N}_])/iu },
  { name: 'Mosque', re: /(?:^|[^\p{L}\p{N}_])(?:мечет[а-яё]*|masjid|mosque)(?:$|[^\p{L}\p{N}_])/iu },
];

export function parseLocation(text, countryCode) {
  const result = {
    region: null, district: null, microdistrict: null, residentialComplex: null,
    area: null, areaAmbiguous: false, locationConfidence: null,
    requireExactAddress: false, metro: null, nearby: [], city: null,
  };
  if (!text) return result;

  const dictionary = matchDictionaryEntities(text, countryCode);
  result.region = dictionary.region;
  result.microdistrict = dictionary.microdistrict;
  result.residentialComplex = dictionary.residentialComplex;
  result.city = dictionary.city;
  result.district = dictionary.district;
  result.metro = dictionary.metro;

  const country = LOCATIONS[countryCode];
  if (countryCode === 'UZ') {
    const resolvedArea = resolveTashkentArea(text);
    if (resolvedArea) {
      result.area = resolvedArea.area;
      result.district = resolvedArea.district || result.district;
      result.areaAmbiguous = resolvedArea.ambiguous;
      result.locationConfidence = resolvedArea.confidence;
      result.requireExactAddress = resolvedArea.requireExactAddress;
      result.city = 'Tashkent';
    }
  }

  if (country) {
    for (const [cityName, city] of Object.entries(country)) {
      if (!result.district) {
        const d = (city.districts || []).find((x) => x.re.test(text));
        if (d) { result.district = d.name; if (!result.city) result.city = cityName; }
      }
      if (!result.metro) {
        const m = (city.metro || []).find((x) => x.re.test(text));
        if (m) { result.metro = m.name; if (!result.city) result.city = cityName; }
      }
      for (const l of city.landmarks || []) {
        if (result.nearby.length >= 4) break;
        if (l.re.test(text) && !result.nearby.includes(l.name)) {
          result.nearby.push(l.name);
          if (!result.city) result.city = cityName;
        }
      }
    }
  }

  for (const item of GENERIC_NEARBY) {
    if (result.nearby.length >= 6) break;
    if (item.name === 'Park' && result.nearby.some((name) => /Park$/i.test(name))) continue;
    if (item.re.test(text) && !result.nearby.includes(item.name)) result.nearby.push(item.name);
  }
  return result;
}

export function canonicalDistrict(name, countryCode) {
  if (!name || typeof name !== 'string') return name || null;
  const dictionary = canonicalDictionaryDistrict(name, countryCode);
  if (dictionary) return dictionary;
  const country = LOCATIONS[countryCode];
  if (!country) return name;
  for (const city of Object.values(country)) {
    const d = (city.districts || []).find((x) => x.re.test(name));
    if (d) return d.name;
  }
  return name;
}

export function cityLocations(countryCode) {
  const country = LOCATIONS[countryCode] || {};
  const extended = dictionaryLocationLists(countryCode);
  const cities = new Set([...Object.keys(country), ...Object.keys(extended)]);
  const out = {};
  for (const city of cities) {
    const legacy = country[city] || { districts: [], metro: [] };
    const extra = extended[city] || { districts: [], metro: [], microdistricts: [], residentialComplexes: [] };
    out[city] = {
      districts: [...new Set([...(legacy.districts || []).map((x) => x.name), ...extra.districts])],
      metro: [...new Set([...(legacy.metro || []).map((x) => x.name), ...extra.metro])],
      microdistricts: extra.microdistricts,
      residentialComplexes: extra.residentialComplexes,
    };
  }
  return out;
}
