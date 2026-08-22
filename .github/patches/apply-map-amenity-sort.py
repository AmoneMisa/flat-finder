from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"{path}: expected one match, got {n}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1))


# textparse.js
replace_once(
    "backend/src/textparse.js",
    "// Air-conditioner / split system present.\nexport function parseAirConditioner(text) {\n",
    """// Dishwasher present. It used to live only in the free-form amenities array.\nexport function parseDishwasher(text) {\n  if (!text) return null;\n  return /(?:посудомо|посудомийн|dishwasher|idish\\s*yuvish|idishyuvg|ma[șs]ina de sp[ăa]lat vase)/i.test(text) ? true : null;\n}\n\nexport function parseTerrace(text) {\n  if (!text) return null;\n  return /(?:террас|терас|terrace|teras(?:ă|a)?|patio)/i.test(text) ? true : null;\n}\n\nexport function parsePrivateYard(text) {\n  if (!text) return null;\n  return /(?:личн(?:ый|ого|ым)\\s+двор|сво[йеё]\\s+(?:закрыт(?:ый|ого)\\s+)?двор|собственн(?:ый|ого)\\s+двор|приватн(?:ий|ый)\\s+двір|власн(?:ий|ого)\\s+двір|private\\s+(?:courtyard|yard)|curte\\s+(?:proprie|privat[ăa])|o['’`]?z\\s+hovli(?:si)?|shaxsiy\\s+hovli)/i.test(text) ? true : null;\n}\n\n// Air-conditioner / split system present.\nexport function parseAirConditioner(text) {\n""",
)

