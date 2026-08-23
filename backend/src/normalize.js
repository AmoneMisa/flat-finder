// A single normalized Listing shape that the Flutter app consumes.
import {extractTags} from './tags.js';
import {canonicalCityName} from './countries.js';
import {
  classifyChildren, classifyDealType, classifyPets, looksCommercial, looksRoomOnly,
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
import {parseDishwasher, parsePrivateYard, parseTerrace} from './amenity-parse.js';

function stripHtml(s) {
  return String(s ?? '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|h[1-6])>/gi, '\n')
    .replace(/<[^>]+>/g, '').replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&').replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>').replace(/&quot;/gi, '"').replace(/&#3[49];/g, "'").replace(/\u00a0/g, ' ')
    .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}

const PARKING_OBJECT_RE = /(?:парко?мест[а-яёіїґ]*|парковочн[а-яёіїґ]*\s+мест[а-яёіїґ]*|машино[-\s]?мест[а-яёіїґ]*|мест[а-яёіїґ]*\s+(?:в|на)\s+(?:паркинг[а-яёіїґ]*|парковк[а-яёіїґ]*)|parking\s+(?:space|spot)s?)/iu;
const HOUSING_OBJECT_RE = /(?:квартир[а-яёіїґ]*|апартамент[а-яёіїґ]*|студи[яії][а-яёіїґ]*|будин[а-яіїґ]*|(?:^|[^\p{L}\p{N}_])дом(?:а|ом|у|ов)?(?=$|[^\p{L}\p{N}_])|жиль[а-яё]*|житл[а-яіїґ]*|flat\b|apartment\b|studio\b|house\b|xonadon\b|kvartira\b)/iu;
const EXPLICIT_SHORT_STAY_RE = /(?:^|[^\p{L}\p{N}_])сут(?:ки|ок)(?=$|[^\p{L}\p{N}_])/iu;

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
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return {lat: null, lng: null, rejected: false};
  }
  const bounds = SOURCE_CITY_BOUNDS[`${String(partial.country || '').toUpperCase()}:${city}`];
  if (!bounds) return {lat, lng, rejected: false};
  const [south, west, north, east] = bounds;
  const rejected = lat < south || lat > north || lng < west || lng > east;
  return rejected
    ? {lat: null, lng: null, rejected: true}
    : {lat, lng, rejected: false};
}

