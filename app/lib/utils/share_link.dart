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

/// whiteslove.me's own flat-finder page, deep-linkable to one listing via
/// `?adv=<publicId>` (see app/pages/flat-finder/index.vue's
/// openSharedListingByPublicId). A normal https link: opens the site in a
/// browser when the app isn't installed, and — once Android App Links
/// verification is set up (see AndroidManifest.xml's autoVerify intent-
/// filter and the site's public/.well-known/assetlinks.json) — opens
/// straight into the app instead, no chooser prompt.
const kWebListingUrl = 'https://whiteslove.me/flat-finder';

String buildListingWebShareUrl(int publicId) =>
    Uri.parse(kWebListingUrl)
        .replace(queryParameters: {'adv': '$publicId'})
        .toString();

/// Decode a single-listing deep link into its `publicId` — accepts both our
/// own `flatfinder://listing?id=` scheme and the site's
/// `https://whiteslove.me/flat-finder?adv=` link (an Android App Link opens
/// the same way a custom-scheme link does). Null for anything else.
int? parseListingLink(Uri uri) {
  if (uri.scheme == kAppLinkScheme && uri.host == kListingLinkHost) {
    return int.tryParse(uri.queryParameters['id'] ?? '');
  }
  if (uri.scheme == 'https' &&
      uri.host == 'whiteslove.me' &&
      uri.path.startsWith('/flat-finder')) {
    return int.tryParse(uri.queryParameters['adv'] ?? '');
  }
  return null;
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
