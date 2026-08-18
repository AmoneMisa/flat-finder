// Best-effort geocoding for listings that arrive without GPS coordinates.
//
// Precision order (highest -> lowest):
//   source coordinates -> exact address -> metro -> nearby POI -> area/kvartal
//   -> district -> city.
//
// Coordinates come from Nominatim (OpenStreetMap). Requests are throttled and
// cached because geocoding runs during background refreshes, never on the
// request path.

import { cacheGet, cacheSet } from './cache.js'

const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search'
const UA = 'flat-finder/1.0 (housing aggregator; contact: admin@whiteslove.me)'
const HIT_TTL_MS = 30 * 24 * 60 * 60 * 1000
const MISS_TTL_MS = 24 * 60 * 60 * 1000
const ERR_TTL_MS = 60 * 1000
const MIN_INTERVAL_MS = 1100
const MAX_LOOKUPS_PER_RUN = Number(process.env.GEOCODE_BUDGET) || 60

const POI_ALIASES = {
  Korzinka: 'korzinka|корзинк\\p{L}*',
  Makro: 'makro|макро',
  Havas: '[xh]avas|хавас',
  Carrefour: 'carrefour|карфур',
  Magnum: 'magnum|магнум',
  Clinic: 'clinic|поликлиник\\p{L}*|poliklinik\\p{L}*',
  Hospital: 'hospital|больниц\\p{L}*|shifoxon\\p{L}*',
  School: 'school|школ\\p{L}*|maktab\\p{L}*',
}

let lastCallAt = 0
async function throttle() {
  const wait = lastCallAt + MIN_INTERVAL_MS - Date.now()
  if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait))
  lastCallAt = Date.now()
}

function geoKey(query) {
  // v2 deliberately invalidates old district/address-only cache semantics.
  return `geo:v2:${query.toLowerCase().replace(/\s+/g, ' ').trim()}`
}

async function getCachedGeo(query) {
  const cached = await cacheGet(geoKey(query))
  return cached ? cached.coords : undefined
}

async function fetchGeo(query) {
  await throttle()
  try {
    const params = new URLSearchParams({ q: query, format: 'json', limit: '1' })
    const res = await fetch(`${NOMINATIM_URL}?${params}`, {
      headers: { 'User-Agent': UA, 'Accept-Language': 'en' },
      signal: AbortSignal.timeout(10_000),
    })
    if (!res.ok) throw new Error(`nominatim ${res.status}`)
    const data = await res.json()
    const first = Array.isArray(data) ? data[0] : null
    const coords = first ? { lat: Number(first.lat), lng: Number(first.lon) } : null
    await cacheSet(geoKey(query), { coords }, coords ? HIT_TTL_MS : MISS_TTL_MS)
    return coords
  } catch {
    await cacheSet(geoKey(query), { coords: null }, ERR_TTL_MS)
    return null
  }
}

function jitter(id, amount) {
  if (!amount) return [0, 0]
  let h = 0
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0
  const a = ((h & 0xffff) / 0xffff - 0.5) * 2 * amount
  const b = (((h >>> 16) & 0xffff) / 0xffff - 0.5) * 2 * amount
  return [a, b]
}

function cityCenter(country) {
  const c = country?.center
  return c && typeof c.lat === 'number' && typeof c.lng === 'number' ? c : null
}

