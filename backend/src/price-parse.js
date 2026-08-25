import {maskPhoneLikeSpans} from '@whiteslove/parsing-lexicon/contact';
import {parseHousingPriceFromText} from '@whiteslove/parsing-lexicon/housing-money';

// Compatibility facade for existing Flat Finder callers. Parsing policy and
// phone exclusion live exclusively in @whiteslove/parsing-lexicon.
export const stripPhoneLikePriceCandidates = maskPhoneLikeSpans;
export const parseListingPriceFromText = parseHousingPriceFromText;
