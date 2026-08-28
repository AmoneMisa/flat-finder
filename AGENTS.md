# AI / Contributor Architecture Rules

## Shared parsing and geography architecture

Flat Finder does **not** own generic natural-language parsing or canonical
geographic knowledge for housing listings.

Reusable functionality is split between two shared packages:

```text
@whiteslove/parsing-lexicon
@whiteslove/geo-catalog
```

Their responsibilities are intentionally different.

```text
raw listing / source data
        │
        ├─────────────────────────────────────┐
        │                                     │
        ▼                                     ▼
@whiteslove/parsing-lexicon          structured source fields
        │
        │ semantic interpretation
        ▼
recognized housing/location meaning
        │
        ▼
@whiteslove/geo-catalog
        │
        │ canonical geographic identity/data
        ▼
canonical geo entities / geoId /
coordinates / hierarchy / boundaries
        │
        ▼
Flat Finder
        │
        ▼
product normalization
policy
matching
ranking
search
persistence
UI
```

The dependency direction must remain clear:

* the lexicon understands **human-written listing language**;
* the geo catalog understands **canonical geography**;
* Flat Finder understands **product behavior**.

Do not collapse these responsibilities into local helpers inside
`backend/src`.

---

# 1. Parsing belongs in the lexicon

All reusable free-text parsing, semantic extraction, semantic classification,
and multilingual vocabulary for housing listing data belongs in:

```text
@whiteslove/parsing-lexicon
```

and not locally in `backend/src`.

If code inspects arbitrary human-written listing text and determines
**what that text means**, it is normally parsing-lexicon responsibility.

This applies whether the implementation uses:

* regular expressions;
* string matching;
* dictionaries;
* keyword lists;
* synonym maps;
* transliteration maps;
* tokenization;
* normalization rules;
* heuristics;
* scoring;
* language detection;
* combinations of the above.

Changing implementation technique does not change ownership.

---

## Housing concepts owned by the lexicon

This includes, but is not limited to:

* rooms;
* bedrooms;
* room count;
* room-share;
* roommate / apartment-share intent;
* floor;
* total building floors;
* area;
* living area;
* kitchen area;
* price;
* price period;
* rent / sale;
* short-term / long-term rental;
* currency wording;
* commission;
* agency fees;
* deposits;
* prepayment;
* utilities;
* utilities-included state;
* audience restrictions;
* tenant preferences;
* family-related wording;
* student-related wording;
* gender-related listing wording;
* pet-related wording;
* children-related wording;
* smoking-related wording;
* property type;
* apartment;
* house;
* room;
* studio;
* furnished / unfurnished state;
* amenities;
* appliances;
* parking;
* balcony;
* elevator;
* heating;
* air conditioning;
* internet;
* address fragments;
* textual location references;
* landmarks mentioned in prose;
* transit / metro references;
* multilingual housing vocabulary;
* spelling variants;
* abbreviations carrying semantic meaning;
* transliterations;
* common marketplace shorthand.

---

# 2. What counts as text understanding

A regex is not acceptable merely because it is small.

The relevant question is:

> Is this code validating a known machine-oriented format, or is it inferring
> semantic meaning from human-written text?

If it infers meaning, it normally belongs in the lexicon.

For example:

```js
/\bбез\s+комиссии\b/i
/\bno\s+commission\b/i
/\bfaqat\s+oilaga\b/i
/\b\d+\s*этаж\b/i
/\b\d+\s*(?:м²|м2|sqm)\b/i
```

are semantic parsers.

They do not belong in Flat Finder merely because they are one-line regexes.

Likewise:

```js
const FAMILY_ONLY_WORDS = [...];
const RENT_KEYWORDS = [...];
const CURRENCY_WORDS = [...];
const ROOM_SHARE_WORDS = [...];
```

are semantic vocabularies and belong in the shared parsing layer.

---

# 3. Before writing regex or vocabulary in `backend/src`

Before adding:

* a regex;
* keyword array;
* synonym table;
* transliteration table;
* semantic string matcher;
* language-specific fallback;

inside `backend/src`, determine whether the code is performing semantic
interpretation.

Ask:

1. Is the input arbitrary human-written listing text?
2. Is the code trying to determine what that text means?
3. Could another housing application reasonably need the same behavior?
4. Does `@whiteslove/parsing-lexicon` already expose this behavior?
5. Would the local implementation duplicate or partially duplicate an
   existing lexicon parser?

