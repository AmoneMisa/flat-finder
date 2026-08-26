import { cacheGet, cacheSet } from './cache.js';
import { upsertListings } from './db.js';
import { indexListings } from './elasticsearch.js';
import { detectExactDuplicatePhotos } from './photo-antifake.js';
import {
  aiWorkerEnabled,
  scheduleVisionAnalysis,
  visionFingerprint,
} from './ai-worker.js';

const STALE_TTL_MS = 60 * 60 * 1000;
const FULL_FEED_VERSION = 'full-feed-v8';
const antiFakeRunning = new Set();

function defaultCacheKey(countryCode) {
  return `${FULL_FEED_VERSION}|${countryCode}|all-sources|`;
}

function listingKey(listing) {
  return `${listing.source}:${listing.id}`;
}

const PHOTO_BASE_URL = (process.env.VISION_PHOTO_BASE_URL || 'http://flat-finder-backend:4000').replace(/\/$/, '');

function absolutePhotoUrl(raw) {
  const url = String(raw || '').trim();
  if (!url) return null;
  if (/^https?:\/\//i.test(url)) return url;
  if (url.startsWith('/api/tg-photo/')) return `${PHOTO_BASE_URL}${url}`;
  return null;
}

function listingImages(listing) {
  const source = Array.isArray(listing.photos) && listing.photos.length
    ? listing.photos
    : listing.photo
      ? [listing.photo]
      : [];
  return [...new Set(source.map(absolutePhotoUrl).filter(Boolean))]
    .slice(0, 4)
    .map((url, index) => ({ id: `photo_${index + 1}`, url }));
}

function needsVision(listing) {
  if (!listing || String(listing.source || '').startsWith('mock')) return false;
  if (!listingImages(listing).length) return false;
  return [
    listing.airConditioner,
    listing.balcony,
    listing.bathrooms,
    listing.bathroomLayout,
    listing.bedrooms,
    listing.furnished,
    listing.parking,
    listing.elevator,
    listing.condition,
  ].some((value) => value == null || value === '');
}

function accepted(item, minConfidence = 0.75) {
  return item && item.value != null && Number(item.confidence) >= minConfidence;
}

export function mergeVision(listing, result) {
  const data = result?.data || {};
  const merged = { ...listing };
  const derivedFields = new Set(
    Array.isArray(listing?.vision?.derivedFields) ? listing.vision.derivedFields.map(String) : [],
  );
  const fill = (field, item, provenanceField = field) => {
    if ((merged[field] == null || merged[field] === '') && accepted(item)) {
      merged[field] = item.value;
      derivedFields.add(provenanceField);
    }
  };

  fill('airConditioner', data.airConditioner);
  fill('balcony', data.balcony);
  fill('bathrooms', data.bathroomsVisible);
  fill('bathroomLayout', data.bathroomLayoutVisible);
  fill('bedrooms', data.bedroomsVisible);
  fill('furnished', data.furnished);
  fill('parking', data.parkingVisible);
  fill('elevator', data.elevatorVisible);
  fill('condition', data.renovationLevel);

  const amenityMap = {
    closedYard: { amenity: 'closed_yard', field: 'closedYard' },
    kitchenVisible: { amenity: 'kitchen', field: 'kitchen' },
    washingMachineVisible: { amenity: 'washing_machine', field: 'washingMachine' },
    dishwasherVisible: { amenity: 'dishwasher', field: 'dishwasher' },
    tvVisible: { amenity: 'tv', field: 'tv' },
    gasWaterHeaterVisible: { amenity: 'gas_water_heater', field: 'gasWaterHeater' },
    waterBoilerVisible: { amenity: 'water_boiler', field: 'waterBoiler' },
  };
  const amenities = new Set(merged.amenities || []);
  for (const [visionField, { amenity, field }] of Object.entries(amenityMap)) {
    const item = data[visionField];
    if (accepted(item) && item.value === true && !amenities.has(amenity)) {
      amenities.add(amenity);
      derivedFields.add(field);
    }
  }
  merged.amenities = [...amenities];

  fill('gasWaterHeater', data.gasWaterHeaterVisible);
  fill('waterBoiler', data.waterBoilerVisible);

  merged.vision = {
    provider: result.provider || null,
    analyzedAt: result.analyzedAt || new Date().toISOString(),
    derivedFields: [...derivedFields].sort(),
    data,
  };
  return merged;
}

async function persistMerged(listing) {
  try {
    const saved = await upsertListings([listing]);
    if (saved) await indexListings([listing]);
  } catch (error) {
    console.warn(`[flats:vision] persistence failed for ${listingKey(listing)}: ${error.message}`);
  }
}

async function applyResult(countryCode, id, fingerprint, result) {
  const key = defaultCacheKey(countryCode);
  const entry = await cacheGet(key);
  if (!entry?.complete || !Array.isArray(entry.listings)) return;

  const index = entry.listings.findIndex((listing) => listingKey(listing) === id);
  if (index < 0) return;
  const current = entry.listings[index];
  const images = listingImages(current);
  if (visionFingerprint(images) !== fingerprint) return;

  const merged = mergeVision(current, result);
  entry.listings[index] = merged;
  entry.vision = entry.vision || {};
  entry.vision[id] = {
    fingerprint,
    status: 'completed',
    provider: result.provider || null,
    analyzedAt: result.analyzedAt || new Date().toISOString(),
  };
  await cacheSet(key, entry, STALE_TTL_MS);
  await persistMerged(merged);
}

async function applyAntiFake(countryCode, id, fingerprint, result) {
  const key = defaultCacheKey(countryCode);
  const entry = await cacheGet(key);
  if (!entry?.complete || !Array.isArray(entry.listings)) return;
  const index = entry.listings.findIndex((listing) => listingKey(listing) === id);
  if (index < 0) return;

  const current = entry.listings[index];
  if (visionFingerprint(listingImages(current)) !== fingerprint) return;

  const merged = {
    ...current,
    antiFake: result,
    duplicatePhotoRisk: result.risk,
    exactDuplicatePhoto: result.exactDuplicatePhoto,
  };
  entry.listings[index] = merged;
  entry.antiFake = entry.antiFake || {};
  entry.antiFake[id] = {
    fingerprint,
    status: 'completed',
    risk: result.risk,
    matches: result.matches.length,
    checkedAt: result.checkedAt,
  };
  await cacheSet(key, entry, STALE_TTL_MS);
  await persistMerged(merged);
}

function scheduleAntiFake(countryCode, listing, images, fingerprint) {
  const id = listingKey(listing);
  const runKey = `${countryCode}:${id}:${fingerprint}`;
  if (antiFakeRunning.has(runKey)) return false;
  antiFakeRunning.add(runKey);

  void detectExactDuplicatePhotos(listing, images)
    .then((result) => applyAntiFake(countryCode, id, fingerprint, result))
    .catch((error) => console.warn(`[flats:antifake] ${id} failed: ${error.message}`))
    .finally(() => antiFakeRunning.delete(runKey));
  return true;
}

export function scheduleListingsVision(listings) {
  if (!aiWorkerEnabled() || !Array.isArray(listings) || !listings.length) return 0;

  const batchSize = Math.max(1, Number(process.env.AI_WORKER_VISION_BATCH) || 3);
  let queued = 0;

  for (const listing of listings) {
    if (queued >= batchSize) break;
    if (!needsVision(listing)) continue;

    const images = listingImages(listing);
    if (!images.length) continue;
    const fingerprint = visionFingerprint(images);
    const id = listingKey(listing);

    const acceptedQueue = scheduleVisionAnalysis({
      id,
      images,
      fingerprint,
      onResult: async (result) => {
        const merged = mergeVision(listing, result);
        if (visionFingerprint(listingImages(merged)) !== fingerprint) return;
        await persistMerged(merged);
      },
      onFailed: (status) => {
        console.warn(`[flats:vision] ${id} failed status=${status}`);
      },
    });

    if (acceptedQueue) queued += 1;
  }

  if (queued) console.log(`[flats:vision] queued persisted-listing vision=${queued}`);
  return queued;
}

export function scheduleCountryVision(countryCode, entry) {
  if (!entry?.complete || !Array.isArray(entry.listings)) return 0;

  const batchSize = Math.max(1, Number(process.env.AI_WORKER_VISION_BATCH) || 3);
  entry.vision = entry.vision || {};
  entry.antiFake = entry.antiFake || {};
  let queued = 0;
  let antiFakeQueued = 0;

  for (const listing of entry.listings) {
    if (queued >= batchSize && antiFakeQueued >= batchSize) break;
    if (!listing || String(listing.source || '').startsWith('mock')) continue;

    const images = listingImages(listing);
    if (!images.length) continue;
    const fingerprint = visionFingerprint(images);
    const id = listingKey(listing);

    const priorAntiFake = entry.antiFake[id];
    if (
      antiFakeQueued < batchSize &&
      !(priorAntiFake?.fingerprint === fingerprint && priorAntiFake.status === 'completed') &&
      scheduleAntiFake(countryCode, listing, images, fingerprint)
    ) {
      entry.antiFake[id] = { fingerprint, status: 'pending', updatedAt: new Date().toISOString() };
      antiFakeQueued += 1;
    }

    if (!aiWorkerEnabled() || queued >= batchSize || !needsVision(listing)) continue;
    const prior = entry.vision[id];
    if (prior?.fingerprint === fingerprint && prior.status === 'completed') continue;

    const acceptedQueue = scheduleVisionAnalysis({
      id,
      images,
      fingerprint,
      onResult: (result) => applyResult(countryCode, id, fingerprint, result),
      onFailed: async (status) => {
        const key = defaultCacheKey(countryCode);
        const current = await cacheGet(key);
        if (!current?.complete) return;
        current.vision = current.vision || {};
        current.vision[id] = {
          fingerprint,
          status,
          updatedAt: new Date().toISOString(),
        };
        await cacheSet(key, current, STALE_TTL_MS);
      },
    });

    if (acceptedQueue) {
      entry.vision[id] = {
        fingerprint,
        status: 'pending',
        updatedAt: new Date().toISOString(),
      };
      queued += 1;
    }
  }

  if (queued || antiFakeQueued) {
    console.log(`[flats:vision] queued vision=${queued}, antifake=${antiFakeQueued} for ${countryCode}`);
  }
  return queued + antiFakeQueued;
}
