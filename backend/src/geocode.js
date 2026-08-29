// Best-effort geocoding for listings that arrive without GPS coordinates.
//
// Precision order (highest -> lowest):
//   source coordinates -> exact address -> street -> residential complex -> metro
//   -> spatial POI constraints -> nearby POI -> microdistrict/area/local place
//   -> district -> city.
//
// Coordinates come from Nominatim (OpenStreetMap). Requests are throttled and
// cached because geocoding runs during background refreshes, never on the
// request path.

import { cacheGet, cacheSet } from './cache.js'
import { canonicalCityName } from './countries.js'
import { assignNearestMetro } from './metro-nearest.js'
import { loadCityPlaces } from './places-db.js'
import { annotateListings } from './nearby-places.js'
import { applyReverseGeo } from './reverse-geo.js'

const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search'
const UA = 'flat-finder/1.0 (housing aggregator; contact: admin@whiteslove.me)'
const HIT_TTL_MS = 30 * 24 * 60 * 60 * 1000
const MISS_TTL_MS = 24 * 60 * 60 * 1000
const ERR_TTL_MS = 60 * 1000
const MIN_INTERVAL_MS = 1100
const MAX_LOOKUPS_PER_RUN = Number(process.env.GEOCODE_BUDGET) || 60
const EARTH_RADIUS_M = 6_371_000

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

function geoKey(query, countryCode) {
  return `geo:v3:${countryCode ? countryCode.toLowerCase() + ':' : ''}${query.toLowerCase().replace(/\s+/g, ' ').trim()}`
}

async function getCachedGeo(query, countryCode) {
  const cached = await cacheGet(geoKey(query, countryCode))
  return cached ? cached.coords : undefined
}

// Without `countrycodes`, Nominatim's global relevance ranking can outrank a
// correct-but-obscure local match with an unrelated same-named place abroad
// (e.g. a Tashkent mahalla query once resolved to "Agram", a mountain pass in
// Afghanistan). The candidate query text already carries city/country as
// words, which isn't a hard constraint the way this param is.
async function fetchGeo(query, countryCode) {
  await throttle()
  try {
    const params = new URLSearchParams({ q: query, format: 'json', limit: '1' })
    if (countryCode) params.set('countrycodes', countryCode.toLowerCase())
    const res = await fetch(`${NOMINATIM_URL}?${params}`, {
      headers: { 'User-Agent': UA, 'Accept-Language': 'en' },
      signal: AbortSignal.timeout(10_000),
    })
    if (!res.ok) throw new Error(`nominatim ${res.status}`)
    const data = await res.json()
    const first = Array.isArray(data) ? data[0] : null
    const coords = first ? { lat: Number(first.lat), lng: Number(first.lon) } : null
    await cacheSet(geoKey(query, countryCode), { coords }, coords ? HIT_TTL_MS : MISS_TTL_MS)
    return coords
  } catch {
    await cacheSet(geoKey(query, countryCode), { coords: null }, ERR_TTL_MS)
    return null
  }
}

export async function geocodeQuery(query, countryCode) {
  if (!query) return null
  const cached = await getCachedGeo(query, countryCode)
  if (cached !== undefined) return cached
  return fetchGeo(query, countryCode)
}