If the answer to the first three questions is yes, the implementation should
normally live in the lexicon.

If the lexicon is missing the capability, fix the lexicon.

Do not create a local workaround simply because it requires fewer changed
files.

---

# 4. Local parsing exceptions

A local parser is acceptable only when the syntax is genuinely specific to a
Flat Finder source, ingestion format, or product convention and is not useful
as generic housing-language understanding.

Examples currently considered acceptable include narrowly scoped source
formats such as:

```text
3//4//4//
2/5/9
1//2//4
```

when they represent marketplace-specific compact layout notation.

Another example is a source-specific bare area shorthand such as:

```text
65кв
82 кв
```

if surrounding source structure makes its meaning unambiguous while parsing
the same pattern globally would create unacceptable false positives.

These local exceptions must remain narrow.

When adding one:

1. Keep it as small as possible.
2. Scope it to the exact source/product syntax.
3. Do not add generic multilingual synonyms.
4. Do not gradually extend it into a generic housing parser.
5. Explain in a comment why it is intentionally local.
6. Add positive and negative tests.
7. Reconsider moving it to the lexicon if multiple sources begin using it.

Example:

```js
// Source-specific syntax.
//
// This marketplace emits compact layouts such as "3//4//4//".
// This is not general natural-language housing parsing and therefore remains
// local.
//
// Do not add normal room/floor parsing here.
function parseSourceCompactLayout(value) {
  // ...
}
```

---

# 5. Machine-readable source formats may remain local

Flat Finder may parse and validate known machine-oriented source fields.

Examples:

```text
2026-08-28T13:42:11Z
USD
listing_182772
41.311081
69.240562
```

Local validation is appropriate for:

* timestamps;
* numeric IDs;
* UUIDs;
* URLs;
* pagination tokens;
* API enums;
* source response shapes;
* numeric latitude/longitude;
* coordinate ranges;
* machine-readable source metadata.

This is not semantic natural-language parsing.

---

# 6. `listing-enrichment.js` is the reference boundary

`backend/src/listing-enrichment.js` is the reference implementation for the
parsing boundary.

Generic housing-language interpretation should be delegated to public exports
from:

```text
@whiteslove/parsing-lexicon
```

including:

```js
parseHousingListingEnrichment(...)
```

where applicable.

Conceptually:

```js
const parsed = parseHousingListingEnrichment(text);

const sourceSpecific = parseSourceSpecificSyntax(rawSourceData);

const normalized = normalizeListing({
  parsed,
  sourceSpecific,
  sourceFields,
});
```

Do not reintroduce generic hand-written parsing into this module.

Forbidden example:

```js
if (/без комиссии/i.test(text)) {
  commission = 0;
}
```

Forbidden example:

```js
const ROOM_SHARE_WORDS = [
  "подселение",
  "roommate",
  "койко место",
];
```

Forbidden example:

```js
if (!parsed.area) {
  // local generic area fallback
}
```

If the lexicon misses a generic case, fix the lexicon.

---

# 7. Do not silently improve lexicon output locally

This anti-pattern is specifically forbidden:

```js
const parsed = parseHousingListingEnrichment(text);

if (!parsed.area) {
  // 40 lines of additional generic parsing
}
```

The same rule applies to:

* floor;
* price;
* commission;
* room-share;
* audience;
* address;
* district;
* property type;
* currency;
* amenities;
* any other reusable semantic field.

A missing generic parse is evidence of a lexicon gap.

Flat Finder must not accumulate a shadow implementation of the lexicon.

---

# 8. Do not fork vocabulary

Never copy lexicon vocabulary into Flat Finder in order to modify it locally.

For example:

```js
const NO_COMMISSION_WORDS = [...];
```

must not be copied from the package and independently extended.

Shared vocabulary should have one canonical implementation.

Otherwise packages will diverge as support evolves for:

* new languages;
* spelling variants;
* transliterations;
* abbreviations;
* false-positive fixes;
* marketplace terminology.

---

# 9. Multilingual behavior belongs in the lexicon

Flat Finder works with multilingual listing data.

Do not solve language support through application-local patches.

This includes support for combinations of:

* Russian;
* Ukrainian;
* Uzbek Latin;
* Uzbek Cyrillic;
* English;
* mixed-language listings;
* transliterated names;
* marketplace-specific abbreviations.

