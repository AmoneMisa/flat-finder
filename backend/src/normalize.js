// A single normalized Listing shape that the Flutter app consumes, regardless
// of which source (OLX, Reddit, Telegram, Threads, mock) produced it.
//
// {
//   id, source, country, title, propertyType, byAgency, price, currency,
//   rooms, areaSqm, city, lat, lng, photo, url, createdAt,
//   description: string,        // free text used for tag extraction
//   dealType: 'sale'|'longRent'|'shortRent'|null,
//   floor, totalFloors, buildingYear, bedrooms: number|null,
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
} from './textparse.js';
import { parseLocation } from './locations.js';

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

export function makeListing(partial) {
  const title = partial.title ?? 'Untitled';
  const description = stripHtml(partial.description ?? '');
  const combined = `${title} ${description}`;
  const propertyType = partial.propertyType === 'house' ? 'house' : 'flat';
  const byAgency = Boolean(partial.byAgency);
  const rooms = partial.rooms != null ? Number(partial.rooms) : null;
  const dealType = partial.dealType ?? classifyDealType(combined);

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
  const district = partial.district ?? loc.district;
  const metro = partial.metro ?? loc.metro;
  const nearby = partial.nearby ?? loc.nearby;

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
    areaSqm: partial.areaSqm != null ? Number(partial.areaSqm) : null,
    city: partial.city ?? '',
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
    tags:
      partial.tags ??
      extractTags({ title, description, propertyType, byAgency, rooms, dealType, audience }),
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
export function applyFilters(listings, filters) {
  const {
    propertyType, agency, priceMin, priceMax, priceTolerance, query, dealType,
    roomsMin, roomsMax, bedroomsMin, bedroomsMax,
    floorMin, floorMax, yearMin, yearMax, audience, city,
    cityAliases, district, metro,
  } = filters;
  const now = Date.now();
  // Accept the selected city or any of its localized aliases (from countries.js).
  const cityForms = city ? (cityAliases?.length ? cityAliases : [city]).map(normCity) : null;
  return listings.filter((l) => {
    // Freshness: drop anything with a known post date older than 3 weeks. Posts
    // with no/unparseable date are kept (lenient, like the numeric ranges).
    if (l.createdAt) {
      const t = Date.parse(l.createdAt);
      if (!Number.isNaN(t) && now - t > MAX_AGE_MS) return false;
    }
    if (propertyType && propertyType !== 'any' && l.propertyType !== propertyType) return false;
    if (dealType && dealType !== 'any' && l.dealType !== dealType) return false;
    if (agency === 'agency' && !l.byAgency) return false;
    if (agency === 'owner' && l.byAgency) return false;
    if (priceMin != null && l.price != null && l.price < priceMin) return false;
    // Optional tolerance: allow listings up to priceMax + priceTolerance through.
    const effMax = priceMax != null ? priceMax + (priceTolerance ?? 0) : null;
    if (effMax != null && l.price != null && l.price > effMax) return false;
    // Numeric ranges skip listings where the value is unknown (like price).
    if (roomsMin != null && l.rooms != null && l.rooms < roomsMin) return false;
    if (roomsMax != null && l.rooms != null && l.rooms > roomsMax) return false;
    if (bedroomsMin != null && l.bedrooms != null && l.bedrooms < bedroomsMin) return false;
    if (bedroomsMax != null && l.bedrooms != null && l.bedrooms > bedroomsMax) return false;
    if (floorMin != null && l.floor != null && l.floor < floorMin) return false;
    if (floorMax != null && l.floor != null && l.floor > floorMax) return false;
    if (yearMin != null && l.buildingYear != null && l.buildingYear < yearMin) return false;
    if (yearMax != null && l.buildingYear != null && l.buildingYear > yearMax) return false;
    // Audience is an explicit restriction, so match strictly when requested.
    if (audience && audience !== 'any' && l.audience !== audience) return false;
    if (cityForms) {
      const hay = normCity(l.city);
      if (!cityForms.some((f) => hay.includes(f))) return false;
    }
    // District / metro are structured picks: match strictly (drop unknowns).
    if (district && (l.district ?? '').toLowerCase() !== String(district).toLowerCase())
      return false;
    if (metro && (l.metro ?? '').toLowerCase() !== String(metro).toLowerCase()) return false;
    if (query) {
      const hay = `${l.title} ${l.city}`.toLowerCase();
      if (!hay.includes(String(query).toLowerCase())) return false;
    }
    return true;
  });
}