function uniq(values) {
  return [...new Set(values.filter((value) => typeof value === 'string' && value.trim()).map((value) => value.trim()))]
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function distanceToMeters(value, unit) {
  const amount = Number(String(value).replace(',', '.'))
  if (!Number.isFinite(amount) || amount <= 0) return null
  return /км|km/i.test(unit) ? Math.round(amount * 1000) : Math.round(amount)
}

export function poiDistanceM(listing, name) {
  const text = `${listing?.title || ''}\n${listing?.description || ''}`
  if (!text.trim() || !name) return null
  const poi = POI_ALIASES[name] || escapeRegExp(name)
  const unit = '(км|km|м|m|метр\\p{L}*)'
  const number = '(\\d+(?:[.,]\\d+)?)'
  const patterns = [
    new RegExp(`${number}\\s*${unit}\\s*(?:от|до|from|to)?\\s*(?:${poi})`, 'iu'),
    new RegExp(`(?:${poi})[^\\r\\n]{0,35}?${number}\\s*${unit}`, 'iu'),
  ]
  for (const re of patterns) {
    const match = text.match(re)
    if (match) return distanceToMeters(match[1], match[2])
  }
  return null
}

function contextParts(listing, country) {
  const city = listing.city || country?.cities?.[0] || ''
  const countryName = country?.name || ''
  return { city, countryName }
}

function poiCandidates(listing, city, countryName) {
  const names = uniq([...(listing.nearbyShops || []), ...(listing.nearby || [])])
  const localContext = listing.area || listing.kvartal || listing.district || city
  return names.map((name) => ({
    q: [name, localContext, city, countryName].filter(Boolean).join(', '),
    source: 'nearby',
    jit: 0,
    // A POI is not the building itself. If the post says "500 m from Korzinka",
    // preserve that as the uncertainty radius; otherwise use a conservative
    // neighbourhood-level estimate.
    accuracyM: poiDistanceM(listing, name) || 500,
  }))
}

// Pure helper exported for unit tests and future UI/debug diagnostics.
export function geocodeCandidates(listing, country) {
  const { city, countryName } = contextParts(listing, country)
  const area = listing.area || listing.kvartal
  const candidates = [
    listing.address && {
      q: [listing.address, city, countryName].filter(Boolean).join(', '),
      source: 'address',
      jit: 0,
      accuracyM: 40,
    },
    listing.metro && {
      q: [`${listing.metro} metro station`, city, countryName].filter(Boolean).join(', '),
      source: 'metro',
      jit: 0,
      accuracyM: 250,
    },
    ...poiCandidates(listing, city, countryName),
    area && {
      q: [area, listing.district, city, countryName].filter(Boolean).join(', '),
      source: 'area',
      jit: 0.003,
      accuracyM: 700,
    },
    listing.district && {
      q: [listing.district, city, countryName].filter(Boolean).join(', '),
      source: 'district',
      jit: 0.008,
      accuracyM: 2500,
    },
    city && {
      q: [city, countryName].filter(Boolean).join(', '),
      source: 'city',
      jit: 0.02,
      accuracyM: 8000,
    },
  ]
  return candidates.filter(Boolean)
}

export async function geocodeListings(listings, country) {
  if (!Array.isArray(listings) || !country) return listings
  const center = cityCenter(country)
  const defaultCity = country?.cities?.[0] || ''
  let budget = MAX_LOOKUPS_PER_RUN

  for (const listing of listings) {
    if (listing.lat != null && listing.lng != null) {
      listing.locationSource ??= 'coordinates'
      listing.locationAccuracyM ??= 25
      continue
    }

    let placed = false
    for (const candidate of geocodeCandidates(listing, country)) {
      let coords = await getCachedGeo(candidate.q)
      if (coords === undefined) {
        // Keep checking later candidates because they may already be cached.
        if (budget <= 0) continue
        coords = await fetchGeo(candidate.q)
        budget--
      }
      if (!coords) continue

      const [dLat, dLng] = jitter(String(listing.id || ''), candidate.jit)
      listing.lat = coords.lat + dLat
      listing.lng = coords.lng + dLng
      listing.locationSource = candidate.source
      listing.locationAccuracyM = candidate.accuracyM
      placed = true
      break
    }

    // The country-level center is only a safe fallback for the configured
    // default city. Never place Kharkiv at Kyiv's center, Cluj at Bucharest, etc.
    const listingCity = listing.city || defaultCity
    if (!placed && center && (!listing.city || listingCity === defaultCity)) {
      const [dLat, dLng] = jitter(String(listing.id || ''), 0.02)
      listing.lat = center.lat + dLat
      listing.lng = center.lng + dLng
      listing.locationSource = 'city'
      listing.locationAccuracyM = 8000
    }
  }
  return listings
}