A listing may contain several languages simultaneously.

Flat Finder should operate on semantic fields such as:

```js
parsed.commission
parsed.audience
parsed.rooms
```

rather than:

```js
text.includes("комиссия") ||
text.includes("commission") ||
text.includes("komissiya")
```

---

# 10. Parsing vs normalization

Normalization can exist on either side of the architecture, depending on what
is being normalized.

## Lexicon normalization

Normalization belongs in the lexicon when it is required to understand human
language.

Examples:

```text
долл.        → USD
кв.м         → square metres
у.е.         → recognized monetary wording
faqat oila   → semantic audience restriction
```

## Flat Finder normalization

Normalization belongs locally when converting already-understood semantic
output into the product's own model.

Example:

```js
parsed.propertyType === "apartment"
```

may be mapped to:

```js
ListingType.APARTMENT
```

Likewise:

```js
parsed.currency === "USD"
```

may be mapped to an internal DB enum.

The lexicon decides what the text means.

Flat Finder decides how that meaning is represented in the product.

---

# 11. Product policy is not parsing

Flat Finder may make product decisions based on already-parsed fields.

Example:

```js
const parsed = parseHousingListingEnrichment(text);

if (parsed.audience?.allowsFamilies === false) {
  // Flat Finder policy.
}
```

Understanding what the text says about audience is lexicon responsibility.

Deciding what Flat Finder does with that result is application responsibility.

Valid Flat Finder product logic includes:

* ranking;
* filtering;
* safety rules;
* visibility decisions;
* match scoring;
* confidence thresholds;
* deduplication;
* source trust;
* conflict resolution;
* database mapping;
* UI representation;
* moderation;
* manual review;
* freshness rules.

---

# 12. Source structured fields and parser output

A marketplace may provide structured fields alongside listing text.

Use structured data where appropriate, but do not create an application-local
semantic text parser as a fallback.

A typical pipeline may be:

```text
source structured fields
            +
title / description
            │
            ▼
@whiteslove/parsing-lexicon
            │
            ▼
semantic parse
            │
            ▼
Flat Finder conflict-resolution logic
            │
            ▼
normalized listing
```

Choosing between conflicting source data and parsed data is a Flat Finder
concern.

Understanding free text is not.

---

# 13. Geographic architecture

Geographic behavior is split between:

```text
@whiteslove/parsing-lexicon
```

and:

```text
@whiteslove/geo-catalog
```

with Flat Finder consuming both.

The three responsibilities are:

```text
"What does this geographic phrase mean?"
    → parsing lexicon

"What canonical place is this, where is it, and what is it related to?"
    → geo catalog

"What should Flat Finder do with this place?"
    → Flat Finder
```

---

# 14. The lexicon understands geographic language

The lexicon is responsible for interpreting geographic references appearing
inside human-written listing text.

Examples:

```text
Чиланзар
Чиланзаре
Chilanzar
Chilonzor
Чилонзор
Ц1
м. Ойбек
рядом с Magic City
возле метро Космонавтов
```

This includes, where supported:

* textual city references;
* textual district references;
* neighborhood names;
* microdistrict references;
* residential complex names;
* streets;
* landmarks;
* metro stations;
* transit references;
* spelling variants;
* grammatical forms;
* abbreviations;
* transliterations;
* multilingual variants;
* colloquial names;
* textual relations such as "near", "opposite", "next to", etc.

Determining that text refers to a location is a language-understanding problem.

Do not create a separate geographic text parser inside Flat Finder.

---

# 15. `@whiteslove/geo-catalog` owns canonical geography

Canonical geographic knowledge belongs in:

```text
@whiteslove/geo-catalog
```

not in Flat Finder and not in the parsing lexicon.

The geo catalog is the source of truth for structured geographic entities.

This includes, where available:

* countries;
* regions / provinces;
* cities;
* districts;
* neighborhoods;
* microdistricts;
* residential areas;
* residential complexes;
* streets;
* landmarks;
* metro / transit entities;
* canonical geographic IDs;
* `geoId`;
* canonical names;
* geographic entity types;
* parent-child relationships;
* geographic hierarchy;
* aliases that are properties of canonical places;
* latitude;
* longitude;
* canonical coordinates;
* centroid / representative coordinates;
* bounding boxes;
* polygons;
* boundaries;
* location metadata;
* coverage data exposed by the package.

