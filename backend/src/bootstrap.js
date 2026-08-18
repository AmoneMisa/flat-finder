import express from 'express';
import { installTranslationRoutes } from './translation-routes.js';

// server.js owns the existing Express app but does not export it. Install the
// translation router immediately before that app starts listening, keeping the
// existing server implementation untouched while the endpoint remains isolated.
const originalListen = express.application.listen;
express.application.listen = function patchedListen(...args) {
  installTranslationRoutes(this);
  express.application.listen = originalListen;
  return originalListen.apply(this, args);
};

await import('./server.js');
