export function olxSegmentDealType(segment) {
  if (segment === 'flat:sale') return 'sale';
  if (segment === 'flat:longRent') return 'longRent';
  return null;
}