Flat Finder must not create a parallel canonical geographic catalog.

---

# 16. Coordinates belong in `geo-catalog`

Canonical coordinates of known geographic entities are shared geographic
knowledge.

They must live in:

```text
@whiteslove/geo-catalog
```

where applicable.

This includes coordinates for entities such as:

* cities;
* districts;
* neighborhoods;
* microdistricts;
* residential complexes;
* landmarks;
* metro stations;
* other supported canonical places.

Do not create local coordinate maps such as:

```js
const DISTRICT_COORDINATES = {
  chilanzar: [41.275, 69.205],
  yunusabad: [41.365, 69.289],
};
```

or:

```js
const CITY_CENTERS = {
  tashkent: {
    lat: 41.31,
    lon: 69.24,
  },
};
```

inside Flat Finder when these coordinates represent canonical geography.

If a canonical coordinate is missing, that is a geo-catalog gap.

Fix the geo package and bump the Flat Finder dependency.

Do not introduce permanent local coordinate fallbacks.

---

# 17. Listing coordinates are different from canonical coordinates

A distinction must be maintained between:

## Canonical geographic coordinates

Example:

```text
coordinates of Chilanzar district
coordinates of Kropyvnytskyi city
coordinates of a known microdistrict
coordinates of Magic City
coordinates of a metro station
```

These belong in:

```text
@whiteslove/geo-catalog
```

## Listing-specific coordinates

Example source data:

```json
{
  "latitude": 41.311081,
  "longitude": 69.240562
}
```

These represent the particular listing.

Flat Finder may:

* validate them;
* normalize numeric representation;
* store them;
* use them for distance calculations;
* compare them to geo-catalog entities.

This is application/source data, not canonical geo-catalog data.

Do not automatically turn listing coordinates into canonical entity
coordinates.

---

# 18. Raw coordinate parsing

If a known source field contains:

```text
41.311081,69.240562
```

Flat Finder may locally parse it as a machine-oriented coordinate format.

It may validate:

```text
-90 <= latitude <= 90
-180 <= longitude <= 180
```

This does not violate the parsing rule because the task is validation of a
known machine-oriented format, not semantic interpretation of arbitrary
listing prose.

However, extracting coordinates from arbitrary human-written prose should be
treated according to shared parsing ownership rather than implemented as an
ad-hoc application parser.

---

# 19. Canonical geographic identity belongs in `geo-catalog`

Flat Finder should reference canonical locations using shared geographic
identity, preferably through `geoId` or equivalent public identifiers exposed
by:

```text
@whiteslove/geo-catalog
```

Conceptually prefer:

```js
{
  listingId: "...",
  geoId: "uz:tashkent:chilanzar"
}
```

over creating a separate Flat Finder canonical district identity.

Flat Finder database records may of course have their own primary keys.

But they should reference shared canonical geographic identity where
appropriate rather than redefining what a city/district/neighborhood is.

---

# 20. Do not map parsed locations to duplicate Flat Finder geography

Avoid architecture such as:

```text
parsed "Chilanzar"
       ↓
Flat Finder custom district registry
       ↓
hard-coded coordinates
```

Prefer:

```text
listing text
    ↓
@whiteslove/parsing-lexicon
    ↓
recognized location
    ↓
@whiteslove/geo-catalog
    ↓
canonical geo entity / geoId
coordinates
hierarchy
metadata
    ↓
Flat Finder
```

Flat Finder should reference or persist the shared geographic identity rather
than maintaining an independent canonical location catalog.

---

# 21. Geographic aliases

Geographic aliases sit close to the boundary between language and geography.

Use this distinction:

```text
"What geographic entity does this human-written phrase refer to?"
    → parsing lexicon

"What names/aliases are associated with this canonical geographic entity?"
    → geo catalog
```

The geo catalog may expose entity aliases as data.

The lexicon may consume shared geographic vocabulary or use its own language
rules to recognize those aliases in text.

Flat Finder must not maintain its own broad district/city alias dictionary.

Where possible, shared packages should avoid maintaining independent copies of
the same geographic vocabulary.

---

# 22. Geographic hierarchy

Relationships between places belong in the geo catalog.

Examples:

```text
country
  └── region
      └── city
          └── district
              └── microdistrict
```

or:

```text
city
  └── district
      └── residential complex
```

