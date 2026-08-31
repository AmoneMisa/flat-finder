export function olxSegmentDealType(segment) {
  if (segment === 'flat:sale') return 'sale';
  if (segment === 'flat:longRent') return 'longRent';
  if (segment === 'flat:shortRent') return 'shortRent';
  if (segment === 'flat:ownerRent') return 'longRent';
  return null;
}
