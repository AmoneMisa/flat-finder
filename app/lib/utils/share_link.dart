import '../models/filters.dart';

/// Custom URL scheme the app registers so a shared search opens Flat Finder.
/// Example link: `flatfinder://search?countries=RO&propertyType=flat`.
const kAppLinkScheme = 'flatfinder';
const kAppLinkHost = 'search';

/// Deep link to one specific listing by its stable `publicId` — mirrors the
/// site's `?adv=<publicId>` query param, since `source`+`id` alone isn't a
/// stable enough key to share (see Listing.publicId).
/// Example link: `flatfinder://listing?id=12345`.
const kListingLinkHost = 'listing';

String buildListingShareUrl(int publicId) {
  final uri = Uri(
    scheme: kAppLinkScheme,
    host: kListingLinkHost,
    queryParameters: {'id': '$publicId'},
  );
  return uri.toString();
}

/// Decode a single-listing deep link into its `publicId`; null for links
/// that aren't ours or aren't a listing link.
int? parseListingLink(Uri uri) {
  if (uri.scheme != kAppLinkScheme || uri.host != kListingLinkHost) return null;
  return int.tryParse(uri.queryParameters['id'] ?? '');
}

/// Build a shareable deep link that encodes a search. Opening it launches the
/// app (where the scheme is registered) with these filters applied.
String buildSearchUrl(Filters filters) {
  final params = Map<String, String>.from(filters.toQueryParams())
    ..remove('limit'); // server-only paging hint, not part of a shared search
  if (filters.sort != SortBy.relevance) params['sort'] = filters.sort.name;
  final uri = Uri(
    scheme: kAppLinkScheme,
    host: kAppLinkHost,
    queryParameters: params,
  );
  return uri.toString();
}

/// Decode one of our search deep links into [Filters]; returns null for links
/// that aren't ours (wrong scheme/host) so callers can ignore them.
Filters? parseSearchUrl(Uri uri) {
  if (uri.scheme != kAppLinkScheme) return null;
  if (uri.host.isNotEmpty && uri.host != kAppLinkHost) return null;
  return Filters.fromQueryParams(uri.queryParameters);
}