# normalize.js imports / address / fields / filters
replace_once(
    "backend/src/normalize.js",
    "  parseNewBuilding, parseParking, parseSmoking, parseYear,\n",
    "  parseNewBuilding, parseParking, parseSmoking, parseYear, parseDishwasher, parseTerrace, parsePrivateYard,\n",
)
replace_once(
    "backend/src/normalize.js",
    "  const street = text.match(/((?:ул(?:иц[аы])?|просп(?:ект)?|проспект|мкр|микрорайон|проезд|переулок)\\.?\\s+[^\\n,.;]{2,40}(?:,?\\s*\\d+[\\w/-]*)?|[^\\n,.;]{2,40}\\s+(?:ko['’]?chasi|k[oó]chasi))/i);\n  return street ? street[1].replace(/\\s+/g, ' ').trim() : null;\n",
    """  const street = text.match(/((?:ул(?:иц[аы])?|просп(?:ект)?|проспект|мкр|микрорайон|проезд|переулок)\\.?\\s+[^\\n,.;]{2,40}(?:,?\\s*\\d+[\\w/-]*)?|[^\\n,.;]{2,40}\\s+(?:ko['’]?chasi|k[oó]chasi))/i);\n  if (street) return street[1].replace(/\\s+/g, ' ').trim();\n  // Common OLX form: `Одесса, район Аркадии, Балтиморская 9, 160 кв.м`.\n  const bare = text.match(/(?:^|[,;\\n]\\s*)([\\p{L}][\\p{L}'’.-]*(?:\\s+[\\p{L}][\\p{L}'’.-]*){0,4}\\s+\\d+[\\p{L}0-9/-]*)(?=\\s*(?:[,.;\\n]|$))/iu);\n  return bare ? bare[1].replace(/\\s+/g, ' ').trim() : null;\n""",
)
replace_once(
    "backend/src/normalize.js",
    "  const balcony = partial.balcony ?? parseBalcony(combined); const airConditioner = partial.airConditioner ?? parseAirConditioner(combined);\n",
    "  const balcony = partial.balcony ?? parseBalcony(combined); const terrace = partial.terrace ?? parseTerrace(combined); const privateYard = partial.privateYard ?? parsePrivateYard(combined);\n  const dishwasher = partial.dishwasher ?? parseDishwasher(combined); const airConditioner = partial.airConditioner ?? parseAirConditioner(combined);\n",
)
replace_once(
    "backend/src/normalize.js",
    "    commercial, petsAllowed, childrenAllowed, roomOnly, deposit, depositAmount, depositCurrency, commission, commissionPercent, balcony,\n    airConditioner, gas, bathrooms, newBuilding, communalSeparated, kvartal, nearbyShops, parking, elevator, heating,\n",
    "    commercial, petsAllowed, childrenAllowed, roomOnly, deposit, depositAmount, depositCurrency, commission, commissionPercent, balcony, terrace, privateYard,\n    dishwasher, airConditioner, gas, bathrooms, newBuilding, communalSeparated, kvartal, nearbyShops, parking, elevator, heating,\n",
)
replace_once(
    "backend/src/normalize.js",
    "  const {propertyType,agency,priceMin,priceMax,priceTolerance,priceCurrency,query,dealType,roomsMin,roomsMax,bedroomsMin,bedroomsMax,areaMin,areaMax,pricePerSqmMin,pricePerSqmMax,floorMin,floorMax,totalFloorsMin,totalFloorsMax,yearMin,yearMax,newBuilding,audience,city,cityAliases,district,metro,metroMaxM,nearbyMaxM,nearbyKind,listingId,pets,children,roomOnly,maxAgeDays,sources}=filters;\n",
    "  const {propertyType,agency,priceMin,priceMax,priceTolerance,priceCurrency,query,dealType,roomsMin,roomsMax,bedroomsMin,bedroomsMax,areaMin,areaMax,pricePerSqmMin,pricePerSqmMax,floorMin,floorMax,totalFloorsMin,totalFloorsMax,yearMin,yearMax,newBuilding,audience,city,cityAliases,district,metro,metroMaxM,nearbyMaxM,nearbyKind,listingId,pets,children,roomOnly,dishwasher,airConditioner,parking,internet,gas,balcony,terrace,privateYard,maxAgeDays,sources}=filters;\n",
)
replace_once(
    "backend/src/normalize.js",
    "    if(yearMin!=null&&(l.buildingYear==null||l.buildingYear<yearMin))return false;if(yearMax!=null&&(l.buildingYear==null||l.buildingYear>yearMax))return false;if(newBuilding===true&&l.newBuilding!==true)return false;if(audience&&audience!=='any'&&l.audience!==audience)return false;if(pets===true&&l.petsAllowed!==true)return false;if(children===true&&l.childrenAllowed===false)return false;if(roomOnly===true&&!l.roomOnly)return false;\n",
    "    if(yearMin!=null&&(l.buildingYear==null||l.buildingYear<yearMin))return false;if(yearMax!=null&&(l.buildingYear==null||l.buildingYear>yearMax))return false;if(newBuilding===true&&l.newBuilding!==true)return false;if(audience&&audience!=='any'&&l.audience!==audience)return false;if(pets===true&&l.petsAllowed!==true)return false;if(children===true&&l.childrenAllowed===false)return false;if(roomOnly===true&&!l.roomOnly)return false;\n    if(dishwasher===true&&l.dishwasher!==true)return false;if(airConditioner===true&&l.airConditioner!==true)return false;if(parking===true&&l.parking!==true)return false;if(internet===true&&l.internet!==true)return false;if(gas===true&&l.gas!==true)return false;if(balcony===true&&l.balcony!==true)return false;if(terrace===true&&l.terrace!==true)return false;if(privateYard===true&&l.privateYard!==true)return false;\n",
)

# server.js
replace_once("backend/src/server.js", "import {getRates} from './fx.js';\n", "import {getRates} from './fx.js';\nimport {sortListings} from './listing-sort.js';\n")
replace_once(
    "backend/src/server.js",
    "    newBuilding: bool(q.newBuilding),\n    city: q.city ? String(q.city) : '',\n",
    """    newBuilding: bool(q.newBuilding),\n    dishwasher: bool(q.dishwasher),\n    airConditioner: bool(q.airConditioner),\n    parking: bool(q.parking),\n    internet: bool(q.internet),\n    gas: bool(q.gas),\n    balcony: bool(q.balcony),\n    terrace: bool(q.terrace),\n    privateYard: bool(q.privateYard),\n    sort: ['newest', 'oldest', 'priceAsc', 'priceDesc', 'titleAsc', 'titleDesc'].includes(q.sort) ? q.sort : null,\n    city: q.city ? String(q.city) : '',\n""",
)
replace_once(
    "backend/src/server.js",
    "    const count =\n        listings.length;\n",
    "    if (filters.sort) sortListings(listings, filters.sort, fxRates);\n\n    const count =\n        listings.length;\n",
)

