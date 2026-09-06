export 'api_service_base.dart' hide ApiService;

import '../models/filters.dart';
import '../models/map_listing_point.dart';
import 'api_service_base.dart' as base;

/// Public transport facade.
///
/// Geographic result membership belongs to the backend/database. The legacy
/// transport implementation still calls `Filters.toUpstreamQueryParams()`,
/// which intentionally used to strip multi-station metro filters and the
/// directional arc so Flutter could post-filter a returned page. Wrap the
/// request filter here so every selected station, radius and arc is sent to the
/// backend while the rest of the mature transport/cache implementation remains
/// unchanged.
class ApiService extends base.ApiService {
  ApiService({String? baseUrl}) : super(baseUrl: baseUrl);

  @override
  Future<base.ListingsResult> fetchListings(
    Filters filters, {
    bool force = false,
    String? cursor,
  }) =>
      super.fetchListings(
        _BackendOwnedGeoFilters(filters),
        force: force,
        cursor: cursor,
      );

  @override
  Future<List<MapListingPoint>> fetchMapListings(Filters filters) =>
      super.fetchMapListings(_BackendOwnedGeoFilters(filters));
}

/// Minimal request proxy: ApiService only reads query/customSources/sort from
/// the filter object outside serialization. The actual query parameter map is
/// delegated to the original filter's complete deep-link serializer, which now
/// doubles as the canonical backend contract for geo filters.
class _BackendOwnedGeoFilters extends Filters {
  _BackendOwnedGeoFilters(this.source)
      : super(
          query: source.query,
          customSources: source.customSources,
          sort: source.sort,
        );

  final Filters source;

  @override
  Map<String, String> toUpstreamQueryParams() => source.toQueryParams();
}