Where supported, relationships such as:

* belongsTo;
* parent;
* children;
* containedIn;
* adjacent location metadata;
* administrative hierarchy;

should come from `@whiteslove/geo-catalog`.

Flat Finder should consume these relationships rather than reconstructing
them through local dictionaries.

---

# 23. Geographic boundaries and spatial metadata

When available, shared geographic data such as:

* bounding boxes;
* polygons;
* centroids;
* representative points;
* administrative boundaries;

belongs in `@whiteslove/geo-catalog`.

Flat Finder may use those values for product features such as:

* radius search;
* point-in-polygon matching;
* determining likely district from listing coordinates;
* map display;
* viewport calculation;
* proximity ranking.

The data is shared geography.

The product decision using that data is Flat Finder responsibility.

---

# 24. Distance calculations

Canonical coordinates belong to the geo catalog.

Flat Finder may use them to calculate:

* listing → landmark distance;
* listing → metro distance;
* listing → district center distance;
* listing → city center distance;
* radius filters;
* proximity ranking;
* search scoring.

Example:

```js
const metro = geoCatalog.getById(metroGeoId);

const distance = calculateDistance(
  listing.coordinates,
  metro.coordinates,
);
```

The distance formula may remain local product/domain logic unless an existing
shared geo utility already provides it.

Do not duplicate canonical coordinates merely to simplify local distance
calculation.

---

# 25. Geographic examples

## District mentioned in text

Input:

```text
Квартира на Чиланзаре
```

Responsibilities:

```text
Recognize "Чиланзаре" as geographic language
    → @whiteslove/parsing-lexicon

Resolve to canonical Chilanzar entity
    → @whiteslove/geo-catalog

Canonical geoId
    → @whiteslove/geo-catalog

Coordinates
    → @whiteslove/geo-catalog

Parent city / hierarchy
    → @whiteslove/geo-catalog

Decide whether Flat Finder supports that location
    → Flat Finder

Persist/reference geoId
    → Flat Finder

Use it for filters/matching/UI
    → Flat Finder
```

## Landmark

Input:

```text
рядом с Magic City
```

Responsibilities:

```text
Recognize geographic reference
    → @whiteslove/parsing-lexicon

Resolve Magic City canonical entity
    → @whiteslove/geo-catalog

Get coordinates
    → @whiteslove/geo-catalog

Calculate listing distance
    → Flat Finder

Use distance in ranking
    → Flat Finder
```

## Coordinates supplied by source

Input:

```json
{
  "lat": 41.302,
  "lng": 69.235
}
```

Responsibilities:

```text
Validate coordinate ranges
    → Flat Finder source adapter/schema

Store listing coordinates
    → Flat Finder

Determine nearby canonical entities
    → Flat Finder using @whiteslove/geo-catalog data/APIs

Canonical district coordinates
    → @whiteslove/geo-catalog
```

---

# 26. Geo-catalog gaps

When geographic data is missing, treat the issue as a geo-catalog gap when
the missing information is reusable canonical geography.

Examples:

* missing city;
* missing district;
* missing neighborhood;
* missing microdistrict;
* missing residential complex;
* missing landmark;
* missing metro station;
* missing canonical coordinate;
* incorrect coordinate;
* missing parent relationship;
* incorrect hierarchy;
* missing canonical name;
* missing alias;
* missing boundary;
* incomplete geographic coverage.

Required workflow:

1. Verify the data is actually absent or incorrect.
2. Update `@whiteslove/geo-catalog`.
3. Add/update catalog tests or validation.
4. Verify hierarchy.
5. Verify coordinates where applicable.
6. Verify canonical IDs.
7. Release/bump the geo package.
8. Update Flat Finder's dependency pin and lockfile.
9. Consume the shared data in Flat Finder.
10. Do not leave a permanent local fallback.

A local Flat Finder coordinate/district patch is not a complete fix for a
shared geography gap.

---

# 27. Parsing-lexicon gaps

When generic semantic parsing is missing:

1. Reproduce the failing listing text.
2. Inspect existing public lexicon exports.
3. Verify that functionality is actually absent.
4. Add or extend the parser in `@whiteslove/parsing-lexicon`.
5. Add parser tests.
6. Include negative/false-positive cases.
7. Export behavior through the public package API.
8. Release the package.
9. Bump the Flat Finder dependency.
10. Verify the lockfile/resolved version.
11. Update Flat Finder integration tests.

