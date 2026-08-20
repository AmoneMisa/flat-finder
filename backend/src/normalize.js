// A single normalized Listing shape that the Flutter app consumes.
import {extractTags} from './tags.js';
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

function stripHtml(s) {
  return String(s ?? '').replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|li|h[1-6])>/gi, '\n')
    .replace(/<[^>]+>/g, '').replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&').replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>').replace(/&quot;/gi, '"').replace(/&#3[49];/g, "'").replace(/\u00a0/g, ' ')
    .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}
function parseAddress(text) {
  if (!text) return null;
  const labeled = text.match(/(?:адрес|адреса|manzil|address)\s*[:\-–]\s*([^\n]{3,80})/i);
  if (labeled) return labeled[1].replace(/\s+/g, ' ').trim().replace(/[.;,]+$/, '');
  const street = text.match(/((?:ул(?:иц[аы])?|просп(?:ект)?|проспект|мкр|микрорайон|проезд|переулок)\.?\s+[^\n,.;]{2,40}(?:,?\s*\d+[\w/-]*)?|[^\n,.;]{2,40}\s+(?:ko['’]?chasi|k[oó]chasi))/i);
  return street ? street[1].replace(/\s+/g, ' ').trim() : null;
}

export function makeListing(partial) {
  const title = partial.title ?? 'Untitled';
  const description = stripHtml(partial.description ?? '');
  const combined = `${title} ${description}`;
  const propertyType = partial.propertyType === 'house' ? 'house' : 'flat';
  const byAgency = Boolean(partial.byAgency);
  const rooms = partial.rooms != null ? Number(partial.rooms) : parseRoomsFromText(combined);
  let dealType = partial.dealType ?? classifyDealType(combined);
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
  const explicitDistrict = parseExplicitDistrict(combined, partial.country);
  const district = canonicalDistrict(partial.district ?? explicitDistrict ?? loc.district, partial.country);
  const metro = partial.metro ?? loc.metro;
  // Dictionary landmarks (LOCATIONS) plus open-ended local ones written in the
  // post itself ("рынок Катартал", "ЗАГС Чиланзарского района").
  const nearby = partial.nearby
    ?? [...new Set([...(loc.nearby || []), ...parseNearbyPlaces(combined)])];
  // Explicit source value > labelled free-text parser > curated dictionary.
  const residenceComplex = partial.residenceComplex ?? parseResidentialComplex(combined) ?? loc.residentialComplex;
  const address = partial.address ?? parseAddress(combined);
  const commercial = partial.commercial ?? looksCommercial(combined);
  const petsAllowed = partial.petsAllowed ?? classifyPets(combined);
  const childrenAllowed = partial.childrenAllowed ?? classifyChildren(combined);
  const roomOnly = partial.roomOnly ?? looksRoomOnly(combined);
  const dep = parseDeposit(combined); const deposit = partial.deposit ?? dep.required; const depositAmount = partial.depositAmount ?? dep.amount;
  // The deposit is frequently quoted in another currency than the rent
  // ("Депозит 1000USD" on a UZS listing), so carry its own currency when stated.
  const depositCurrency = partial.depositCurrency ?? dep.currency ?? null;
  const com = parseCommission(combined); const commission = partial.commission ?? com.has; const commissionPercent = partial.commissionPercent ?? com.percent;
  const balcony = partial.balcony ?? parseBalcony(combined); const airConditioner = partial.airConditioner ?? parseAirConditioner(combined);
  const gas = partial.gas ?? parseGasSupply(combined); const bathrooms = partial.bathrooms != null ? Number(partial.bathrooms) : parseBathrooms(combined);
  const newBuilding = partial.newBuilding ?? (parseNewBuilding(combined) || (buildingYear && buildingYear >= new Date().getFullYear()-5 ? true : null));
  const communalSeparated = partial.communalSeparated ?? parseCommunalSeparated(combined);
  const parsedKvartal = parseKvartal(combined); const area = partial.area ?? loc.area ?? partial.kvartal ?? parsedKvartal; const kvartal = partial.kvartal ?? area;
  const nearbyShops = partial.nearbyShops ?? parseNearbyShops(combined); const amenities = Array.isArray(partial.amenities) ? partial.amenities : parseAmenities(combined);
  const parking = partial.parking ?? parseParking(combined); const elevator = partial.elevator ?? parseElevator(combined); const heating = partial.heating ?? parseHeating(combined);
  const hotWater = partial.hotWater ?? parseHotWater(combined); const internet = partial.internet ?? parseInternet(combined); const smokingAllowed = partial.smokingAllowed ?? parseSmoking(combined);
  const negotiable = partial.negotiable ?? parseNegotiable(combined); const furnished = partial.furnished ?? parseFurnished(combined);
  return {
    id:String(partial.id), source:partial.source, country:partial.country, title, propertyType, byAgency,
    price:partial.price != null ? Number(partial.price):null, currency:partial.currency ?? '', rooms,
    areaSqm:partial.areaSqm != null ? Number(partial.areaSqm):parseAreaFromText(combined), city:partial.city || loc.city || '',
    region:partial.region ?? loc.region ?? null, microdistrict:partial.microdistrict ?? loc.microdistrict ?? null,
    address:address || null, lat:partial.lat != null?Number(partial.lat):null, lng:partial.lng != null?Number(partial.lng):null,
    photo:partial.photo ?? (Array.isArray(partial.photos)?partial.photos[0]:null) ?? null,
    photos:Array.isArray(partial.photos)?partial.photos:(partial.photo?[partial.photo]:[]), url:partial.url ?? '', createdAt:partial.createdAt ?? null,
    description, dealType, floor, totalFloors, buildingYear, bedrooms, audience, contact, district, area,
    areaAmbiguous:partial.areaAmbiguous ?? loc.areaAmbiguous ?? false, locationConfidence:partial.locationConfidence ?? loc.locationConfidence ?? null,
    requireExactAddress:partial.requireExactAddress ?? loc.requireExactAddress ?? false, metro, nearby, residenceComplex,
    commercial, petsAllowed, childrenAllowed, roomOnly, deposit, depositAmount, depositCurrency, commission, commissionPercent, balcony,
    airConditioner, gas, bathrooms, newBuilding, communalSeparated, kvartal, nearbyShops, parking, elevator, heating,
    hotWater, internet, smokingAllowed, negotiable, furnished, condition:partial.condition ?? null, amenities,
    tags:partial.tags ?? extractTags({title,description,propertyType,byAgency,rooms,dealType,audience,district,nearby,residenceComplex,petsAllowed,childrenAllowed,roomOnly,deposit,commission,commissionPercent}),
  };
}
export const MAX_AGE_MS = 21*24*60*60*1000;
function normCity(s){return String(s??'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');}
export function applyFilters(listings, filters, rates=null){
  const {propertyType,agency,priceMin,priceMax,priceTolerance,priceCurrency,query,dealType,roomsMin,roomsMax,bedroomsMin,bedroomsMax,areaMin,areaMax,pricePerSqmMin,pricePerSqmMax,floorMin,floorMax,totalFloorsMin,totalFloorsMax,yearMin,yearMax,newBuilding,audience,city,cityAliases,district,metro,listingId,pets,children,roomOnly,maxAgeDays,sources}=filters;
  const convertPrices=!!(rates&&priceCurrency); const now=Date.now(); const ageCapMs=maxAgeDays!=null&&maxAgeDays>0?Math.min(maxAgeDays*24*60*60*1000,MAX_AGE_MS):MAX_AGE_MS;
  const cityForms=city?(cityAliases?.length?cityAliases:[city]).map(normCity):null;
  return listings.filter((l)=>{
    if(listingId&&String(l.id)!==String(listingId))return false; if(sources?.length&&!sources.includes(String(l.source).toLowerCase()))return false;
    if(String(l.source).toLowerCase()==='telegram'){const listingText=[l.title,l.description].filter(Boolean).join('\n');if(looksHousingWanted(listingText))return false;}
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
    if(cityForms){const hay=normCity(l.city);if(!cityForms.some((f)=>hay.includes(f)))return false;}if(district&&(l.district??'').toLowerCase()!==String(district).toLowerCase())return false;if(metro&&(l.metro??'').toLowerCase()!==String(metro).toLowerCase())return false;
    if(query){const hay=[l.title,l.description,l.city,l.region,l.district,l.microdistrict,l.metro,l.residenceComplex,...(l.tags??[])].filter(Boolean).join(' ').toLowerCase();if(!hay.includes(String(query).toLowerCase()))return false;}return true;
  });
}
