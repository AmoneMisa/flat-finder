import express from 'express';
import { installTranslationRoutes } from './translation-routes.js';
import { installHiringRoutes } from './hiring-routes.js';
import { installSocialRoutes } from './social-routes.js';
import { installAvailabilityRoutes } from './availability-routes.js';
import { startSocialHousingScheduler } from './social-housing-scheduler.js';

// server.js owns the existing Express app but does not export it. Install
// isolated auxiliary routers immediately before that app starts listening.
const originalListen = express.application.listen;
express.application.listen = function patchedListen(...args) {
  installTranslationRoutes(this);
  installHiringRoutes(this);
  installSocialRoutes(this);
  installAvailabilityRoutes(this);
  express.application.listen = originalListen;
  const server = originalListen.apply(this, args);
  startSocialHousingScheduler();
  return server;
};

await import('./server.js');