Do not patch around a lexicon gap with a local semantic regex.

---

# 28. Public APIs only

Flat Finder should consume public package APIs.

Do not import private package internals.

Bad:

```js
import parseArea from
  "@whiteslove/parsing-lexicon/src/internal/area.js";
```

Bad:

```js
import tashkentDistricts from
  "@whiteslove/geo-catalog/src/data/tashkent.js";
```

Prefer public exports:

```js
import {
  parseHousingListingEnrichment,
} from "@whiteslove/parsing-lexicon";
```

and public geo-catalog resolution/query APIs.

The exact export names may evolve, but package boundaries must remain intact.

---

# 29. Dependency versions are part of the fix

Changes in shared packages are not complete until Flat Finder actually uses
the version containing them.

Always verify:

* package version;
* `package.json`;
* dependency pin/range;
* lockfile;
* actual resolved version;
* workspace behavior;
* CI behavior;
* production build behavior.

A lexicon or geo-catalog fix existing only in its source repository is not yet
a Flat Finder fix.

---

# 30. Confidence and ambiguity

Semantic parsing may return incomplete or uncertain information.

Do not compensate by adding aggressive local fallback regexes.

Flat Finder should handle uncertainty through:

* parser confidence;
* source reliability;
* structured source fields;
* precedence rules;
* conflict resolution;
* omission of uncertain values;
* manual review where applicable;
* fallback UI behavior.

A missing value is preferable to a confidently incorrect field inferred by an
unsafe local parser.

---

# 31. False positives matter

Parsing changes must be evaluated for false positives.

Patterns such as:

```text
12
100
2/3
40
```

may represent:

* room count;
* floor;
* area;
* price;
* building number;
* apartment number;
* date;
* phone fragment;
* ID.

Do not add a broad regex merely because it fixes one listing.

Shared parser tests should include ambiguous and negative cases.

---

# 32. Prefer deterministic parsing for deterministic concepts

For concepts such as:

* explicit floor notation;
* explicit area notation;
* explicit room count;
* explicit commission;
* explicit price;
* explicit currency;

prefer deterministic shared parsing where practical.

Do not introduce LLM inference as a hidden replacement for well-defined
lexicon behavior.

If LLM enrichment is introduced, define explicitly:

* precedence;
* confidence;
* conflict behavior;
* fallback behavior;
* whether output is advisory or authoritative.

---

# 33. Avoid duplicated derived fields

Do not independently derive the same semantic field across several modules.

Avoid:

```text
listing-enrichment.js
telegram-import.js
matching.js
search-normalizer.js
```

all independently parsing commission, district, area, or room-share from raw
text.

Parse/resolve once at the appropriate boundary and pass normalized structured
data downstream.

Prefer:

```js
if (listing.enrichment.roomShare) {
  // ...
}
```

over:

```js
if (/подселение|roommate|.../.test(listing.description)) {
  // ...
}
```

---

# 34. Raw text should have a limited lifetime

Raw listing text is expected near ingestion and enrichment boundaries.

Downstream modules should increasingly operate on structured data.

Preferred architecture:

```text
ingestion
    ↓
raw source listing
    ↓
lexicon parsing
    ↓
geo resolution
    ↓
normalized listing
    ↓
policy
    ↓
matching / ranking / search
    ↓
persistence / UI
```

If ranking, search, UI, or matching code starts running semantic regexes over
raw descriptions, reconsider the design.

---

# 35. Tests should enforce ownership

## Parsing-lexicon tests

Test language understanding.

Example:

```text
input listing text
        ↓
expected semantic output
```

Cases include:

* multilingual commission;
* audience restrictions;
* floor syntax;
* area syntax;
* room-share;
* address wording;
* geographic textual references;
* aliases/transliterations;
* negative cases.

## Geo-catalog tests

Test canonical geographic data.

Examples:

* canonical entity exists;
* `geoId` is stable/valid;
* parent relationship is correct;
* coordinates are present;
* latitude/longitude are valid;
* aliases map correctly;
* hierarchy is valid;
* duplicate entities do not exist;
* coverage meets package expectations.

## Flat Finder tests

Test application behavior.

Examples:

