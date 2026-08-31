import 'listing.dart';

/// Source listing ids are not globally unique. Country is part of the identity
/// as the same provider may reuse an id in different regional catalogs.
String listingKey(Listing listing) => listingKeyParts(
      source: listing.source,
      country: listing.country,
      id: listing.id,
    );

String listingKeyParts({
  required String source,
  required String country,
  required String id,
}) => '${source.toLowerCase()}:${country.toUpperCase()}:$id';

bool sameListing(Listing a, Listing b) => listingKey(a) == listingKey(b);
