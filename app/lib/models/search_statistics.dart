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
  final int priceCount;
  final double? minUsd;
  final double? maxUsd;

  const GeoStat({
    required this.label,
    required this.count,
    this.medianUsd,
    this.priceCount = 0,
    this.minUsd,
    this.maxUsd,
  });

  factory GeoStat.fromJson(Map<String, dynamic> j) => GeoStat(
    label: j['label']?.toString() ?? '',
    count: (j['count'] as num?)?.toInt() ?? 0,
    medianUsd: (j['medianUsd'] as num?)?.toDouble(),
    priceCount: (j['priceCount'] as num?)?.toInt() ?? 0,
    minUsd: (j['minUsd'] as num?)?.toDouble(),
    maxUsd: (j['maxUsd'] as num?)?.toDouble(),
  );
}

class PriceBandStat {
  final String key;
  final int count;
  const PriceBandStat({required this.key, required this.count});
  factory PriceBandStat.fromJson(Map<String, dynamic> j) => PriceBandStat(
    key: j['key']?.toString() ?? '',
    count: (j['count'] as num?)?.toInt() ?? 0,
  );
}

class ActivityStat {
  final DateTime date;
  final int count;
  const ActivityStat({required this.date, required this.count});
  factory ActivityStat.fromJson(Map<String, dynamic> j) => ActivityStat(
    date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime(1970),
    count: (j['count'] as num?)?.toInt() ?? 0,
  );
}

class QualityStat {
  final int duplicatesRejected;
  final int suspectedFake;
  const QualityStat({this.duplicatesRejected = 0, this.suspectedFake = 0});
  factory QualityStat.fromJson(Map<String, dynamic>? j) => QualityStat(
    duplicatesRejected: (j?['duplicatesRejected'] as num?)?.toInt() ?? 0,
    suspectedFake: (j?['suspectedFake'] as num?)?.toInt() ?? 0,
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
  final int rawTotal;
  final String currency;
  final List<DealTypeStat> dealTypes;
  final Map<String, List<GeoStat>>
  geographies; // by dimension: country/city/district/...
  final OwnershipStat ownership;
  final Map<String, Map<String, List<GeoStat>>> geographiesByDeal;
  final Map<String, List<PriceBandStat>> priceBandsByDeal;
  final Map<String, int> priceBandSamplesByDeal;
  final List<ActivityStat> activity;
  final QualityStat quality;

  const SearchStatistics({
    required this.total,
    required this.rawTotal,
    required this.currency,
    required this.dealTypes,
    required this.geographies,
    required this.ownership,
    required this.geographiesByDeal,
    required this.priceBandsByDeal,
    required this.priceBandSamplesByDeal,
    required this.activity,
    required this.quality,
  });

  factory SearchStatistics.fromJson(Map<String, dynamic> j) => SearchStatistics(
    total: (j['total'] as num?)?.toInt() ?? 0,
    rawTotal:
        (j['rawTotal'] as num?)?.toInt() ?? (j['total'] as num?)?.toInt() ?? 0,
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
    geographiesByDeal: ((j['geographiesByDeal'] as Map?) ?? const {}).map(
      (deal, dimensions) => MapEntry(
        deal.toString(),
        ((dimensions as Map?) ?? const {}).map(
          (dimension, rows) => MapEntry(
            dimension.toString(),
            ((rows as List?) ?? const [])
                .map((e) => GeoStat.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
        ),
      ),
    ),
    priceBandsByDeal: ((j['priceBandsByDeal'] as Map?) ?? const {}).map(
      (deal, rows) => MapEntry(
        deal.toString(),
        ((rows as List?) ?? const [])
            .map((e) => PriceBandStat.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
    ),
    priceBandSamplesByDeal: ((j['priceBandSamplesByDeal'] as Map?) ?? const {})
        .map(
          (deal, count) =>
              MapEntry(deal.toString(), (count as num?)?.toInt() ?? 0),
        ),
    activity: ((j['activity'] as List?) ?? const [])
        .map((e) => ActivityStat.fromJson(e as Map<String, dynamic>))
        .toList(),
    quality: QualityStat.fromJson(j['quality'] as Map<String, dynamic>?),
  );
}