* lexicon result maps correctly to DB fields;
* parsed location resolves to expected `geoId`;
* listing coordinates are preserved;
* shared coordinates are used for proximity;
* source data wins according to precedence rules;
* safety policy consumes parsed fields;
* match score behaves correctly;
* unsupported locations are handled according to product policy.

Do not duplicate entire lexicon or geo-catalog test suites in Flat Finder.

---

# 36. AI contributor rule: search before implementing

AI agents must not assume that adding a local helper is the appropriate
smallest fix.

Before implementing any parsing or geographic change:

1. Search Flat Finder for the relevant field.
2. Inspect `backend/src/listing-enrichment.js`.
3. Inspect current imports from `@whiteslove/parsing-lexicon`.
4. Inspect current imports from `@whiteslove/geo-catalog`.
5. Inspect public package exports.
6. Determine whether the requirement is:

  * generic semantic parsing;
  * canonical geographic data;
  * source-specific parsing;
  * product normalization;
  * product policy;
  * persistence;
  * ranking/matching/search.
7. Implement it at the correct layer.

A correct two-package change is preferable to an architecturally incorrect
one-file patch.

---

# 37. AI contributor rule: do not assume missing functionality

If Flat Finder is not currently using a parser or geo-catalog feature, do not
assume the shared package lacks it.

Check public exports and package data first.

The application may simply not consume existing shared functionality yet.

Do not reproduce behavior merely because the current Flat Finder module does
not import it.

---

# 38. AI contributor rule: preserve boundaries during refactors

Refactors must preserve ownership boundaries even when:

* splitting enrichment modules;
* adding workers/queues;
* adding source adapters;
* introducing TypeScript;
* migrating frameworks;
* changing schemas;
* moving persistence code;
* adding AI enrichment;
* changing ingestion architecture.

Generic housing-language understanding remains in the lexicon.

Canonical geography remains in the geo catalog.

Product behavior remains in Flat Finder.

---

# 39. Prohibited Flat Finder patterns

Unless explicitly documented as a narrow source-specific exception, do not add:

```js
const SOME_SEMANTIC_KEYWORDS = [...];
```

Do not add:

```js
const DISTRICT_ALIASES = {...};
```

as a parallel generic geographic vocabulary.

Do not add:

```js
const DISTRICT_COORDINATES = {...};
```

for canonical locations.

Do not add:

```js
if (/human-language-pattern/i.test(description)) {
  // infer semantic meaning
}
```

Do not add:

```js
if (!lexiconResult.someField) {
  // generic local fallback parser
}
```

Do not add:

```js
description.includes("semantic keyword")
```

for generic housing-language classification.

Do not hide equivalent behavior inside vaguely named utilities such as:

```text
normalizeDescription
extractExtraDetails
inferMetadata
detectListingFeatures
fixMissingFields
resolveLocationFallback
```

Ownership is determined by behavior, not function name.

---

# 40. Acceptable Flat Finder patterns

Expected patterns include:

```js
const enrichment =
  parseHousingListingEnrichment(description);
```

```js
const geoEntity =
  resolveGeoEntity(enrichment.location);
```

```js
const listing =
  normalizeLexiconAndGeoResult({
    enrichment,
    geoEntity,
  });
```

```js
const allowed =
  applyListingSafetyPolicy(listing);
```

```js
const sourceLayout =
  parseSourceSpecificCompactLayout(rawSourceValue);
```

```js
const sourceData =
  SourceListingSchema.parse(payload);
```

```js
const distance =
  calculateDistance(
    listing.coordinates,
    geoEntity.coordinates,
  );
```

---

# 41. Ownership matrix

