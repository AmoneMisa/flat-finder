import express from 'express';
import { installTranslationRoutes } from './translation-routes.js';
import { installHiringRoutes } from './hiring-routes.js';

// server.js owns the existing Express app but does not export it. Install
// isolated auxiliary routers immediately before that app starts listening.
const originalListen = express.application.listen;
express.application.listen = function patchedListen(...args) {
  installTranslationRoutes(this);
  installHiringRoutes(this);
  express.application.listen = originalListen;
  return originalListen.apply(this, args);
};

await import('./server.js');
