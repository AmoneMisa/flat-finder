from pathlib import Path


def replace_once(text, old, new, label):
    if old not in text:
        raise RuntimeError(f'missing patch anchor: {label}')
    return text.replace(old, new, 1)

path = Path('backend/src/normalize.js')
text = path.read_text()
text = replace_once(
    text,
    "  parseHousingOccupancyType,\n  parseLexiconAddress,\n  parseLexiconDealType,",
    "  parseHousingIntent,\n  parseHousingOccupancyType,\n  parseHousingSemanticContext,\n  parseLexiconAddress,\n  parseLexiconDealType,",
    'normalize imports',
)
text = replace_once(
    text,
    "  const rooms = partial.rooms != null ? Number(partial.rooms) : parseRoomsFromText(combined);\n  const parsedDealType = parseLexiconDealType(combined) ?? classifyDealType(combined);",
    "  const rooms = partial.rooms != null ? Number(partial.rooms) : parseRoomsFromText(combined);\n  const housingIntent = parseHousingIntent(combined);\n  const housingContext = parseHousingSemanticContext(combined);\n  const housingAction = partial.housingAction ?? partial.action ?? housingIntent?.action ?? null;\n  const listingKind = partial.listingKind ?? housingIntent?.listingKind ?? 'propertyOffer';\n  const parsedDealType = housingIntent?.dealType ?? parseLexiconDealType(combined) ?? classifyDealType(combined);",
    'intent context',
)
text = replace_once(
    text,
    "    description,\n    dealType,\n    occupancyType,",
    "    description,\n    housingAction,\n    listingKind,\n    dealType,\n    occupancyType,",
    'intent result fields',
)
text = replace_once(
    text,
    "    furnished,\n    condition: partial.condition ?? null,\n    amenities,",
    "    furnished,\n    furnitureState: partial.furnitureState ?? housingContext.furniture ?? null,\n    condition: partial.condition ?? housingContext.condition ?? null,\n    propertyCondition: partial.propertyCondition ?? housingContext.condition ?? null,\n    layoutTypes: Array.isArray(partial.layoutTypes) ? partial.layoutTypes : [...housingContext.layouts],\n    buildingType: partial.buildingType ?? housingContext.buildingType ?? null,\n    buildingStatus: partial.buildingStatus ?? housingContext.buildingStatus ?? null,\n    priceContext: partial.priceContext ?? housingContext.priceContext ?? null,\n    priceModifiers: Array.isArray(partial.priceModifiers) ? partial.priceModifiers : [...housingContext.priceModifiers],\n    rentDuration: partial.rentDuration ?? housingContext.rentDuration ?? null,\n    floorConstraints: Array.isArray(partial.floorConstraints) ? partial.floorConstraints : [...housingContext.floorConstraints],\n    tenantPolicies: partial.tenantPolicies ?? housingContext.tenantPolicies,\n    documentStatus: Array.isArray(partial.documentStatus) ? partial.documentStatus : [...housingContext.documents],\n    financing: Array.isArray(partial.financing) ? partial.financing : [...housingContext.financing],\n    locationRelations: Array.isArray(partial.locationRelations) ? partial.locationRelations : [...housingContext.locationRelations],\n    availability: partial.availability ?? housingContext.availability ?? null,\n    listingStatus: partial.listingStatus ?? housingContext.listingStatus ?? 'active',\n    amenities,",
    'context result fields',
)
path.write_text(text)

# Property-wanted posts are valid parsed records, but Flat Finder's offer feed must not show them.
path = Path('backend/src/postgres-search.js')
text = path.read_text()
text = replace_once(
    text,
    "  const where = ['l.active = TRUE'];\n",
    "  const where = [\n    'l.active = TRUE',\n    `COALESCE(l.data->>'listingKind', 'propertyOffer') <> 'propertyWanted'`,\n    `COALESCE(l.data->>'listingStatus', 'active') NOT IN ('sold', 'rented', 'closed', 'outdated')`,\n  ];\n",
    'offer feed policy',
)
path.write_text(text)

Path('backend/test/housing-context-integration.test.js').write_text(r"""import test from 'node:test';
import assert from 'node:assert/strict';
import { makeListing } from '../src/normalize.js';

const base = {
  id: 'ctx-1',
  source: 'telegram',
  country: 'UZ',
  city: 'Tashkent',
  price: null,
  currency: 'USD',
  url: 'https://example.invalid/listing',
};

test('wanted purchase stays sale but is not an offer', () => {
  const listing = makeListing({ ...base, title: 'Куплю 2-комнатную квартиру в Ташкенте' });
  assert.equal(listing.housingAction, 'buy');
  assert.equal(listing.listingKind, 'propertyWanted');
  assert.equal(listing.dealType, 'sale');
});

test('short rent keeps transaction side and duration separate', () => {
  const listing = makeListing({ ...base, id: 'ctx-2', title: 'Сдам квартиру посуточно' });
  assert.equal(listing.housingAction, 'rentOut');
  assert.equal(listing.listingKind, 'propertyOffer');
  assert.equal(listing.dealType, 'shortRent');
});

test('housing context survives normalization as structured fields', () => {
  const listing = makeListing({
    ...base,
    id: 'ctx-3',
    title: 'Сдам квартиру',
    description: 'Новый ремонт. Без животных, с детьми можно. Ипотека возможна. Кадастр готов. Без торга.',
  });
  assert.equal(listing.propertyCondition, 'newRenovation');
  assert.equal(listing.tenantPolicies.pets, 'notAllowed');
  assert.equal(listing.tenantPolicies.children, 'allowed');
  assert.ok(listing.financing.includes('mortgageAllowed'));
  assert.ok(listing.documentStatus.includes('cadastralReady'));
  assert.ok(listing.priceModifiers.includes('fixed'));
});

test('explicit inactive status is preserved for downstream feed exclusion', () => {
  const listing = makeListing({ ...base, id: 'ctx-4', title: 'Квартира уже сдана' });
  assert.equal(listing.listingStatus, 'rented');
});
""")
