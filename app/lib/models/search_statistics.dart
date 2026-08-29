/// Aggregate statistics for the current search (backend's `includeStats`
/// response — see `statistics` in backend/src/postgres-search.js). Fields
/// the app doesn't currently render (price bands, activity, quality) are
/// intentionally left unparsed rather than half-modeled.
class DealTypeStat {
  final String key; // sale | longRent | shortRent
  final int count;
  final double? medianUsd;
  final double? averageUsd;
  final double? minUsd;
  final double? maxUsd;

  const DealTypeStat({
    required this.key,
    required this.count,
    this.medianUsd,
    this.averageUsd,
    this.minUsd,
    this.maxUsd,
  });

  factory DealTypeStat.fromJson(Map<String, dynamic> j) => DealTypeStat(
        key: j['key']?.toString() ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
        medianUsd: (j['medianUsd'] as num?)?.toDouble(),
        averageUsd: (j['averageUsd'] as num?)?.toDouble(),
        minUsd: (j['minUsd'] as num?)?.toDouble(),
        maxUsd: (j['maxUsd'] as num?)?.toDouble(),
      );
}

class GeoStat {
  final String label;
  final int count;
  final double? medianUsd;

  const GeoStat({required this.label, required this.count, this.medianUsd});

  factory GeoStat.fromJson(Map<String, dynamic> j) => GeoStat(
        label: j['label']?.toString() ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
        medianUsd: (j['medianUsd'] as num?)?.toDouble(),
      );
}

class OwnershipStat {
  final int owners;
  final int agencies;
  final int commission;
  final int noCommission;

  const OwnershipStat({
    required this.owners,
    required this.agencies,
    required this.commission,
    required this.noCommission,
  });

  factory OwnershipStat.fromJson(Map<String, dynamic>? j) => OwnershipStat(
        owners: (j?['owners'] as num?)?.toInt() ?? 0,
        agencies: (j?['agencies'] as num?)?.toInt() ?? 0,
        commission: (j?['commission'] as num?)?.toInt() ?? 0,
        noCommission: (j?['noCommission'] as num?)?.toInt() ?? 0,
      );
}

class SearchStatistics {
  final int total;
  final String currency;
  final List<DealTypeStat> dealTypes;
  final Map<String, List<GeoStat>> geographies; // by dimension: country/city/district/...
  final OwnershipStat ownership;

  const SearchStatistics({
    required this.total,
    required this.currency,
    required this.dealTypes,
    required this.geographies,
    required this.ownership,
  });

  factory SearchStatistics.fromJson(Map<String, dynamic> j) => SearchStatistics(
        total: (j['total'] as num?)?.toInt() ?? 0,
        currency: j['currency']?.toString() ?? 'USD',
        dealTypes: ((j['dealTypes'] as List?) ?? const [])
            .map((e) => DealTypeStat.fromJson(e as Map<String, dynamic>))
            .toList(),
        geographies: ((j['geographies'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(
            k.toString(),
            ((v as List?) ?? const [])
                .map((e) => GeoStat.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
        ),
        ownership: OwnershipStat.fromJson(j['ownership'] as Map<String, dynamic>?),
      );
}
