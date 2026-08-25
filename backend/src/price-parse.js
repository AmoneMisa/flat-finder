import {parsePriceFromText} from './textparse.js';

// Strip phone-like digit runs before looking for a price. Price extraction used
// to mask phones only in its last-resort fallback, so a phone could still win in
// an earlier currency/keyword branch (for example `095 082 01 03` in a post
// whose real budget is `до 10 000 грн`). Keep newlines out of the separator set
// so unrelated numbers on adjacent lines are never merged into one phone.
export function stripPhoneLikePriceCandidates(text) {
  return String(text || '').replace(/\+?\d(?:[\t \u00a0().-]*\d){9,}/g, ' ');
}

export function parseListingPriceFromText(text, fallbackCurrency = '') {
  return parsePriceFromText(stripPhoneLikePriceCandidates(text), fallbackCurrency);
}
