import {canonicalCityName, COUNTRIES, COUNTRY_CODES} from './countries.js';
import {cityLocations} from './locations.js';
import {getAvailableListingLocations} from './db.js';
import {getRates} from './fx.js';
import {mapZonesFor} from './district-zones.js';
import {geographyDisplayName} from '@whiteslove/parsing-lexicon/geography-display';

/** {raw name -> localized label}, only for names that actually translate. */
function labelMap(names, locale, kind) {
  const map = {};
  for (const name of names) {
    const label = geographyDisplayName(name, locale, kind);
    if (label && label !== name) map[name] = label;
  }
  return map;
}

export function installCatalogRoutes(app) {
  app.get('/api/countries', async (req, res) => {
    // Clients (the app in particular) render raw geography names as-is by
    // default — OK for Romania/Kazakhstan/Uzbekistan's small Latin-script
    // lists, wrong for a Russian-language UI. Locale is opt-in via query
    // param rather than always computed, since it's extra work for every
    // city/district/metro/microdistrict/quartal/area name in every country.
    const locale = String(req.query.locale || '').trim();
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

          for (const [cityName, location] of Object.entries(locations)) {
            location.districts = [...new Set(location.districts ?? [])]
              .sort((a, b) => a.localeCompare(b, 'uk'));
            location.metro = [...new Set(location.metro ?? [])]
              .sort((a, b) => a.localeCompare(b, 'uk'));

            // Expose the selectable structured sub-city entities that the web
            // client gets from geo-catalog. Flutter consumes these names as
            // filters instead of treating them as arbitrary keyword search.
            const zones = mapZonesFor(code, cityName, location.districts);
            location.microdistricts = zones.microdistrictMarkers.map((item) => item.name);
            location.quartals = zones.quartalMarkers.map((item) => item.name);
            location.areas = zones.areaZones.map((item) => item.name);

            if (locale) {
              location.districtLabels = labelMap(location.districts, locale, 'district');
              location.metroLabels = labelMap(location.metro, locale, 'metro');
              location.microdistrictLabels = labelMap(location.microdistricts, locale, 'any');
              location.quartalLabels = labelMap(location.quartals, locale, 'any');
              location.areaLabels = labelMap(location.areas, locale, 'any');
            }
          }

          const citiesList = [...cities].sort((a, b) => a.localeCompare(b, 'uk'));

          return {
            code: country.code,
            name: country.name,
            currency: country.currency,
            center: country.center,
            cities: citiesList,
            ...(locale ? {cityLabels: labelMap(citiesList, locale, 'city')} : {}),
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
      return res.json(mapZonesFor(country, city, districtOptions));
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
