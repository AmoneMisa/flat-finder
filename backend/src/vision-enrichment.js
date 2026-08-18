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

function listingImages(listing) {
  const source = Array.isArray(listing.photos) && listing.photos.length
    ? listing.photos
    : listing.photo
      ? [listing.photo]
      : [];
  return [...new Set(source.map(String).filter((url) => /^https?:\/\//i.test(url)))]
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

function mergeVision(listing, result) {
  const data = result?.data || {};
  const merged = { ...listing };
  const fill = (field, item) => {
    if ((merged[field] == null || merged[field] === '') && accepted(item)) {
      merged[field] = item.value;
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
    closedYard: 'closed_yard',
    kitchenVisible: 'kitchen',
    washingMachineVisible: 'washing_machine',
    dishwasherVisible: 'dishwasher',
    tvVisible: 'tv',
    gasWaterHeaterVisible: 'gas_water_heater',
    waterBoilerVisible: 'water_boiler',
  };
  const amenities = new Set(merged.amenities || []);
  for (const [visionField, amenity] of Object.entries(amenityMap)) {
    const item = data[visionField];
    if (accepted(item) && item.value === true) amenities.add(amenity);
  }
  merged.amenities = [...amenities];

  if ((merged.gasWaterHeater == null || merged.gasWaterHeater === '') && accepted(data.gasWaterHeaterVisible)) {
    merged.gasWaterHeater = data.gasWaterHeaterVisible.value;
  }
  if ((merged.waterBoiler == null || merged.waterBoiler === '') && accepted(data.waterBoilerVisible)) {
    merged.waterBoiler = data.waterBoilerVisible.value;
  }

  // Keep provenance/evidence available to the API/UI without allowing vision to
  // silently overwrite deterministic/text facts.
  merged.vision = {
    provider: result.provider || null,
    analyzedAt: result.analyzedAt || new Date().toISOString(),
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

    // Exact-photo anti-fake is independent of external AI and runs even when all
    // visual amenity fields are already known from text/source metadata.
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
