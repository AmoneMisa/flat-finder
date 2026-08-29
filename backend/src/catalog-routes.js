import {canonicalCityName, COUNTRIES, COUNTRY_CODES} from './countries.js';
import {cityLocations} from './locations.js';
import {getAvailableListingLocations} from './db.js';
import {getRates} from './fx.js';
import {districtZonesFor} from './district-zones.js';

export function installCatalogRoutes(app) {
  app.get('/api/countries', async (_req, res) => {
    try {
      const result = await Promise.all(
        COUNTRY_CODES.map(async (code) => {
          const country = COUNTRIES[code];
          const locations = cityLocations(code);
          const cities = new Set(country.crawlCities ?? []);

          if (code === 'UA') {
            try {
              const rows = await getAvailableListingLocations(code);

              for (const row of rows) {
                const city = canonicalCityName(code, row.city);
                if (!city) continue;

                cities.add(city);
                if (!locations[city]) {
                  locations[city] = {districts: [], metro: []};
                }

                const district = String(row.district ?? '').trim();
                if (district && !locations[city].districts.includes(district)) {
                  locations[city].districts.push(district);
                }
              }
            } catch (err) {
              console.warn(
                `[locations] ${code} dynamic locations failed: ${err?.message ?? err}`,
              );
            }
          }

          for (const location of Object.values(locations)) {
            location.districts = [...new Set(location.districts ?? [])]
              .sort((a, b) => a.localeCompare(b, 'uk'));
            location.metro = [...new Set(location.metro ?? [])]
              .sort((a, b) => a.localeCompare(b, 'uk'));
          }

          return {
            code: country.code,
            name: country.name,
            currency: country.currency,
            center: country.center,
            cities: [...cities].sort((a, b) => a.localeCompare(b, 'uk')),
            locations,
          };
        }),
      );

      return res.json(result);
    } catch (err) {
      return res.status(500).json({
        error: err?.message ?? String(err),
      });
    }
  });

  app.get('/api/district-zones', async (req, res) => {
    try {
      const country = String(req.query.country || '').toUpperCase();
      const city = String(req.query.city || '').trim();
      if (!country || !city) {
        return res.status(400).json({error: 'country and city are required'});
      }
      const locations = cityLocations(country);
      const districtOptions = locations[city]?.districts ?? [];
      return res.json({zones: districtZonesFor(country, city, districtOptions)});
    } catch (err) {
      return res.status(500).json({error: err?.message ?? String(err)});
    }
  });

  app.get('/api/rates', async (_req, res) => {
    try {
      const {base, rates, at} = await getRates();
      return res.json({
        base,
        rates,
        fetchedAt: new Date(at).toISOString(),
      });
    } catch (err) {
      return res.status(500).json({error: err.message});
    }
  });
}
