# AI / Contributor Architecture Rules

## Parsing belongs in the lexicon, not here

All free-text parsing, semantic classification, and multilingual vocabulary
(regex or dictionary-based) for housing listing data lives in
`@whiteslove/parsing-lexicon` — never locally in `backend/src`.

This applies to:

- Extracting structured fields from free text (rooms, floor, area, price,
  audience, commission, address, room-share, utilities, deposits, amenities,
  landmarks, etc.)
- Multilingual keyword/vocabulary lists used to detect or classify meaning
  (deal type, property type, currency, district/city names, etc.)
- Any regex whose job is to *understand* text, not just validate a
  narrowly-scoped format.

A local parser in this repo is only acceptable when it covers a format the
shared lexicon genuinely does not (and is unlikely to ever need generically)
— e.g. this product's own Uzbek "3//4//4//" compact-layout shorthand, or a
bare "NNкв" area shorthand with no unit suffix. Keep those minimal and
comment why they're local, not shared.

**Before writing a new regex or vocabulary list in `backend/src`, check
whether `@whiteslove/parsing-lexicon` already exports it.** If the lexicon
is missing the case, fix it in the lexicon package and bump the pin here —
do not patch around a lexicon gap with a local parser as a shortcut.

`backend/src/listing-enrichment.js` is the reference example: it now calls
`parseHousingListingEnrichment` from the shared lexicon for area, floor,
audience, commission, address, and room-share, and keeps only the small,
genuinely product-specific supplements listed above plus safety-policy
logic (which is product policy over already-parsed fields, not language
parsing). Do not reintroduce hand-rolled regex for anything the lexicon
already covers.