| Requirement                                              | Owner                                       |
| -------------------------------------------------------- | ------------------------------------------- |
| Recognize `без комиссии`                                 | `@whiteslove/parsing-lexicon`               |
| Recognize Uzbek equivalent of no commission              | `@whiteslove/parsing-lexicon`               |
| Extract `65 m²`                                          | `@whiteslove/parsing-lexicon`               |
| Interpret contextual `4/9` floor syntax                  | `@whiteslove/parsing-lexicon`               |
| Recognize room-share wording                             | `@whiteslove/parsing-lexicon`               |
| Recognize `Чиланзаре` as a location reference            | `@whiteslove/parsing-lexicon`               |
| Interpret multilingual/transliterated geographic wording | `@whiteslove/parsing-lexicon`               |
| Canonical Chilanzar entity                               | `@whiteslove/geo-catalog`                   |
| Canonical `geoId`                                        | `@whiteslove/geo-catalog`                   |
| City/district hierarchy                                  | `@whiteslove/geo-catalog`                   |
| City coordinates                                         | `@whiteslove/geo-catalog`                   |
| District coordinates                                     | `@whiteslove/geo-catalog`                   |
| Microdistrict coordinates                                | `@whiteslove/geo-catalog`                   |
| Residential complex coordinates                          | `@whiteslove/geo-catalog`                   |
| Landmark coordinates                                     | `@whiteslove/geo-catalog`                   |
| Metro coordinates                                        | `@whiteslove/geo-catalog`                   |
| Canonical boundaries/polygons                            | `@whiteslove/geo-catalog`                   |
| Parse numeric `lat/lng` from source API                  | Flat Finder source adapter                  |
| Store exact listing coordinates                          | Flat Finder                                 |
| Reference canonical location by `geoId`                  | Flat Finder consuming `geo-catalog`         |
| Determine supported markets/cities                       | Flat Finder                                 |
| Decide source-field precedence                           | Flat Finder                                 |
| Calculate listing match score                            | Flat Finder                                 |
| Decide whether proximity affects ranking                 | Flat Finder                                 |
| Calculate product-specific radius/distance               | Flat Finder/shared geo utility if available |
| Map semantic values to DB schema                         | Flat Finder                                 |
| Apply safety policy                                      | Flat Finder                                 |
| Deduplicate listings                                     | Flat Finder                                 |
| Parse source-only compact layout syntax                  | Flat Finder, narrow exception               |
| Validate UUID/API URL/timestamp                          | Flat Finder                                 |

---

# 42. When modifying `listing-enrichment.js`

Before committing a change, verify:

* no new generic housing-language regex was added;
* no new multilingual semantic keyword array was added;
* no geographic canonical dictionary was added;
* no canonical coordinate map was added;
* no lexicon behavior was duplicated;
* no geo-catalog data was duplicated;
* generic parsing uses public lexicon APIs;
* canonical geographic data uses public geo-catalog APIs;
* local parsing supplements are genuinely source/product-specific;
* local exceptions contain explanatory comments;
* product policy works over structured data;
* dependency versions were bumped where required;
* tests live at the correct architectural layer.

---

# 43. Definition of done for parsing-related fixes

A parsing fix is complete only when applicable items below are satisfied:

* semantic behavior has the correct owner;
* generic parsing changes exist in `@whiteslove/parsing-lexicon`;
* lexicon tests cover the behavior;
* false positives were considered;
* multilingual implications were considered;
* public package exports expose the behavior;
* a released/pinned package version contains the change;
* Flat Finder actually resolves that package version;
* no duplicate local fallback parser was introduced;
* Flat Finder integration behavior is tested.

A locally passing Flat Finder test is not sufficient if the implementation
violates ownership boundaries.

---

# 44. Definition of done for geography-related fixes

A geographic fix is complete only when applicable items below are satisfied:

* canonical geographic data has the correct owner;
* missing canonical entities are added to `@whiteslove/geo-catalog`;
* canonical coordinates live in the geo catalog;
* hierarchy is correct;
* `geoId`/canonical IDs are valid;
* aliases are stored/handled at the correct shared layer;
* catalog tests/validation pass;
* Flat Finder pins a geo-catalog version containing the change;
* Flat Finder references the shared entity rather than duplicating it;
* no permanent local coordinate fallback was introduced;
* listing-specific coordinates remain distinct from canonical entity
  coordinates;
* integration behavior is tested.

---

# 45. Core architecture rule

There must be one reusable source of truth for each responsibility.

```text
@whiteslove/parsing-lexicon
    understands listing language

@whiteslove/geo-catalog
    understands canonical geography

Flat Finder
    understands product behavior
```

Or, as a decision rule:

```text
"What does this text mean?"
    → @whiteslove/parsing-lexicon

"What place is this, where is it, and what belongs to it?"
    → @whiteslove/geo-catalog

"What should the application do with it?"
    → Flat Finder
```

If a proposed Flat Finder change starts teaching `backend/src` new reusable
housing vocabulary, move it to the lexicon.

If it starts teaching Flat Finder canonical places, coordinates, geographic
hierarchy, or shared location identity, move it to the geo catalog.

Flat Finder should consume those shared capabilities rather than duplicate
them.