export function makeListing(partial) {
  const sourceTitle = partial.title ?? '';
  const description = stripHtml(partial.description ?? '');
  const combined = `${sourceTitle} ${description}`;
  const propertyType = partial.propertyType === 'house' ? 'house' : 'flat';
  const byAgency = Boolean(partial.byAgency);
  const rooms = partial.rooms != null ? Number(partial.rooms) : parseRoomsFromText(combined);
  const parsedDealType = classifyDealType(combined);
  const explicitShortStay = parsedDealType === 'shortRent' || EXPLICIT_SHORT_STAY_RE.test(combined);

  // Explicit short-term language ("сутки", "посуточно", "daily", etc.) is
  // stronger than a scraper's generic `longRent` default. Keep an explicit sale
  // authoritative because sale copy may advertise potential daily-rental income.
  let dealType = partial.dealType === 'sale'
    ? 'sale'
    : explicitShortStay
      ? 'shortRent'
      : (partial.dealType ?? parsedDealType);

  const SALE_FLOOR = {
    USD: 10000,
    EUR: 10000,
    GBP: 10000,
    UYE: 10000,
    UZS: 100_000_000,
    KZT: 5_000_000,
    UAH: 500_000,
    RON: 50_000,
    KGS: 800_000,
    TJS: 90_000,
    RUB: 700_000,
  };
  if (
    partial.dealType == null &&
    dealType !== 'sale' &&
    dealType !== 'shortRent' &&
    partial.price != null
  ) {
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
  const district = canonicalDistrict(
    (coords.rejected ? null : partial.district) ?? explicitDistrict ?? loc.district,
    partial.country,
  );
  const metro = partial.metro ?? loc.metro;
  const nearby = partial.nearby
    ?? [...new Set([...(loc.nearby || []), ...parseNearbyPlaces(combined)])];
  const residenceComplex = partial.residenceComplex
    ?? parseResidentialComplex(combined)
    ?? loc.residentialComplex;
  const address = partial.address ?? parseAddress(combined);
  const commercial = partial.commercial === true || looksCommercial(combined) || looksParkingOnly(combined);
  const petsAllowed = partial.petsAllowed ?? classifyPets(combined);
  const childrenAllowed = partial.childrenAllowed ?? classifyChildren(combined);
  const roomOnly = partial.roomOnly ?? looksRoomOnly(combined);

  const dep = parseDeposit(combined);
  const deposit = partial.deposit ?? dep.required;
  const depositAmount = partial.depositAmount ?? dep.amount;
  const depositCurrency = partial.depositCurrency ?? dep.currency ?? null;

  const com = parseCommission(combined);
  const commission = partial.commission ?? com.has;
  const commissionPercent = partial.commissionPercent ?? com.percent;

  const balcony = partial.balcony ?? parseBalcony(combined);
  const terrace = partial.terrace ?? parseTerrace(combined);
  const privateYard = partial.privateYard ?? parsePrivateYard(combined);
  const dishwasher = partial.dishwasher ?? parseDishwasher(combined);
  const airConditioner = partial.airConditioner ?? parseAirConditioner(combined);
  const gas = partial.gas ?? parseGasSupply(combined);
  const bathrooms = partial.bathrooms != null ? Number(partial.bathrooms) : parseBathrooms(combined);
  const newBuilding = partial.newBuilding
    ?? (parseNewBuilding(combined) || (buildingYear && buildingYear >= new Date().getFullYear() - 5 ? true : null));
  const communalSeparated = partial.communalSeparated ?? parseCommunalSeparated(combined);
  const parsedKvartal = parseKvartal(combined);
  const area = partial.area ?? loc.area ?? partial.kvartal ?? parsedKvartal;
  const kvartal = partial.kvartal ?? area;
  const nearbyShops = partial.nearbyShops ?? parseNearbyShops(combined);
  const amenities = Array.isArray(partial.amenities) ? partial.amenities : parseAmenities(combined);
  const parking = partial.parking ?? parseParking(combined);
  const elevator = partial.elevator ?? parseElevator(combined);
  const heating = partial.heating ?? parseHeating(combined);
  const hotWater = partial.hotWater ?? parseHotWater(combined);
  const internet = partial.internet ?? parseInternet(combined);
  const smokingAllowed = partial.smokingAllowed ?? parseSmoking(combined);
  const negotiable = partial.negotiable ?? parseNegotiable(combined);
  const furnished = partial.furnished ?? parseFurnished(combined);
  const title = normalizeListingTitle(sourceTitle, {
    propertyType,
    rooms,
    residenceComplex,
    address,
    city,
  });

  return {
    id: String(partial.id),
    source: partial.source,
    country: partial.country,
    title,
    propertyType,
    byAgency,
    price: partial.price != null ? Number(partial.price) : null,
    currency: partial.currency ?? '',
    rooms,
    areaSqm: partial.areaSqm != null ? Number(partial.areaSqm) : parseAreaFromText(combined),
    city,
    region: partial.region ?? loc.region ?? null,
    microdistrict: coords.rejected ? null : (partial.microdistrict ?? loc.microdistrict ?? null),
    address: address || null,
    lat: coords.lat,
    lng: coords.lng,
    sourceCoordinateRejected: coords.rejected || partial.sourceCoordinateRejected === true,
    photo: partial.photo ?? (Array.isArray(partial.photos) ? partial.photos[0] : null) ?? null,
    photos: Array.isArray(partial.photos) ? partial.photos : (partial.photo ? [partial.photo] : []),
    url: partial.url ?? '',
    createdAt: partial.createdAt ?? null,
    description,
    dealType,
    floor,
    totalFloors,
    buildingYear,
    bedrooms,
    audience,
    contact,
    district,
    area,
    areaAmbiguous: partial.areaAmbiguous ?? loc.areaAmbiguous ?? false,
    locationConfidence: partial.locationConfidence ?? loc.locationConfidence ?? null,
    requireExactAddress: partial.requireExactAddress ?? loc.requireExactAddress ?? false,
    metro,
    nearby,
    residenceComplex,
    commercial,
    petsAllowed,
    childrenAllowed,
    roomOnly,
    deposit,
    depositAmount,
    depositCurrency,
    commission,
    commissionPercent,
    balcony,
    terrace,
    privateYard,
    dishwasher,
    airConditioner,
    gas,
    bathrooms,
    newBuilding,
    communalSeparated,
    kvartal,
    nearbyShops,
    parking,
    elevator,
    heating,
    hotWater,
    internet,
    smokingAllowed,
    negotiable,
    furnished,
    condition: partial.condition ?? null,
    amenities,
    tags: partial.tags ?? extractTags({
      title,
      description,
      propertyType,
      byAgency,
      rooms,
      dealType,
      audience,
      district,
      nearby,
      residenceComplex,
      petsAllowed,
      childrenAllowed,
      roomOnly,
      deposit,
      commission,
      commissionPercent,
    }),
  };
}
