from pathlib import Path


def replace(path, old, new):
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f'marker missing in {path}: {old[:80]!r}')
    p.write_text(s.replace(old, new, 1))

replace('backend/src/mock.js', "import { LOCATIONS } from './locations.js';", "import { cityLocations } from './locations.js';")
replace('backend/src/mock.js', "    const cityLoc = LOCATIONS[countryCode]?.[cityName];\n    const pick = (arr) => (arr && arr.length ? arr[Math.floor(rand() * arr.length)].name : null);", "    const cityLoc = cityLocations(countryCode)?.[cityName];\n    const pick = (arr) => (arr && arr.length ? arr[Math.floor(rand() * arr.length)] : null);")

replace('backend/src/normalize.js', "    : (housingStructured.rooms ?? parseRoomsFromText(combined));", "    : (parseRoomsFromText(combined) ?? housingStructured.rooms);")
replace('backend/src/normalize.js', "    : (housingStructured.floor.floor ?? parsedFloor.floor);", "    : (parsedFloor.floor ?? housingStructured.floor.floor);")
replace('backend/src/normalize.js', "    : (housingStructured.floor.totalFloors ?? parsedFloor.totalFloors);", "    : (parsedFloor.totalFloors ?? housingStructured.floor.totalFloors);")
replace('backend/src/normalize.js', "  const sourceCity = parseCanonicalCity(country, partial.city || '');\n  const loc = parseLocation(combined, country, sourceCity || null);\n  const city = sourceCity || parseCanonicalCity(country, loc.city || '');\n  const coords = sourceCoordinates(partial, city, country);\n  const explicitDistrict = parseExplicitDistrict(combined, country);", "  const sourceCity = parseCanonicalCity(country, partial.city || '');\n  const explicitDistrict = parseExplicitDistrict(combined, country);\n  const loc = parseLocation(combined, country, sourceCity || null);\n  const city = sourceCity || parseCanonicalCity(country, loc.city || '') || (country === 'UZ' && explicitDistrict ? 'Tashkent' : '');\n  const coords = sourceCoordinates(partial, city, country);")
replace('backend/src/normalize.js', "  const residenceComplex = partial.residenceComplex\n    ?? loc.residentialComplex\n    ?? parseResidentialComplex(combined);", "  const parsedResidenceComplex = parseResidentialComplex(combined);\n  const kharkivVorobioviHory = country === 'UA' && city === 'Kharkiv' && /вороб[ьъ]?[её]вы\\s+горы/iu.test(combined);\n  const preferLocalResidence = country === 'UZ' || /^\\d+ Жемчужина$/u.test(parsedResidenceComplex || '') || kharkivVorobioviHory;\n  const canonicalLocalResidence = kharkivVorobioviHory ? 'Vorobiovi Hory' : parsedResidenceComplex;\n  const residenceComplex = partial.residenceComplex\n    ?? (preferLocalResidence ? (canonicalLocalResidence ?? loc.residentialComplex) : (loc.residentialComplex ?? canonicalLocalResidence));")