# coordinate validation wired into both ingestion paths
replace_once("backend/src/scrapers/index.js", "import {geocodeListings} from '../geocode.js';\n", "import {geocodeListings} from '../geocode.js';\nimport {rejectOutOfAreaCoordinates} from '../coordinate-validation.js';\n")
replace_once(
    "backend/src/scrapers/index.js",
    "    try {\n      await geocodeListings(\n          result.listings,\n          COUNTRIES[countryCode],\n      );\n",
    "    try {\n      await rejectOutOfAreaCoordinates(result.listings, COUNTRIES[countryCode]);\n      await geocodeListings(\n          result.listings,\n          COUNTRIES[countryCode],\n      );\n",
)
replace_once("backend/src/queueTasks.js", "import { executeQueueTaskOnce } from './queueTaskDedup.js';\n", "import { executeQueueTaskOnce } from './queueTaskDedup.js';\nimport { geocodeListings } from './geocode.js';\nimport { rejectOutOfAreaCoordinates } from './coordinate-validation.js';\n")
replace_once(
    "backend/src/queueTasks.js",
    "    const nextTask = nextOlxTask(task, pageResult, page);\n\n    return {\n",
    """    const rejected = await rejectOutOfAreaCoordinates(\n      pageResult.listings, COUNTRIES[country],\n      { areaHint: task.citySlug ? String(task.citySlug) : null },\n    );\n    if (rejected.length) await geocodeListings(rejected, COUNTRIES[country]);\n\n    const nextTask = nextOlxTask(task, pageResult, page);\n\n    return {\n""",
)

Path("backend/src/listing-sort.js").write_text("""import { toUsd } from './fx.js';\n\nfunction ts(v) { if (!v) return null; const n = Date.parse(v); return Number.isNaN(n) ? null : n; }\nfunction nullable(a, b, dir) {\n  const am = a == null || !Number.isFinite(a); const bm = b == null || !Number.isFinite(b);\n  if (am && bm) return 0; if (am) return 1; if (bm) return -1; return dir * (a - b);\n}\nfunction dateCmp(a, b, oldest = false) { return nullable(ts(a.createdAt), ts(b.createdAt), oldest ? 1 : -1); }\nfunction priceCmp(a, b, rates, asc) {\n  const p = nullable(toUsd(a.price, a.currency, rates), toUsd(b.price, b.currency, rates), asc ? 1 : -1);\n  return p || dateCmp(a, b);\n}\nfunction titleCmp(a, b, desc) {\n  const p = String(a.title || '').trim().localeCompare(String(b.title || '').trim(), ['ru', 'uk', 'en'], { sensitivity: 'base', numeric: true });\n  return (desc ? -p : p) || dateCmp(a, b);\n}\nexport function sortListings(listings, sort, rates = null) {\n  if (!Array.isArray(listings)) return listings;\n  if (sort === 'oldest') listings.sort((a,b) => dateCmp(a,b,true));\n  else if (sort === 'priceAsc') listings.sort((a,b) => priceCmp(a,b,rates,true));\n  else if (sort === 'priceDesc') listings.sort((a,b) => priceCmp(a,b,rates,false));\n  else if (sort === 'titleAsc') listings.sort((a,b) => titleCmp(a,b,false));\n  else if (sort === 'titleDesc') listings.sort((a,b) => titleCmp(a,b,true));\n  else listings.sort((a,b) => dateCmp(a,b,false));\n  return listings;\n}\n""")

