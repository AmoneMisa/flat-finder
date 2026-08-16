// A single normalized Listing shape that the Flutter app consumes, regardless
// of which source (OLX, Reddit, Telegram, Threads, mock) produced it.
//
// {
//   id, source, country, title, propertyType, byAgency, price, currency,
//   rooms, areaSqm, city, lat, lng, photo, url, createdAt,
//   description: string,        // free text used for tag extraction
//   dealType: 'sale'|'longRent'|'shortRent'|null,
//   floor, totalFloors, buildingYear, bedrooms: number|null,
//   furnished: boolean|null, condition: string|null, amenities: string[],
//   audience: 'women'|'men'|'family'|null,   // stated tenant restriction
//   contact: string|null,       // phone or @handle pulled from the post
//   tags: string[],             // derived card tags
// }

import { extractTags } from './tags.js';
import {
  classifyDealType,
  parseFloor,
  parseYear,
  parseBedrooms,
  classifyAudience,
  parseContact,
  looksCommercial,
  parseResidentialComplex,
  classifyPets,
  classifyChildren,
  looksRoomOnly,
  parseDeposit,
  parseCommission,
  parseBalcony,
  parseAirConditioner,
  parseGasSupply,
  parseNewBuilding,
  parseBathrooms,
  parseCommunalSeparated,
  parseKvartal,
  parseNearbyShops,
  parseRoomsFromText,
  parseAreaFromText,
} from './textparse.js';
import { parseLocation, canonicalDistrict } from './locations.js';
import { toUsd } from './fx.js';

