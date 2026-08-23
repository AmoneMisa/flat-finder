import express from 'express';
import { installTranslationRoutes } from './translation-routes.js';
import { installHiringRoutes } from './hiring-routes.js';
import { installSocialRoutes } from './social-routes.js';
import { installAvailabilityRoutes } from './availability-routes.js';

// server.js owns the existing Express app but does not export it. Install
// isolated auxiliary routers immediately before that app starts listening.
// Recurring crawl/maintenance jobs live in src/worker.js, never this API process.
const originalListen = express.application.listen;
express.application.listen = function patchedListen(...args) {
  installTranslationRoutes(this);
  installHiringRoutes(this);
  installSocialRoutes(this);
  installAvailabilityRoutes(this);
  express.application.listen = originalListen;
  return originalListen.apply(this, args);
};

await import('./server.js');
