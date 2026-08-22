// A single normalized Listing shape that the Flutter app consumes.
import {extractTags} from './tags.js';
import {canonicalCityName} from './countries.js';
import {
  classifyChildren, classifyDealType, classifyPets, looksCommercial, looksHousingWanted, looksRoomOnly,
  parseAirConditioner, parseAmenities, parseAreaFromText, parseBalcony, parseBathrooms, parseBedrooms,
  parseCommunalSeparated, parseContact, parseDeposit, parseElevator, parseFurnished, parseGasSupply,
  parseHeating, parseHotWater, parseInternet, parseKvartal, parseNearbyShops, parseNearbyPlaces, parseNegotiable,
  parseNewBuilding, parseParking, parseSmoking, parseYear,
} from './textparse.js';
import {
  classifyAudience, parseCommission, parseExplicitDistrict, parseFloor, parseResidentialComplex,
  parseRoomsFromText,
} from './textparse-overrides.js';
import {canonicalDistrict, parseLocation} from './locations.js';
import {toUsd} from './fx.js';
import {parseDishwasher, parsePrivateYard, parseTerrace} from './amenity-parse.js';

function stripHtml(s) {
  return String(s ?? '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|h[1-6])>/gi, '\n')
    .replace(/<[^>]+>/g, '').replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&').replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>').replace(/&quot;/gi, '"').replace(/&#3[49];/g, "'").replace(/\u00a0/g, ' ')
    .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}

const PARKING_OBJECT_RE = /(?:парко?мест[а-яёіїґ]*|парковочн[а-яёіїґ]*\s+мест[а-яёіїґ]*|машино[-\s]?мест[а-яёіїґ]*|мест[а-яёіїґ]*\s+(?:в|на)\s+(?:паркинг[а-яёіїґ]*|парковк[а-яёіїґ]*)|parking\s+(?:space|spot)s?)/iu;
const HOUSING_OBJECT_RE = /(?:квартир[а-яёіїґ]*|апартамент[а-яёіїґ]*|студи[яії][а-яёіїґ]*|будин[а-яіїґ]*|(?:^|[^\p{L}\p{N}_])дом(?:а|ом|у|ов)?(?=$|[^\p{L}\p{N}_])|жиль[а-яё]*|житл[а-яіїґ]*|flat\b|apartment\b|studio\b|house\b|xonadon\b|kvartira\b)/iu;

export function looksParkingOnly(text) {
  const value = String(text || '').replace(/\s+/g, ' ').trim();
  if (!value || !PARKING_OBJECT_RE.test(value)) return false;
  return !HOUSING_OBJECT_RE.test(value);
}

function normalizeListingTitle(value, {propertyType, rooms, residenceComplex, address, city}) {
  const cleaned = stripHtml(value ?? '')
    .replace(/\s+/g, ' ')
    .replace(/^[^\p{L}\p{N}]+/u, '')
    .trim();
  const letters = (cleaned.match(/\p{L}/gu) || []).length;
  const meaningful = cleaned && letters >= 3 && cleaned.length <= 90;
  if (meaningful) return cleaned;

  const noun = propertyType === 'house' ? 'Дом' : 'Квартира';
  const base = rooms != null && Number.isFinite(Number(rooms)) && Number(rooms) >= 1 && Number(rooms) <= 10
    ? `${Number(rooms)}-комнатная ${noun.toLowerCase()}`
    : noun;
  const place = residenceComplex || address || city;
  return place ? `${base} · ${place}` : base;
}

function parseAddress(text) {
  if (!text) return null;
  const labeled = text.match(/(?:адрес|адреса|manzil|address)\s*[:\-–]\s*([^\n]{3,80})/i);
  if (labeled) return labeled[1].replace(/\s+/g, ' ').trim().replace(/[.;,]+$/, '');
  const street = text.match(/((?:ул(?:иц[аы])?|просп(?:ект)?|проспект|мкр|микрорайон|проезд|переулок)\.?\s+[^\n,.;]{2,40}(?:,?\s*\d+[\w/-]*)?|[^\n,.;]{2,40}\s+(?:ko['’]?chasi|k[oó]chasi))/i);
  if (street) return street[1].replace(/\s+/g, ' ').trim();

  // OLX descriptions often omit the street prefix: "..., Балтиморская 9, ...".
  // Require a word-like street name plus a house number in a delimited segment
  // so area/price/floor numbers are not accidentally promoted to addresses.
  const bare = text.match(/(?:^|[,;\n]\s*)([\p{L}][\p{L}'’.-]*(?:\s+[\p{L}][\p{L}'’.-]*){0,4}\s+\d+[\p{L}0-9/-]*)(?=\s*(?:[,.;\n]|$))/iu);
  return bare ? bare[1].replace(/\s+/g, ' ').trim() : null;
}

// Cheap synchronous guard for the concrete production failure that prompted
// the general asynchronous bbox validator. It also protects the legacy cached
// scraper path before its final geocoding pass. Bounds are intentionally broad
// enough for all of Odesa proper, including the northern residential districts.
const SOURCE_CITY_BOUNDS = {
  'UA:Odesa': [46.25, 30.45, 46.65, 30.88], // south, west, north, east
};
function sourceCoordinates(partial, city) {
  const lat = partial.lat != null ? Number(partial.lat) : null;
  const lng = partial.lng != null ? Number(partial.lng) : null;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return {lat:null,lng:null,rejected:false};
  const bounds = SOURCE_CITY_BOUNDS[`${String(partial.country || '').toUpperCase()}:${city}`];
  if (!bounds) return {lat,lng,rejected:false};
  const [south, west, north, east] = bounds;
  const rejected = lat < south || lat > north || lng < west || lng > east;
  return rejected ? {lat:null,lng:null,rejected:true} : {lat,lng,rejected:false};
}

export function makeListing(partial) {
  const sourceTitle = partial.title ?? '';
  const description = stripHtml(partial.description ?? '');
  const combined = `${sourceTitle} ${description}`;
  const propertyType = partial.propertyType === 'house' ? 'house' : 'flat';
  const byAgency = Boolean(partial.byAgency);
  const rooms = partial.rooms != null ? Number(partial.rooms) : parseRoomsFromText(combined);
  const parsedDealType = classifyDealType(combined);
  // Explicit short-term language ("сутки", "посуточно", "daily", etc.) is
  // stronger than a scraper's generic `longRent` default. Keep an explicit sale
  // authoritative because sale copy may advertise potential daily-rental income.
  let dealType = partial.dealType === 'sale'
    ? 'sale'
    : parsedDealType === 'shortRent'
      ? 'shortRent'
      : (partial.dealType ?? parsedDealType);
  const SALE_FLOOR = {USD:10000,EUR:10000,GBP:10000,UYE:10000,UZS:100_000_000,KZT:5_000_000,UAH:500_000,RON:50_000,KGS:800_000,TJS:90_000,RUB:700_000};
  if (partial.dealType == null && dealType !== 'sale' && dealType !== 'shortRent' && partial.price != null) {
    const floor = SALE_FLOOR[String(partial.currency ?? '').toUpperCase()];
    if (floor && Number(partial.price) >= floor) dealType = 'sale';
  }
  const parsedFloor = parseFloor(combined);
  const floor = partial.floor != null ? Number(partial.floor) : parsedFloor.floor;
  const totalFloors = partial.totalFloors != null ? Number(partial.totalFloors) : parsedFloor.totalFloors;
  const buildingYear = partial.buildingYear != null ? Number(partial.buildingYear) : parseYear(combined);
  const bedrooms = partial.bedrooms != null ? Number(partial.bedrooms) : parseBedrooms(combined);
  const audience = partial.audience ?? classifyAudience(combined);
  const contact = partial.contact ?? parseContact(combined);
  const loc = parseLocation(combined, partial.country);
  const city = canonicalCityName(partial.country, partial.city || loc.city || '');
  const coords = sourceCoordinates(partial, city);
  const explicitDistrict = parseExplicitDistrict(combined, partial.country);
  const district = canonicalDistrict((coords.rejected ? null : partial.district) ?? explicitDistrict ?? loc.district, partial.country);
  const metro = partial.metro ?? loc.metro;
  // Dictionary landmarks (LOCATIONS) plus open-ended local ones written in the
  // post itself ("рынок Катартал", "ЗАГС Чиланзарского района").
  const nearby = partial.nearby
    ?? [...new Set([...(loc.nearby || []), ...parseNearbyPlaces(combined)])];
  // Explicit source value > labelled free-text parser > curated dictionary.
  const residenceComplex = partial.residenceComplex ?? parseResidentialComplex(combined) ?? loc.residentialComplex;
  const address = partial.address ?? parseAddress(combined);
  // Parking-space adverts are inventory, not housing. A normal apartment that
  // merely mentions its parking amenity is protected by looksParkingOnly().
  const commercial = partial.commercial === true || looksCommercial(combined) || looksParkingOnly(combined);
  const petsAllowed = partial.petsAllowed ?? classifyPets(combined);
  const childrenAllowed = partial.childrenAllowed ?? classifyChildren(combined);
  const roomOnly = partial.roomOnly ?? looksRoomOnly(combined);
  const dep = parseDeposit(combined); const deposit = partial.deposit ?? dep.required; const depositAmount = partial.depositAmount ?? dep.amount;
  // The deposit is frequently quoted in another currency than the rent
  // ("Депозит 1000USD" on a UZS listing), so carry its own currency when stated.
  const depositCurrency = partial.depositCurrency ?? dep.currency ?? null;
  const com = parseCommission(combined); const commission = partial.commission ?? com.has; const commissionPercent = partial.commissionPercent ?? com.percent;
  const balcony = partial.balcony ?? parseBalcony(combined);
  const terrace = partial.terrace ?? parseTerrace(combined);
  const privateYard = partial.privateYard ?? parsePrivateYard(combined);
  const dishwasher = partial.dishwasher ?? parseDishwasher(combined);
  const airConditioner = partial.airConditioner ?? parseAirConditioner(combined);
  const gas = partial.gas ?? parseGasSupply(combined); const bathrooms = partial.bathrooms != null ? Number(partial.bathrooms) : parseBathrooms(combined);
  const newBuilding = partial.newBuilding ?? (parseNewBuilding(combined) || (buildingYear && buildingYear >= new Date().getFullYear()-5 ? true : null));
  const communalSeparated = partial.communalSeparated ?? parseCommunalSeparated(combined);
  const parsedKvartal = parseKvartal(combined); const area = partial.area ?? loc.area ?? partial.kvartal ?? parsedKvartal; const kvartal = partial.kvartal ?? area;
  const nearbyShops = partial.nearbyShops ?? parseNearbyShops(combined); const amenities = Array.isArray(partial.amenities) ? partial.amenities : parseAmenities(combined);
  const parking = partial.parking ?? parseParking(combined); const elevator = partial.elevator ?? parseElevator(combined); const heating = partial.heating ?? parseHeating(combined);
  const hotWater = partial.hotWater ?? parseHotWater(combined); const internet = partial.internet ?? parseInternet(combined); const smokingAllowed = partial.smokingAllowed ?? parseSmoking(combined);
  const negotiable = partial.negotiable ?? parseNegotiable(combined); const furnished = partial.furnished ?? parseFurnished(combined);
  const title = normalizeListingTitle(sourceTitle, {propertyType, rooms, residenceComplex, address, city});
  return {
    id:String(partial.id), source:partial.source, country:partial.country, title, propertyType, byAgency,
    price:partial.price != null ? Number(partial.price):null, currency:partial.currency ?? '', rooms,
    areaSqm:partial.areaSqm != null ? Number(partial.areaSqm):parseAreaFromText(combined), city,
    region:partial.region ?? loc.region ?? null, microdistrict:coords.rejected ? null : (partial.microdistrict ?? loc.microdistrict ?? null),
    address:address || null, lat:coords.lat, lng:coords.lng, sourceCoordinateRejected:coords.rejected || partial.sourceCoordinateRejected === true,
    photo:partial.photo ?? (Array.isArray(partial.photos)?partial.photos[0]:null) ?? null,
    photos:Array.isArray(partial.photos)?partial.photos:(partial.photo?[partial.photo]:[]), url:partial.url ?? '', createdAt:partial.createdAt ?? null,
    description, dealType, floor, totalFloors, buildingYear, bedrooms, audience, contact, district, area,
    areaAmbiguous:partial.areaAmbiguous ?? loc.areaAmbiguous ?? false, locationConfidence:partial.locationConfidence ?? loc.locationConfidence ?? null,
    requireExactAddress:partial.requireExactAddress ?? loc.requireExactAddress ?? false, metro, nearby, residenceComplex,
    commercial, petsAllowed, childrenAllowed, roomOnly, deposit, depositAmount, depositCurrency, commission, commissionPercent,
    balcony, terrace, privateYard, dishwasher, airConditioner, gas, bathrooms, newBuilding, communalSeparated, kvartal,
    nearbyShops, parking, elevator, heating, hotWater, internet, smokingAllowed, negotiable, furnished,
    condition:partial.condition ?? null, amenities,
    tags:partial.tags ?? extractTags({title,description,propertyType,byAgency,rooms,dealType,audience,district,nearby,residenceComplex,petsAllowed,childrenAllowed,roomOnly,deposit,commission,commissionPercent}),
  };
}
export const MAX_AGE_MS = 21*24*60*60*1000;
function normCity(s){return String(s??'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');}
export function applyFilters(listings, filters, rates=null){
  const {propertyType,agency,priceMin,priceMax,priceTolerance,priceCurrency,query,dealType,roomsMin,roomsMax,bedroomsMin,bedroomsMax,areaMin,areaMax,pricePerSqmMin,pricePerSqmMax,floorMin,floorMax,totalFloorsMin,totalFloorsMax,yearMin,yearMax,newBuilding,audience,city,cityAliases,district,metro,metroMaxM,nearbyMaxM,nearbyKind,listingId,pets,children,roomOnly,dishwasher,airConditioner,parking,internet,gas,balcony,terrace,privateYard,maxAgeDays,sources}=filters;
  const convertPrices=!!(rates&&priceCurrency); const now=Date.now(); const ageCapMs=maxAgeDays!=null&&maxAgeDays>0?Math.min(maxAgeDays*24*60*60*1000,MAX_AGE_MS):MAX_AGE_MS;
  const cityForms=city?(cityAliases?.length?cityAliases:[city]).map(normCity):null;
  return listings.filter((l)=>{
    if(listingId&&String(l.id)!==String(listingId))return false; if(sources?.length&&!sources.includes(String(l.source).toLowerCase()))return false;
    if(String(l.source).toLowerCase()==='telegram'){const listingText=[l.title,l.description].filter(Boolean).join('\n');if(looksHousingWanted(listingText))return false;}
    // Flat Finder intentionally contains residential sale/long-term inventory.
    // Short-stay apartments and parking-space inventory are noise here.
    if(l.dealType==='shortRent')return false;
    if(l.commercial)return false; if(l.createdAt){const t=Date.parse(l.createdAt);if(!Number.isNaN(t)&&now-t>ageCapMs)return false;}
    if(propertyType&&propertyType!=='any'&&l.propertyType!==propertyType)return false; if(dealType&&dealType!=='any'&&l.dealType!==dealType)return false;
    if(agency==='agency'&&!l.byAgency)return false;if(agency==='owner'&&l.byAgency)return false;const effMax=priceMax!=null?priceMax+(priceTolerance??0):null;
    if(priceMin!=null||effMax!=null){if(convertPrices){const p=toUsd(l.price,l.currency,rates);if(p==null)return false;if(priceMin!=null){const m=toUsd(priceMin,priceCurrency,rates);if(m!=null&&p<m)return false;}if(effMax!=null){const m=toUsd(effMax,priceCurrency,rates);if(m!=null&&p>m)return false;}}else{if(priceMin!=null&&(l.price==null||l.price<priceMin))return false;if(effMax!=null&&(l.price==null||l.price>effMax))return false;}}
    if(roomsMin!=null&&(l.rooms==null||l.rooms<roomsMin))return false;if(roomsMax!=null&&(l.rooms==null||l.rooms>roomsMax))return false;if(bedroomsMin!=null&&(l.bedrooms==null||l.bedrooms<bedroomsMin))return false;if(bedroomsMax!=null&&(l.bedrooms==null||l.bedrooms>bedroomsMax))return false;
    if(areaMin!=null&&(l.areaSqm==null||l.areaSqm<areaMin))return false;if(areaMax!=null&&(l.areaSqm==null||l.areaSqm>areaMax))return false;
    // Price per m2. Needs both a price and a usable area, so listings missing
    // either drop out — same rule the other numeric ranges already follow.
    if(pricePerSqmMin!=null||pricePerSqmMax!=null){const a=l.areaSqm;if(a==null||!(a>0))return false;if(convertPrices){const p=toUsd(l.price,l.currency,rates);if(p==null)return false;const per=p/a;if(pricePerSqmMin!=null){const m=toUsd(pricePerSqmMin,priceCurrency,rates);if(m!=null&&per<m)return false;}if(pricePerSqmMax!=null){const m=toUsd(pricePerSqmMax,priceCurrency,rates);if(m!=null&&per>m)return false;}}else{if(l.price==null)return false;const per=l.price/a;if(pricePerSqmMin!=null&&per<pricePerSqmMin)return false;if(pricePerSqmMax!=null&&per>pricePerSqmMax)return false;}}if(floorMin!=null&&(l.floor==null||l.floor<floorMin))return false;if(floorMax!=null&&(l.floor==null||l.floor>floorMax))return false;if(totalFloorsMin!=null&&(l.totalFloors==null||l.totalFloors<totalFloorsMin))return false;if(totalFloorsMax!=null&&(l.totalFloors==null||l.totalFloors>totalFloorsMax))return false;
    if(yearMin!=null&&(l.buildingYear==null||l.buildingYear<yearMin))return false;if(yearMax!=null&&(l.buildingYear==null||l.buildingYear>yearMax))return false;if(newBuilding===true&&l.newBuilding!==true)return false;if(audience&&audience!=='any'&&l.audience!==audience)return false;if(pets===true&&l.petsAllowed!==true)return false;if(children===true&&l.childrenAllowed===false)return false;if(roomOnly===true&&!l.roomOnly)return false;
    if(dishwasher===true&&l.dishwasher!==true)return false;if(airConditioner===true&&l.airConditioner!==true)return false;if(parking===true&&l.parking!==true)return false;if(internet===true&&l.internet!==true)return false;if(gas===true&&l.gas!==true)return false;if(balcony===true&&l.balcony!==true)return false;if(terrace===true&&l.terrace!==true)return false;if(privateYard===true&&l.privateYard!==true)return false;
    if(cityForms){const hay=normCity(l.city);if(!cityForms.some((f)=>hay.includes(f)))return false;}if(district&&(l.district??'').toLowerCase()!==String(district).toLowerCase())return false;if(metro&&(l.metro??'').toLowerCase()!==String(metro).toLowerCase())return false;
    // Walking distance filters. A listing with no measured distance cannot
    // satisfy "within 300 m", so it drops out the way every other numeric
    // range here treats a missing value.
    if(metroMaxM!=null){const d=l.metroDistanceM??(l.metroNearby??[])[0]?.distanceM;if(d==null||d>metroMaxM)return false;}
    if(nearbyKind||nearbyMaxM!=null){
      const places=(l.nearbyPlaces??[]).filter((p)=>!nearbyKind||String(p.kind).toLowerCase()===nearbyKind);
      if(!places.length)return false;
      if(nearbyMaxM!=null&&!places.some((p)=>p.distanceM!=null&&p.distanceM<=nearbyMaxM))return false;
    }
    if(query){const hay=[l.title,l.description,l.city,l.region,l.district,l.microdistrict,l.metro,l.residenceComplex,...(l.tags??[])].filter(Boolean).join(' ').toLowerCase();if(!hay.includes(String(query).toLowerCase()))return false;}return true;
  });
}
