import express from 'express';
import cors from 'cors';
import {installTranslationRoutes} from './translation-routes.js';
import {installHiringRoutes} from './hiring-routes.js';
import {installSocialRoutes} from './social-routes.js';
import {installAvailabilityRoutes} from './availability-routes.js';
import {installSystemRoutes} from './system-routes.js';
import {installListingRoutes} from './listing-routes.js';
import {installListingItemRoutes} from './listing-item-routes.js';
import {installCatalogRoutes} from './catalog-routes.js';
import {installMediaRoutes} from './media-routes.js';

export function createApp() {
  const app = express();
  app.use(cors());
  app.use(express.json());

  installTranslationRoutes(app);
  installHiringRoutes(app);
  installSocialRoutes(app);
  installAvailabilityRoutes(app);
  installSystemRoutes(app);
  installListingRoutes(app);
  installListingItemRoutes(app);
  installCatalogRoutes(app);
  installMediaRoutes(app);

  return app;
}
