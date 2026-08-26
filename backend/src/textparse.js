// Compatibility facade: keep the public textparse API while moving shared
// housing semantics into @whiteslove/parsing-lexicon.
export * from './textparse-legacy.js';

import { parseHousingFeatures } from '@whiteslove/parsing-lexicon';

export function classifyPets(text) {
  return parseHousingFeatures(text).petsAllowed;
}

export function parseInternet(text) {
  return parseHousingFeatures(text).internet;
}