p = Path('backend/src/locations.js')
s = p.read_text()
import_marker = "import { resolveTashkentArea } from './tashkent-areas.js';\n"
if import_marker not in s: raise SystemExit('locations import marker missing')
s = s.replace(import_marker, import_marker + "import { TASHKENT_METRO } from './tashkent-metro.js';\n", 1)
marker = "const GENERIC_NEARBY = GENERIC_LANDMARK_TERMS.map((item) => ({\n  name: item.canonical,\n  re: aliasesToRegex([item.canonical, ...aliasesOf(item)]),\n}));\n"
insert = r'''
const TASHKENT_COMPAT_LANDMARKS = [
  ['Bobur Park', /(?:^|[^\p{L}\p{N}_])(?:bobur\s+bog['’`i]*|бобур\s+парк)(?=$|[^\p{L}\p{N}_])/iu],
  ['Bus stop', /(?:avtobus|автобус)[^\r\n,;]{0,18}(?:kanichkasi|bekati|остановк)/iu],
  ['Clinic', /(?:poleklinika|poliklinika|поликлиник)/iu],
  ['School', /(?:^|[^\p{L}\p{N}_])(?:maktab|мактаб|школа)(?=$|[^\p{L}\p{N}_])/iu],
  ['Alay Bazaar', /(?:^|[^\p{L}\p{N}_])(?:алайск(?:ий|ого)|алай|alay)(?=$|[^\p{L}\p{N}_])/iu],
  ['C-2', /(?:^|[^\p{L}\p{N}_])(?:ц|c)\s*[-–]?\s*2(?=$|[^\p{L}\p{N}_])/iu],
  ['Darkhan', /(?:^|[^\p{L}\p{N}_])(?:дархан|darkhan)(?=$|[^\p{L}\p{N}_])/iu],
  ['Novomoskovskaya', /(?:^|[^\p{L}\p{N}_])(?:новомосковск(?:ая|ой)|novomoskovskaya)(?=$|[^\p{L}\p{N}_])/iu],
  ['Yangi Choshtepa', /(?:^|[^\p{L}\p{N}_])(?:янги\s+чоштепа|yangi\s+choshtepa)(?=$|[^\p{L}\p{N}_])/iu],
  ['Sergeli Car Bazaar', /(?:^|[^\p{L}\p{N}_])(?:serg(?:eli|ile|ele)|сергели)[^\r\n]{0,24}(?:mashina|moshena|машин)[^\r\n]{0,12}(?:bozor|бозор|базар|рынок)(?=$|[^\p{L}\p{N}_])/iu],
  ['Nizami Pedagogical University', /(?:низомий|nizomiy)[^\r\n]{0,35}(?:universitet|университет)/iu],
  ['World Languages University', /(?:жахон|жаҳон|jahon)[^\r\n]{0,35}(?:tillar|тиллар)[^\r\n]{0,25}(?:universitet|университет)/iu],
];

function explicitTashkentMetro(text) {
  if (/(?:ташкент|toshkent)\s+северн\p{L}*\s+вокзал/iu.test(text)) return 'Tashkent North Railway Station';
  const explicit = String(text).match(/(?:метро|metro|м\.)\s*[:\-–—]?\s*([^\n,.;]{2,52})/iu)?.[1] || '';
  if (explicit) {
    for (const station of TASHKENT_METRO) {
      station.re.lastIndex = 0;
      if (station.re.test(explicit)) return station.name;
    }
  }
  const beforeMarker = String(text).match(/(?:^|[^\p{L}\p{N}_])([\p{L}'’`-]{3,28})\s+metro(?:da|ga)?(?=$|[^\p{L}\p{N}_])/iu)?.[1] || '';
  if (beforeMarker) {
    for (const station of TASHKENT_METRO) {
      station.re.lastIndex = 0;
      if (station.re.test(beforeMarker)) return station.name;
    }
  }
  return null;
}
'''
if marker not in s: raise SystemExit('locations marker missing')
s = s.replace(marker, marker + insert, 1)
old = "      result.city = 'Tashkent';\n    }\n  }\n\n  for (const item of GENERIC_NEARBY) {"
new = "      result.city = 'Tashkent';\n    }\n\n    const explicitMetro = explicitTashkentMetro(text);\n    if (explicitMetro) result.metro = explicitMetro;\n    if (result.metro === 'Chilonzor' && /(?:чилонзор|chilonzor|чиланзар|chilanzar)\\s*[-№#]?\\s*\\d{1,2}(?!\\d)/iu.test(text) && !/(?:чилонзор|chilonzor|чиланзар|chilanzar)\\s+metro/iu.test(text)) {\n      result.metro = null;\n    }\n\n    for (const [name, re] of TASHKENT_COMPAT_LANDMARKS) {\n      if (!re.test(text)) continue;\n      result.city ||= 'Tashkent';\n      if (!result.nearby.includes(name)) result.nearby.push(name);\n    }\n  }\n\n  for (const item of GENERIC_NEARBY) {\n    if (item.name === 'Metro') continue;\n    if (item.name === 'Market' && result.nearby.some((name) => /Bazaar$/i.test(name))) continue;"
if old not in s: raise SystemExit('locations UZ close marker missing')
s = s.replace(old, new, 1)
p.write_text(s)

