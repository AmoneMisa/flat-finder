// Best-effort geocoding for listings that arrive without GPS coordinates
// (Telegram posts, most custom sources). We place a flat on the map at the most
// specific location it names, falling back down the chain:
//
//   address (highest)  ->  metro station  ->  district  ->  city center (lowest)
//
// Coordinates come from Nominatim (OpenStreetMap). Nominatim's usage policy caps
// requests at ~1/s and requires a User-Agent, so every lookup is throttled and
// cached (in Redis via cache.js, keyed by the query) — a district/address is only
// ever geocoded once. This runs inside the background refresh (scrapers/index.js),
// never on the request path.

import { cacheGet, cacheSet } from './cache.js'

const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search'
const UA = 'flat-finder/1.0 (housing aggregator; contact: admin@whiteslove.me)'
const HIT_TTL_MS = 30 * 24 * 60 * 60 * 1000 // coords don't move — cache a month
const MISS_TTL_MS = 24 * 60 * 60 * 1000 // retry "not found" the next day
const ERR_TTL_MS = 60 * 1000 // transient error — retry soon
const MIN_INTERVAL_MS = 1100 // stay under Nominatim's ~1 req/s
// Cap live lookups per refresh so a big cold batch can't run for many minutes;
// whatever isn't geocoded this round falls back to the city center and is
// resolved on a later refresh (the cache persists between runs).
const MAX_LOOKUPS_PER_RUN = Number(process.env.GEOCODE_BUDGET) || 60

let lastCallAt = 0
async function throttle() {
  const wait = lastCallAt + MIN_INTERVAL_MS - Date.now()
  if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait))
  lastCallAt = Date.now()
}

function geoKey(query) {
  return `geo:${query.toLowerCase().replace(/\s+/g, ' ').trim()}`
}

// undefined = never looked up; null = looked up, no result; {lat,lng} = hit.
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
  } catch (err) {
    await cacheSet(geoKey(query), { coords: null }, ERR_TTL_MS)
    return null
  }
}

// Deterministic ~metre-scale jitter from the listing id, so many pins sharing a
// district/city centroid don't stack on the exact same point.
function jitter(id, amount) {
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

// Mutates each listing without lat/lng, setting coordinates from the best signal.
export async function geocodeListings(listings, country) {
  if (!Array.isArray(listings) || !country) return listings
  const center = cityCenter(country)
  const cityName = country.name
  let budget = MAX_LOOKUPS_PER_RUN

  for (const listing of listings) {
    if (listing.lat != null && listing.lng != null) continue
    const place = listing.city || cityName
    // Priority: address > metro > district. `jit` widens with vagueness.
    const candidates = [
      listing.address && { q: `${listing.address}, ${place}, ${cityName}`, jit: 0 },
      listing.metro && { q: `${listing.metro} metro station, ${place}, ${cityName}`, jit: 0.003 },
      listing.district && { q: `${listing.district}, ${place}, ${cityName}`, jit: 0.008 },
    ].filter(Boolean)

    let placed = false
    for (const candidate of candidates) {
      let coords = await getCachedGeo(candidate.q)
      if (coords === undefined) {
        if (budget <= 0) break // out of live-lookup budget this run
        coords = await fetchGeo(candidate.q)
        budget--
      }
      if (coords) {
        const [dLat, dLng] = jitter(listing.id, candidate.jit)
        listing.lat = coords.lat + dLat
        listing.lng = coords.lng + dLng
        placed = true
        break
      }
    }

    if (!placed && center) {
      const [dLat, dLng] = jitter(listing.id, 0.02) // spread around the city centre
      listing.lat = center.lat + dLat
      listing.lng = center.lng + dLng
    }
  }
  return listings
}