Path("backend/src/coordinate-validation.js").write_text("""import { canonicalCityName } from './countries.js';\nimport { geocodeBbox } from './geocode.js';\n\nconst DEFAULT_PADDING_DEG = 0.02;\nconst bboxPromises = new Map();\n\nexport function coordinateInsideBbox(lat, lng, bbox, padding = DEFAULT_PADDING_DEG) {\n  if (!Number.isFinite(Number(lat)) || !Number.isFinite(Number(lng))) return false;\n  if (!Array.isArray(bbox) || bbox.length !== 4 || !bbox.every(Number.isFinite)) return true;\n  const [south, west, north, east] = bbox;\n  return Number(lat) >= south - padding && Number(lat) <= north + padding && Number(lng) >= west - padding && Number(lng) <= east + padding;\n}\n\nasync function bboxFor(country, area) {\n  const query = [area, country?.name].filter(Boolean).join(', ');\n  if (!query) return null;\n  const key = `${country?.code || ''}:${String(area).toLowerCase()}`;\n  if (!bboxPromises.has(key)) bboxPromises.set(key, geocodeBbox(query).catch(() => null));\n  return bboxPromises.get(key);\n}\n\nexport async function rejectOutOfAreaCoordinates(listings, country, { areaHint = null } = {}) {\n  if (!Array.isArray(listings) || !country) return [];\n  const configured = Number(process.env.SOURCE_COORD_BBOX_PADDING_DEG);\n  const padding = Number.isFinite(configured) && configured >= 0 ? configured : DEFAULT_PADDING_DEG;\n  const rejected = [];\n  for (const listing of listings) {\n    if (!Number.isFinite(Number(listing?.lat)) || !Number.isFinite(Number(listing?.lng))) continue;\n    const area = areaHint || canonicalCityName(country.code, listing.city || '');\n    if (!area) continue;\n    const bbox = await bboxFor(country, area);\n    if (!bbox || coordinateInsideBbox(listing.lat, listing.lng, bbox, padding)) continue;\n    listing.sourceCoordinateRejected = true;\n    listing.lat = null; listing.lng = null;\n    listing.district = null; listing.microdistrict = null;\n    listing.locationSource = 'source-coordinate-rejected'; listing.locationAccuracyM = null;\n    rejected.push(listing);\n  }\n  return rejected;\n}\n""")

Path("backend/test/map-amenity-sort.test.js").write_text("""import test from 'node:test';\nimport assert from 'node:assert/strict';\nimport { makeListing, applyFilters } from '../src/normalize.js';\nimport { coordinateInsideBbox } from '../src/coordinate-validation.js';\nimport { sortListings } from '../src/listing-sort.js';\n\ntest('bare street plus house number is retained as an address', () => {\n  const l = makeListing({ id:'a', source:'olx', country:'UA', title:'Аркадия', description:'Одесса, район Аркадии, Балтиморская 9, 160 кв.м' });\n  assert.equal(l.address, 'Балтиморская 9');\n});\n\ntest('requested quick amenities are normalized and filterable', () => {\n  const all = makeListing({ id:'all', source:'telegram', country:'UA', title:'Квартира', description:'Посудомоечная машина, кондиционер, своё парковочное место, Wi-Fi, газ, балкон, терраса, личный двор.' });\n  for (const k of ['dishwasher','airConditioner','parking','internet','gas','balcony','terrace','privateYard']) assert.equal(all[k], true, k);\n  const plain = makeListing({ id:'plain', source:'telegram', country:'UA', title:'Квартира', description:'Обычная квартира' });\n  const found = applyFilters([plain, all], { propertyType:'any', agency:'any', dealType:'any', audience:'any', dishwasher:true, airConditioner:true, parking:true, internet:true, gas:true, balcony:true, terrace:true, privateYard:true });\n  assert.deepEqual(found.map(x => x.id), ['all']);\n});\n\ntest('bbox guard rejects an offshore point', () => {\n  const bbox = [46.35, 30.60, 46.60, 30.85];\n  assert.equal(coordinateInsideBbox(46.46, 30.74, bbox, 0.02), true);\n  assert.equal(coordinateInsideBbox(46.20, 31.05, bbox, 0.02), false);\n});\n\ntest('sorting supports date, cross-currency price and alphabetic directions', () => {\n  const rows = [\n    {id:'b',title:'Бета',price:4150,currency:'UAH',createdAt:'2026-08-20T00:00:00Z'},\n    {id:'a',title:'Альфа',price:200,currency:'USD',createdAt:'2026-08-21T00:00:00Z'},\n    {id:'z',title:'Ялта',price:null,currency:'UAH',createdAt:'2026-08-19T00:00:00Z'},\n  ]; const rates={USD:1,UAH:41.5};\n  assert.deepEqual(sortListings([...rows],'newest',rates).map(x=>x.id), ['a','b','z']);\n  assert.deepEqual(sortListings([...rows],'oldest',rates).map(x=>x.id), ['z','b','a']);\n  assert.deepEqual(sortListings([...rows],'priceAsc',rates).map(x=>x.id), ['b','a','z']);\n  assert.deepEqual(sortListings([...rows],'priceDesc',rates).map(x=>x.id), ['a','b','z']);\n  assert.deepEqual(sortListings([...rows],'titleAsc',rates).map(x=>x.id), ['a','b','z']);\n  assert.deepEqual(sortListings([...rows],'titleDesc',rates).map(x=>x.id), ['z','b','a']);\n});\n""")

print('patch applied')