p = Path('backend/src/location-dictionary-resolver.js')
s = p.read_text()
s = s.replace("    else if (item.type === 'metro' && !result.metro) result.metro = item.name;", "    else if (item.type === 'metro') { /* contextual metro matching is handled below */ }", 1)
s = s.replace("    if (item.type === 'microdistrict' && !result.microdistrict) result.microdistrict = item.name;", "    if (item.type === 'microdistrict') result.microdistrict = item.name;", 1)
s = s.replace("    else if (item.type === 'residential_complex' && !result.residentialComplex) result.residentialComplex = item.name;", "    else if (item.type === 'residential_complex') result.residentialComplex = item.name;", 1)
old = "  const cities = mergedCountry(countryCode);\n  let ordered;\n  if (central?.city && cities[central.city]) {\n    ordered = [[central.city, cities[central.city]]];"
new = "  const cities = mergedCountry(countryCode);\n  if (countryCode === 'UZ') {\n    const tashkentRc = matchTashkentResidentialComplex(text);\n    const tashkentLandmark = matchTashkentPoi(text);\n    if (tashkentRc || tashkentLandmark) {\n      result.city ||= 'Tashkent';\n      if (tashkentRc && !result.residentialComplex) result.residentialComplex = tashkentRc.name;\n      if (tashkentLandmark && !result.landmark) {\n        result.landmark = tashkentLandmark.name;\n        result.landmarkCategory = tashkentLandmark.category || tashkentLandmark.entityType || null;\n      }\n    }\n  }\n  let ordered;\n  const resolvedCity = central?.city || result.city;\n  if (resolvedCity && cities[resolvedCity]) {\n    ordered = [[resolvedCity, cities[resolvedCity]]];"
if old not in s: raise SystemExit('resolver city marker missing')
s = s.replace(old, new, 1)
p.write_text(s)

p = Path('backend/src/tashkent-areas.js')
s = p.read_text()
s = s.replace("  if (!explicitSergeliDistrict && /(?:^|\\s)(?:сергели|sergeli|sergile|sergele)(?:\\s|$)/iu.test(text)) {\n    return result('Sergeli', null, 0.35, true);\n  }", "  if (explicitSergeliDistrict) return result('Sergeli', 'Sergeli');\n  if (/(?:^|\\s)(?:сергели|sergeli|sergile|sergele)(?:\\s|$)/iu.test(text)) {\n    return result('Sergeli', null, 0.35, true);\n  }", 1)
s = s.replace("  if (!explicitChilanzarDistrict && /(?:^|\\s)(?:чиланзар|чилонзор|chilanzar|chilonzor)(?:\\s|$)/iu.test(text)) {\n    return result('Chilanzar', null, 0.35, true);\n  }", "  if (explicitChilanzarDistrict) return result('Chilanzar', 'Chilanzar');\n  if (/(?:^|\\s)(?:чиланзар|чилонзор|chilanzar|chilonzor)(?:\\s|$)/iu.test(text)) {\n    return result('Chilanzar', null, 0.35, true);\n  }", 1)
p.write_text(s)

replace('backend/src/textparse-overrides.js', "['Uchtepa', /учтепинск[а-яё]*\\s+район|уч\\s*теп[а-яё]*\\s+район|uchtepa\\s+(?:tumani|district)/iu],", "['Uchtepa', /учтепинск[а-яё]*\\s+район|уч\\s*теп[а-яё]*\\s+район|uchtepa\\s+(?:tumani|district)|(?:^|[^\\p{L}\\p{N}_])uch\\s*tepa(?=\\s+\\d{1,3}\\s*[-–]?\\s*kvartal)/iu],")
replace('backend/src/textparse-overrides.js', "['Yashnobod', /яшнабадск[а-яё]*\\s+район|yashnobod\\s+(?:tumani|district)/iu],", "['Yashnobod', /яшнабадск[а-яё]*\\s+район|(?:^|[^\\p{L}\\p{N}_])#?яшнабадск[а-яё]*(?=$|[^\\p{L}\\p{N}_])|yashnobod\\s+(?:tumani|district)/iu],")

replace('backend/test/city-canonicalization.test.js', "test('keeps an unknown source city instead of discarding it', () => {\n  assert.equal(listing('Yangiyul').city, 'Yangiyul');\n});", "test('canonicalizes known Yangiyul spelling and keeps a genuinely unknown source city', () => {\n  assert.equal(listing('Yangiyul').city, 'Yangiyol');\n  assert.equal(listing('Imaginaryville').city, 'Imaginaryville');\n});")