export async function geocodeBbox(query) {
  if (!query) return null
  const key = `geo:bbox:v1:${query.toLowerCase().trim()}`
  const cached = await cacheGet(key)
  if (cached) return cached.bbox

  await throttle()
  try {
    const params = new URLSearchParams({ q: query, format: 'json', limit: '1' })
    const res = await fetch(`${NOMINATIM_URL}?${params}`, {
      headers: { 'User-Agent': UA, 'Accept-Language': 'en' },
      signal: AbortSignal.timeout(10_000),
    })
    if (!res.ok) throw new Error(`nominatim ${res.status}`)
    const data = await res.json()
    const raw = Array.isArray(data) ? data[0]?.boundingbox : null
    const numbers = (raw || []).map(Number)
    const bbox = numbers.length === 4 && numbers.every(Number.isFinite)
      ? [numbers[0], numbers[2], numbers[1], numbers[3]]
      : null
    await cacheSet(key, { bbox }, bbox ? HIT_TTL_MS : MISS_TTL_MS)
    return bbox
  } catch {
    await cacheSet(key, { bbox: null }, ERR_TTL_MS)
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

function listingText(listing) {
  return `${listing?.title || ''}\n${listing?.description || ''}`
}

function detectedPoiNames(listing) {
  const text = listingText(listing)
  if (!text.trim()) return []
  const names = []
  for (const [name, alias] of Object.entries(POI_ALIASES)) {
    if (new RegExp(`(?:${alias})`, 'iu').test(text)) names.push(name)
  }
  return names
}

export function poiDistanceM(listing, name) {
  const text = listingText(listing)
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
  const city = canonicalCityName(
    country?.code,
    listing.city || country?.cities?.[0] || '',
  )
  const countryName = country?.name || ''
  return { city, countryName }
}

function poiCandidates(listing, city, countryName) {
  const names = uniq([
    ...(listing.nearbyShops || []),
    ...(listing.nearby || []),
    ...detectedPoiNames(listing),
  ])
  const area = listing.area || listing.kvartal || listing.microdistrict
  return names.map((name) => {
    const distanceM = poiDistanceM(listing, name)
    return {
      q: [name, area, listing.district, city, countryName].filter(Boolean).join(', '),
      source: 'nearby',
      name,
      distanceM,
      jit: 0,
      accuracyM: distanceM || 500,
    }
  })
}

function listCandidates(values, source, context, accuracyM, jit) {
  return uniq(values || []).map((value) => ({
    q: [value, ...context].filter(Boolean).join(', '),
    source,
    jit,
    accuracyM,
  }))
}

function locationEntityCandidates(listing, city, countryName) {
  const entities = Array.isArray(listing.locationEntities) ? listing.locationEntities : []
  const supported = new Map([
    ['mahalla', { source: 'localArea', accuracyM: 700, jit: 0.003 }],
    ['local_area', { source: 'localArea', accuracyM: 800, jit: 0.003 }],
    ['suburb', { source: 'suburb', accuracyM: 1400, jit: 0.005 }],
    ['settlement', { source: 'settlement', accuracyM: 1400, jit: 0.005 }],
    ['informal_area', { source: 'informalArea', accuracyM: 1300, jit: 0.005 }],
    ['development_area', { source: 'developmentArea', accuracyM: 1200, jit: 0.004 }],
    ['microdistrict', { source: 'microdistrict', accuracyM: 600, jit: 0.002 }],
    ['street', { source: 'street', accuracyM: 180, jit: 0 }],
  ])
  const out = []
  for (const entity of entities) {
    const config = supported.get(entity?.type)
    if (!config || !entity?.name) continue
    out.push({
      q: [entity.name, entity.parent, listing.district, city, countryName].filter(Boolean).join(', '),
      source: config.source,
      jit: config.jit,
      accuracyM: config.accuracyM,
    })
  }
  return out
}

function dedupeCandidates(candidates) {
  const seen = new Set()
  return candidates.filter((candidate) => {
    if (!candidate?.q) return false
    const key = candidate.q.toLowerCase().replace(/\s+/g, ' ').trim()
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
}

export function geocodeCandidates(listing, country) {
  const { city, countryName } = contextParts(listing, country)
  const area = listing.area || listing.kvartal
  const localContext = [listing.district, city, countryName]
  const candidates = [
    listing.address && {
      q: [listing.address, city, countryName].filter(Boolean).join(', '),
      source: 'address',
      jit: 0,
      accuracyM: 40,
    },
    listing.street && {
      q: [listing.street, listing.district, city, countryName].filter(Boolean).join(', '),
      source: 'street',
      jit: 0,
      accuracyM: 180,
    },
    listing.residenceComplex && {
      q: [listing.residenceComplex, listing.district, city, countryName].filter(Boolean).join(', '),
      source: 'residentialComplex',
      jit: 0,
      accuracyM: 300,
    },
    listing.metro && {
      q: [`${listing.metro} metro station`, city, countryName].filter(Boolean).join(', '),
      source: 'metro',
      jit: 0,
      accuracyM: 250,
    },
    ...poiCandidates(listing, city, countryName),
    listing.microdistrict && {
      q: [listing.microdistrict, ...localContext].filter(Boolean).join(', '),
      source: 'microdistrict',
      jit: 0.002,
      accuracyM: 600,
    },
    area && {
      q: [area, ...localContext].filter(Boolean).join(', '),
      source: 'area',
      jit: 0.003,
      accuracyM: 700,
    },
    ...listCandidates(listing.localAreas, 'localArea', localContext, 800, 0.003),
    listing.locality && {
      q: [listing.locality, city, countryName].filter(Boolean).join(', '),
      source: 'locality',
      jit: 0.004,
      accuracyM: 1000,
    },
    ...listCandidates(listing.developmentAreas, 'developmentArea', [city, countryName], 1200, 0.004),
    ...listCandidates(listing.informalAreas, 'informalArea', [city, countryName], 1300, 0.005),
    ...listCandidates(listing.suburbs, 'suburb', [city, countryName], 1400, 0.005),
    ...listCandidates(listing.settlements, 'settlement', [city, countryName], 1400, 0.005),
    ...listCandidates(listing.searchClusters, 'searchCluster', [city, countryName], 1600, 0.006),
    ...locationEntityCandidates(listing, city, countryName),
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
  return dedupeCandidates(candidates)
}

function projectPoint(point, origin) {
  const lat0 = (origin.lat * Math.PI) / 180
  return {
    x: ((point.lng - origin.lng) * Math.PI / 180) * EARTH_RADIUS_M * Math.cos(lat0),
    y: ((point.lat - origin.lat) * Math.PI / 180) * EARTH_RADIUS_M,
  }
}

function unprojectPoint(point, origin) {
  const lat0 = (origin.lat * Math.PI) / 180
  return {
    lat: origin.lat + (point.y / EARTH_RADIUS_M) * (180 / Math.PI),
    lng: origin.lng + (point.x / (EARTH_RADIUS_M * Math.cos(lat0))) * (180 / Math.PI),
  }
}

function spatialResidual(point, anchors) {
  const squared = anchors.map((anchor) => {
    const d = Math.hypot(point.x - anchor.x, point.y - anchor.y)
    return (d - anchor.distanceM) ** 2
  })
  return Math.sqrt(squared.reduce((sum, value) => sum + value, 0) / squared.length)
}

function circlePairCandidates(a, b) {
  const dx = b.x - a.x
  const dy = b.y - a.y
  const d = Math.hypot(dx, dy)
  if (d < 0.001) return []

  const ux = dx / d
  const uy = dy / d
  const along = (a.distanceM ** 2 - b.distanceM ** 2 + d ** 2) / (2 * d)
  const base = { x: a.x + along * ux, y: a.y + along * uy }
  const h2 = a.distanceM ** 2 - along ** 2

  if (h2 >= 0) {
    const h = Math.sqrt(h2)
    return [
      { x: base.x - uy * h, y: base.y + ux * h },
      { x: base.x + uy * h, y: base.y - ux * h },
    ]
  }

  const edgeA = { x: a.x + ux * a.distanceM, y: a.y + uy * a.distanceM }
  const edgeB = { x: b.x - ux * b.distanceM, y: b.y - uy * b.distanceM }
  return [{ x: (edgeA.x + edgeB.x) / 2, y: (edgeA.y + edgeB.y) / 2 }]
}

export function solveSpatialPoint(rawAnchors, prior = null) {
  const anchors = (rawAnchors || []).filter(
    (anchor) => Number.isFinite(anchor?.lat) && Number.isFinite(anchor?.lng) && Number(anchor?.distanceM) > 0,
  )
  if (anchors.length < 2) return null

  const origin = {
    lat: anchors.reduce((sum, anchor) => sum + anchor.lat, 0) / anchors.length,
    lng: anchors.reduce((sum, anchor) => sum + anchor.lng, 0) / anchors.length,
  }
  const localAnchors = anchors.map((anchor) => ({
    ...projectPoint(anchor, origin),
    distanceM: Number(anchor.distanceM),
  }))
  const priorLocal = prior && Number.isFinite(prior.lat) && Number.isFinite(prior.lng)
    ? projectPoint(prior, origin)
    : null

  const candidates = []
  for (let i = 0; i < localAnchors.length; i++) {
    for (let j = i + 1; j < localAnchors.length; j++) {
      candidates.push(...circlePairCandidates(localAnchors[i], localAnchors[j]))
    }
  }

  const totalWeight = localAnchors.reduce((sum, anchor) => sum + 1 / anchor.distanceM, 0)
  candidates.push({
    x: localAnchors.reduce((sum, anchor) => sum + anchor.x / anchor.distanceM, 0) / totalWeight,
    y: localAnchors.reduce((sum, anchor) => sum + anchor.y / anchor.distanceM, 0) / totalWeight,
  })
  if (priorLocal) candidates.push(priorLocal)

  let best = null
  for (const candidate of candidates) {
    const residualM = spatialResidual(candidate, localAnchors)
    const priorPenalty = priorLocal ? Math.hypot(candidate.x - priorLocal.x, candidate.y - priorLocal.y) * 0.01 : 0
    const score = residualM + priorPenalty
    if (!best || score < best.score) best = { point: candidate, residualM, score }
  }
  if (!best) return null

  return {
    ...unprojectPoint(best.point, origin),
    residualM: best.residualM,
    anchorCount: anchors.length,
  }
}

export async function geocodeListings(listings, country) {
  if (!Array.isArray(listings) || !country) return listings
  const center = cityCenter(country)
  const defaultCity = country?.cities?.[0] || ''
  let budget = MAX_LOOKUPS_PER_RUN

  async function lookup(candidate) {
    if (!candidate?.q) return null
    let coords = await getCachedGeo(candidate.q, country.code)
    if (coords === undefined) {
      if (budget <= 0) return null
      coords = await fetchGeo(candidate.q, country.code)
      budget--
    }
    return coords || null
  }

  function applyCandidate(listing, candidate, coords) {
    const [dLat, dLng] = jitter(String(listing.id || ''), candidate.jit)
    listing.lat = coords.lat + dLat
    listing.lng = coords.lng + dLng
    listing.locationSource = candidate.source
    listing.locationAccuracyM = candidate.accuracyM
  }

  for (const listing of listings) {
    const canonicalCity = canonicalCityName(country?.code, listing.city || '')
    if (canonicalCity) listing.city = canonicalCity

    if (listing.lat != null && listing.lng != null) {
      listing.locationSource ??= 'coordinates'
      listing.locationAccuracyM ??= 25
      continue
    }

    const candidates = geocodeCandidates(listing, country)
    const exactCandidates = candidates.filter((candidate) =>
      ['address', 'street', 'residentialComplex', 'metro'].includes(candidate.source),
    )
    const nearbyCandidates = candidates.filter((candidate) => candidate.source === 'nearby')
    const broadCandidates = candidates.filter((candidate) => [
      'microdistrict', 'area', 'localArea', 'locality', 'developmentArea',
      'informalArea', 'suburb', 'settlement', 'searchCluster', 'district', 'city',
    ].includes(candidate.source))

    let placed = false

    for (const candidate of exactCandidates) {
      const coords = await lookup(candidate)
      if (!coords) continue
      applyCandidate(listing, candidate, coords)
      placed = true
      break
    }
    if (placed) continue

    const constrainedPoi = nearbyCandidates.filter((candidate) => candidate.distanceM != null)
    if (constrainedPoi.length >= 2) {
      const anchors = []
      for (const candidate of constrainedPoi) {
        const coords = await lookup(candidate)
        if (coords) anchors.push({ ...coords, distanceM: candidate.distanceM, name: candidate.name })
      }

      if (anchors.length >= 2) {
        const priorCandidate = broadCandidates[0]
        const prior = priorCandidate ? await lookup(priorCandidate) : center
        const spatial = solveSpatialPoint(anchors, prior)
        if (spatial) {
          listing.lat = spatial.lat
          listing.lng = spatial.lng
          listing.locationSource = 'spatial'
          listing.locationAccuracyM = Math.max(100, Math.round(spatial.residualM + 100))
          listing.locationAnchorCount = spatial.anchorCount
          placed = true
        }
      }
    }
    if (placed) continue

    for (const candidate of nearbyCandidates) {
      const coords = await lookup(candidate)
      if (!coords) continue
      applyCandidate(listing, candidate, coords)
      placed = true
      break
    }
    if (placed) continue

    for (const candidate of broadCandidates) {
      const coords = await lookup(candidate)
      if (!coords) continue
      applyCandidate(listing, candidate, coords)
      placed = true
      break
    }

    const listingCity = canonicalCityName(country?.code, listing.city || defaultCity)
    if (!placed && center && (!listing.city || listingCity === defaultCity)) {
      const [dLat, dLng] = jitter(String(listing.id || ''), 0.02)
      listing.lat = center.lat + dLat
      listing.lng = center.lng + dLng
      listing.locationSource = 'city'
      listing.locationAccuracyM = 8000
    }
  }

  await applyReverseGeo(listings, country)
  const placed = await annotateFromPlaces(listings, country)
  if (!placed) {
    await assignNearestMetro(listings, country, (query) => lookup({ q: query }))
  }

  return listings
}

async function annotateFromPlaces(listings, country) {
  const cities = new Set(
    listings
      .filter((listing) => Number.isFinite(listing.lat) && Number.isFinite(listing.lng))
      .map((listing) => listing.city || country?.cities?.[0] || ''),
  )
  let annotated = 0

  for (const city of cities) {
    if (!city) continue
    try {
      const rows = await loadCityPlaces(country?.code, city)
      if (!rows.length) continue
      const batch = listings.filter((listing) => (listing.city || country?.cities?.[0]) === city)
      annotated += annotateListings(batch, rows)
    } catch (error) {
      console.warn(`[places] lookup for ${city} failed:`, error?.message || error)
    }
  }

  if (annotated) console.log(`[places] annotated ${annotated} listings from the places table`)
  return annotated > 0
}