// Turn source HTML (Telegram/OLX posts arrive with <br />, entities, etc.) into
// clean plain text so the app doesn't render raw markup.
function stripHtml(s) {
  return String(s ?? '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|li|h[1-6])>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#3[49];/g, "'")
    .replace(/\u00a0/g, ' ')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

// Best-effort street address from a post: an explicit "Адрес:/Manzil:" label, or
// a street pattern (ул./проспект/мкр/ko'chasi). Used for map geocoding + display.
function parseAddress(text) {
  if (!text) return null;
  const labeled = text.match(/(?:адрес|адреса|manzil|address)\s*[:\-–]\s*([^\n]{3,80})/i);
  if (labeled) return labeled[1].replace(/\s+/g, ' ').trim().replace(/[.;,]+$/, '');
  const street = text.match(
    /((?:ул(?:иц[аы])?\.?|улиц[аы]|просп(?:ект)?\.?|проспект|мкр\.?|микрорайон|ko['’]?chasi|k[oó]chasi)\s*[^\n,.;]{2,50}(?:,?\s*\d+[\w/-]*)?)/i,
  );
  if (street) return street[1].replace(/\s+/g, ' ').trim();
  return null;
}

export function makeListing(partial) {
  const title = partial.title ?? 'Untitled';
  const description = stripHtml(partial.description ?? '');
  const combined = `${title} ${description}`;
  const propertyType = partial.propertyType === 'house' ? 'house' : 'flat';
  const byAgency = Boolean(partial.byAgency);
  const rooms = partial.rooms != null ? Number(partial.rooms) : parseRoomsFromText(combined);
  let dealType = partial.dealType ?? classifyDealType(combined);

  // Sale-scale price guard. Some sale posts carry no explicit sale keyword and
  // only mention rent in passing (e.g. "зона для проживания и аренды", price
  // "115 000 у.е."), so classifyDealType mislabels them as longRent. A hard-
  // currency price this large is a purchase, never a monthly rent, so correct
  // it. Scoped to USD/EUR (OLX maps Uzbek "у.е."/UYE to USD) to stay currency-
  // safe; UZS/UAH/etc. nominal values are left untouched. Only overrides a
  // *text-derived* longRent, never an explicit source dealType.
  if (
    partial.dealType == null &&
    dealType === 'longRent' &&
    partial.price != null &&
    Number(partial.price) >= 10000 &&
    ['USD', 'EUR'].includes(String(partial.currency ?? '').toUpperCase())
  ) {
    dealType = 'sale';
  }

  // Structured fields: prefer an explicit value from the source, otherwise parse
  // them out of the post text (works across EN/RU/UZ/KZ/RO/UA).
  const parsedFloor = parseFloor(combined);
  const floor = partial.floor != null ? Number(partial.floor) : parsedFloor.floor;
  const totalFloors =
    partial.totalFloors != null ? Number(partial.totalFloors) : parsedFloor.totalFloors;
  const buildingYear =
    partial.buildingYear != null ? Number(partial.buildingYear) : parseYear(combined);
  const bedrooms = partial.bedrooms != null ? Number(partial.bedrooms) : parseBedrooms(combined);
  const audience = partial.audience ?? classifyAudience(combined);
  const contact = partial.contact ?? parseContact(combined);

  // Intra-city location: district, nearest metro/transit station, and nearby
  // landmarks, detected from the post text unless the source provided them.
  const loc = parseLocation(combined, partial.country);
  // A source-provided district (e.g. OLX's raw "Чиланзарский район") is mapped to
  // our canonical value so the district filter matches; text-parsed districts are
  // already canonical. Unknown names are kept as-is.
  const district = canonicalDistrict(partial.district ?? loc.district, partial.country);
  const metro = partial.metro ?? loc.metro;
  const nearby = partial.nearby ?? loc.nearby;
  const residenceComplex = partial.residenceComplex ?? parseResidentialComplex(combined);
  const address = partial.address ?? parseAddress(combined);

  // Flag non-residential (office / commercial) posts so the housing search can
  // drop them. An explicit propertyType from the source overrides the guess.
  const commercial = partial.commercial ?? looksCommercial(combined);

  // Tenant conditions + costs pulled from the post text unless the source
  // provided them. petsAllowed/childrenAllowed are true/false/null (unstated).
  const petsAllowed = partial.petsAllowed ?? classifyPets(combined);
  const childrenAllowed = partial.childrenAllowed ?? classifyChildren(combined);
  const roomOnly = partial.roomOnly ?? looksRoomOnly(combined);
  const dep = parseDeposit(combined);
  const deposit = partial.deposit ?? dep.required;
  const depositAmount = partial.depositAmount ?? dep.amount;
  const com = parseCommission(combined);
  const commission = partial.commission ?? com.has;
  const commissionPercent = partial.commissionPercent ?? com.percent;

  // Amenities / structured extras for the normalized spec table. Prefer a value
  // the source gave us, else parse it from the text. `null` renders as "n/d".
  const balcony = partial.balcony ?? parseBalcony(combined);
  const airConditioner = partial.airConditioner ?? parseAirConditioner(combined);
  const gas = partial.gas ?? parseGasSupply(combined);
  const bathrooms = partial.bathrooms != null ? Number(partial.bathrooms) : parseBathrooms(combined);
  const newBuilding =
    partial.newBuilding ??
    (parseNewBuilding(combined) ||
      (buildingYear && buildingYear >= new Date().getFullYear() - 3 ? true : null));
  // UZ note: utilities are usually included when unstated (null); the UI reflects that.
  const communalSeparated = partial.communalSeparated ?? parseCommunalSeparated(combined);
  const kvartal = partial.kvartal ?? parseKvartal(combined);
  const nearbyShops = partial.nearbyShops ?? parseNearbyShops(combined);

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
    city: partial.city || loc.city || '',
    address: address || null,
    lat: partial.lat != null ? Number(partial.lat) : null,
    lng: partial.lng != null ? Number(partial.lng) : null,
    photo: partial.photo ?? (Array.isArray(partial.photos) ? partial.photos[0] : null) ?? null,
    photos: Array.isArray(partial.photos)
      ? partial.photos
      : partial.photo
        ? [partial.photo]
        : [],
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
    metro,
    nearby,
    residenceComplex,
    commercial,
    petsAllowed,
    childrenAllowed,
    roomOnly,
    deposit,
    depositAmount,
    commission,
    commissionPercent,
    balcony,
    airConditioner,
    gas,
    bathrooms,
    newBuilding,
    communalSeparated,
    kvartal,
    nearbyShops,
    furnished: partial.furnished ?? null,
    condition: partial.condition ?? null,
    amenities: Array.isArray(partial.amenities) ? partial.amenities : [],
    tags:
      partial.tags ??
      extractTags({
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

// Only surface listings posted within this window — older posts are treated as
// stale/inactive and dropped. (3 weeks, per product requirement.)
export const MAX_AGE_MS = 21 * 24 * 60 * 60 * 1000;

// Lowercase and strip diacritics so "București" matches "bucuresti" etc.
function normCity(s) {
  return String(s ?? '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
}

// Apply the user-facing filters that a source could not enforce server-side.
export function applyFilters(listings, filters, rates = null) {
  const {
    propertyType, agency, priceMin, priceMax, priceTolerance, priceCurrency, query, dealType,
    roomsMin, roomsMax, bedroomsMin, bedroomsMax,
    floorMin, floorMax, yearMin, yearMax, audience, city,
    cityAliases, district, metro,
    pets, children, roomOnly, maxAgeDays, sources,
  } = filters;
  // Cross-currency price filtering: when the client says which currency the
  // min/max are in and we have FX rates, compare everything in USD so a bound
  // in one currency matches listings priced in any. Otherwise fall back to a
  // raw same-currency comparison (unchanged behaviour).
  const convertPrices = !!(rates && priceCurrency);
  const now = Date.now();
  // Optional "posted within N days" freshness cap on top of MAX_AGE_MS.
  const ageCapMs =
    maxAgeDays != null && maxAgeDays > 0
      ? Math.min(maxAgeDays * 24 * 60 * 60 * 1000, MAX_AGE_MS)
      : MAX_AGE_MS;
  // Accept the selected city or any of its localized aliases (from countries.js).
  const cityForms = city ? (cityAliases?.length ? cityAliases : [city]).map(normCity) : null;
  return listings.filter((l) => {
    if (sources?.length && !sources.includes(String(l.source).toLowerCase())) return false;
    // Never show offices / commercial premises among housing results.
    if (l.commercial) return false;
    // Freshness: drop anything with a known post date older than 3 weeks. Posts
    // with no/unparseable date are kept (lenient, like the numeric ranges).
    if (l.createdAt) {
      const t = Date.parse(l.createdAt);
      if (!Number.isNaN(t) && now - t > ageCapMs) return false;
    }
    if (propertyType && propertyType !== 'any' && l.propertyType !== propertyType) return false;
    if (dealType && dealType !== 'any' && l.dealType !== dealType) return false;
    if (agency === 'agency' && !l.byAgency) return false;
    if (agency === 'owner' && l.byAgency) return false;
    // Once the user selects a numeric constraint, an unknown value is not a
    // valid match. Previously unknown prices/room counts slipped through and
    // made the controls appear to do nothing.
    // Optional tolerance: allow listings up to priceMax + priceTolerance through.
    const effMax = priceMax != null ? priceMax + (priceTolerance ?? 0) : null;
    if (priceMin != null || effMax != null) {
      if (convertPrices) {
        const priceUsd = toUsd(l.price, l.currency, rates);
        if (priceUsd == null) return false; // unknown / unconvertible price
        if (priceMin != null) {
          const minUsd = toUsd(priceMin, priceCurrency, rates);
          if (minUsd != null && priceUsd < minUsd) return false;
        }
        if (effMax != null) {
          const maxUsd = toUsd(effMax, priceCurrency, rates);
          if (maxUsd != null && priceUsd > maxUsd) return false;
        }
      } else {
        if (priceMin != null && (l.price == null || l.price < priceMin)) return false;
        if (effMax != null && (l.price == null || l.price > effMax)) return false;
      }
    }
    if (roomsMin != null && (l.rooms == null || l.rooms < roomsMin)) return false;
    if (roomsMax != null && (l.rooms == null || l.rooms > roomsMax)) return false;
    if (bedroomsMin != null && (l.bedrooms == null || l.bedrooms < bedroomsMin)) return false;
    if (bedroomsMax != null && (l.bedrooms == null || l.bedrooms > bedroomsMax)) return false;
    if (floorMin != null && (l.floor == null || l.floor < floorMin)) return false;
    if (floorMax != null && (l.floor == null || l.floor > floorMax)) return false;
    if (yearMin != null && (l.buildingYear == null || l.buildingYear < yearMin)) return false;
    if (yearMax != null && (l.buildingYear == null || l.buildingYear > yearMax)) return false;
    // Audience is an explicit restriction, so match strictly when requested.
    if (audience && audience !== 'any' && l.audience !== audience) return false;
    // Tenant conditions: only drop on an explicit contradiction. A listing that
    // does not state a policy (null) is kept, like the lenient numeric ranges.
    if (pets === true && l.petsAllowed === false) return false;
    if (children === true && l.childrenAllowed === false) return false;
    // Room-only (partial rent): when requested, show only shared-room posts.
    if (roomOnly === true && !l.roomOnly) return false;
    if (cityForms) {
      const hay = normCity(l.city);
      if (!cityForms.some((f) => hay.includes(f))) return false;
    }
    // District / metro are structured picks: match strictly (drop unknowns).
    if (district && (l.district ?? '').toLowerCase() !== String(district).toLowerCase())
      return false;
    if (metro && (l.metro ?? '').toLowerCase() !== String(metro).toLowerCase()) return false;
    if (query) {
      const hay = [l.title, l.description, l.city, l.district, l.metro, ...(l.tags ?? [])]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();
      if (!hay.includes(String(query).toLowerCase())) return false;
    }
    return true;
  });
}
