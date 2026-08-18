// Background refresher. Periodically re-scrapes every country's default browse
// view so live data stays fresh and the common request is served instantly from
// cache. Runs once at startup and then on a fixed interval (hourly by default).
//
// Env:
//   REFRESH_MINUTES   interval in minutes (default 60)
//   DISABLE_SCHEDULER  set to "1" to turn the background job off entirely

import { COUNTRY_CODES } from './countries.js';
import { warmCountry } from './scrapers/index.js';
import { scheduleCountryVision } from './vision-enrichment.js';

const REFRESH_MINUTES = Math.max(1, Number(process.env.REFRESH_MINUTES) || 60);
const REFRESH_MS = REFRESH_MINUTES * 60 * 1000;

let timer = null;
let running = false;
let lastRun = null; // { at, ok, total, sourceCounts, degraded }

// Refresh all countries in parallel. Never throws — individual failures are
// swallowed so one bad source can't stop the schedule. Photo analysis is queued
// only after the fresh snapshot exists and therefore never delays scraping.
export async function refreshAll(reason = 'scheduled') {
  if (running) {
    console.log('[scheduler] refresh already in progress, skipping');
    return lastRun;
  }
  running = true;
  const started = Date.now();
  const sourceCounts = {};
  const degraded = [];
  try {
    const results = await Promise.allSettled(COUNTRY_CODES.map((c) => warmCountry(c)));
    let ok = 0;
    results.forEach((r, i) => {
      if (r.status !== 'fulfilled') {
        console.warn(`[scheduler] ${COUNTRY_CODES[i]} failed: ${r.reason?.message ?? r.reason}`);
        return;
      }
      ok += 1;
      if (r.value.degraded) degraded.push(COUNTRY_CODES[i]);
      for (const [name, n] of Object.entries(r.value.sourceCounts ?? {})) {
        sourceCounts[name] = (sourceCounts[name] ?? 0) + n;
      }

      // Free-tier vision enrichment is deliberately background-only. The
      // provider/result cache prevents repeated external calls for unchanged photos.
      try {
        scheduleCountryVision(COUNTRY_CODES[i], r.value);
      } catch (error) {
        console.warn(`[scheduler] ${COUNTRY_CODES[i]} vision scheduling failed: ${error.message}`);
      }
    });
    lastRun = { at: new Date().toISOString(), ok, total: COUNTRY_CODES.length, sourceCounts, degraded };
    console.log(
      `[scheduler] ${reason} refresh: ${ok}/${COUNTRY_CODES.length} countries, ` +
        `live=${JSON.stringify(sourceCounts)}, demo=[${degraded.join(',')}] in ${Date.now() - started}ms`,
    );
  } finally {
    running = false;
  }
  return lastRun;
}

export function getLastRun() {
  return lastRun;
}

export function startScheduler() {
  if (process.env.DISABLE_SCHEDULER === '1') {
    console.log('[scheduler] disabled via DISABLE_SCHEDULER=1');
    return;
  }
  // Warm on boot (don't block server startup), then on the interval.
  refreshAll('startup').catch((e) => console.warn('[scheduler] startup refresh error', e));
  timer = setInterval(
    () => refreshAll('hourly').catch((e) => console.warn('[scheduler] refresh error', e)),
    REFRESH_MS,
  );
  if (timer.unref) timer.unref(); // don't keep the process alive just for this
  console.log(`[scheduler] auto-refresh every ${REFRESH_MINUTES} min`);
}

export function stopScheduler() {
  if (timer) clearInterval(timer);
  timer = null;
}
