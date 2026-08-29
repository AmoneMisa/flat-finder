import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/filters.dart';
import '../models/search_statistics.dart';
import '../services/api_service.dart';
import '../state/settings.dart';

/// Bottom sheet summarizing the current search: deal-type breakdown with
/// median prices, owner/agency split, and top districts/cities by listing
/// count. Fetched with `statsOnly` so it costs nothing beyond the aggregate
/// query already computed server-side.
class StatsSheet extends StatefulWidget {
  const StatsSheet({super.key, required this.api, required this.filters});

  final ApiService api;
  final Filters filters;

  @override
  State<StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends State<StatsSheet> {
  late Future<SearchStatistics?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchSearchStatistics(widget.filters);
  }

  String _dealLabel(AppStrings s, String key) => switch (key) {
        'sale' => s.t('sale'),
        'longRent' => s.t('longTerm'),
        'shortRent' => s.t('shortTerm'),
        _ => key,
      };

  String _geoDimensionLabel(AppStrings s, String key) => switch (key) {
        'district' => s.t('district'),
        'city' => s.t('city'),
        'metro' => s.t('metro'),
        'microdistrict' => s.t('quartal'),
        'country' => s.t('countries'),
        _ => key,
      };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>().s;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      builder: (context, scroll) => FutureBuilder<SearchStatistics?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snap.data;
          if (stats == null) {
            return Center(child: Text(s.t('statsUnavailable')));
          }
          final numberFmt = NumberFormat.decimalPattern();
          String money(double v) => '${numberFmt.format(v.round())} ${stats.currency}';
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(s.t('statistics'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                s.t('statsTotalN', {'n': stats.total.toString()}),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (stats.dealTypes.isNotEmpty) ...[
                Text(s.t('dealType'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final d in stats.dealTypes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(_dealLabel(s, d.key))),
                        Text('${d.count}'),
                        if (d.medianUsd != null) ...[
                          const SizedBox(width: 12),
                          Text(
                            money(d.medianUsd!),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
              ],
              Text(s.t('realEstateAgency'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(s.t('privateOwner'))),
                  Text('${stats.ownership.owners}'),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(s.t('realEstateAgency'))),
                    Text('${stats.ownership.agencies}'),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(child: Text(s.t('noCommission'))),
                  Text('${stats.ownership.noCommission}'),
                ],
              ),
              for (final entry in stats.geographies.entries)
                if (entry.value.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(_geoDimensionLabel(s, entry.key),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final g in entry.value.take(8))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(g.label)),
                          Text('${g.count}'),
                        ],
                      ),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }
}
