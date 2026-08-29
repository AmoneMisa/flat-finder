import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/filters.dart';
import '../models/search_statistics.dart';
import '../services/api_service.dart';
import '../state/settings.dart';

class StatsSheet extends StatefulWidget {
  const StatsSheet({super.key, required this.api, required this.filters});
  final ApiService api;
  final Filters filters;

  @override
  State<StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends State<StatsSheet> {
  late Future<SearchStatistics?> _future;
  int _activityDays = 14;
  String _dealScope = 'longRent';
  String _geoDimension = 'city';

  static const _bandColors = <String, Color>{
    'green': Color(0xff4ade80),
    'blue': Color(0xff67e8f9),
    'pink': Color(0xffe0679a),
    'orange': Color(0xfffb923c),
    'yellow': Color(0xfffacc15),
    'red': Color(0xffef4444),
  };

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchSearchStatistics(widget.filters);
  }

  String _dealLabel(AppStrings s, String key) => switch (key) {
    'sale' => s.t('sale'),
    'longRent' => s.t('longTerm'),
    'shortRent' => s.t('shortTerm'),
    'roomRent' => s.t('roomOnly'),
    _ => key,
  };

  String _geoLabel(AppStrings s, String key) => switch (key) {
    'country' => s.t('country'),
    'city' => s.t('city'),
    'district' => s.t('district'),
    'microdistrict' => s.t('microdistrict'),
    'metro' => s.t('metro'),
    _ => key,
  };

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .88,
      maxChildSize: .96,
      builder: (context, scroll) => FutureBuilder<SearchStatistics?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snapshot.data;
          return stats == null
              ? Center(child: Text(settings.t('statsUnavailable')))
              : _content(scroll, stats, settings);
        },
      ),
    );
  }

  Widget _content(
    ScrollController scroll,
    SearchStatistics stats,
    SettingsState settings,
  ) {
    final s = settings.s;
    final number = NumberFormat.decimalPattern(settings.lang);
    String money(double? usd) => usd == null
        ? s.t('notSpecified')
        : '${number.format(usd.round())} ${stats.currency}';
    final cutoff = DateTime.now().subtract(Duration(days: _activityDays));
    final activity = stats.activity
        .where((row) => row.date.isAfter(cutoff))
        .toList();
    final scopedGeo = stats.geographiesByDeal[_dealScope]?[_geoDimension];
    final geography =
        (scopedGeo?.isNotEmpty == true
                ? scopedGeo!
                : stats.geographies[_geoDimension] ?? const <GeoStat>[])
            .take(8)
            .toList();
    final bands = stats.priceBandsByDeal[_dealScope] ?? const <PriceBandStat>[];

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
      children: [
        const Center(child: SizedBox(width: 42, child: Divider(thickness: 4))),
        Text(
          s.t('statistics'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(s.t('statsTotalN', {'n': number.format(stats.total)})),
        const SizedBox(height: 16),
        _card(
          s.t('statsActivity'),
          trailing: _segments<int>(
            [7, 14, 21],
            _activityDays,
            (v) => '$v',
            (v) => setState(() => _activityDays = v),
          ),
          child: SizedBox(
            height: 150,
            child: activity.isEmpty
                ? Center(child: Text(s.t('statsNoData')))
                : CustomPaint(
                    painter: _LineChartPainter(
                      activity.map((e) => e.count.toDouble()).toList(),
                      const Color(0xff24a7d6),
                    ),
                  ),
          ),
        ),
        _card(
          s.t('statsDeals'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final deal in stats.dealTypes)
                SizedBox(
                  width: 148,
                  child: _metric(
                    _dealLabel(s, deal.key),
                    number.format(deal.count),
                    '${s.t('statsMedian')}: ${money(deal.medianUsd)}',
                  ),
                ),
            ],
          ),
        ),
        if (bands.isNotEmpty)
          _card(
            s.t('statsPriceBands'),
            trailing: _dealSegments(stats, s),
            child: _BarList([
              for (final key in const [
                'green',
                'blue',
                'pink',
                'orange',
                'yellow',
                'red',
              ])
                _BarRow(
                  s.t('priceBand_$key'),
                  bands
                      .where((r) => r.key == key)
                      .fold(0, (sum, row) => sum + row.count),
                  _bandColors[key]!,
                ),
            ]),
          ),
        _card(
          s.t('statsGeography'),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _dealSegments(stats, s),
              const SizedBox(height: 6),
              _segments<String>(
                const ['country', 'city', 'district', 'microdistrict', 'metro'],
                _geoDimension,
                (v) => _geoLabel(s, v),
                (v) => setState(() => _geoDimension = v),
              ),
            ],
          ),
          child: geography.isEmpty
              ? Text(s.t('statsNoData'))
              : _BarList([
                  for (final row in geography)
                    _BarRow(
                      row.label,
                      row.count,
                      const Color(0xff24a7d6),
                      subtitle:
                          '${s.t('statsMedian')}: ${money(row.medianUsd)}',
                    ),
                ]),
        ),
        _card(
          s.t('statsOwnership'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric(
                s.t('privateOwner'),
                number.format(stats.ownership.owners),
              ),
              _metric(s.t('agency'), number.format(stats.ownership.agencies)),
              _metric(
                s.t('noCommission'),
                number.format(stats.ownership.noCommission),
              ),
              _metric(
                s.t('commission'),
                number.format(stats.ownership.commission),
              ),
            ],
          ),
        ),
        _card(
          s.t('statsDataQuality'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric(s.t('statsVisible'), number.format(stats.total)),
              _metric(
                s.t('statsDuplicates'),
                number.format(stats.quality.duplicatesRejected),
              ),
              _metric(
                s.t('statsFake'),
                number.format(stats.quality.suspectedFake),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dealSegments(SearchStatistics stats, AppStrings s) {
    final values = stats.dealTypes
        .where((e) => e.count > 0)
        .map((e) => e.key)
        .toList();
    if (values.isEmpty) return const SizedBox.shrink();
    final selected = values.contains(_dealScope) ? _dealScope : values.first;
    return _segments<String>(
      values,
      selected,
      (v) => _dealLabel(s, v),
      (v) => setState(() => _dealScope = v),
    );
  }

  Widget _segments<T extends Object>(
    List<T> values,
    T selected,
    String Function(T) label,
    ValueChanged<T> onChanged,
  ) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<T>(
      segments: [
        for (final v in values) ButtonSegment(value: v, label: Text(label(v))),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (values) => onChanged(values.first),
    ),
  );

  Widget _card(String title, {Widget? trailing, required Widget child}) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              if (trailing != null) Flexible(flex: 2, child: trailing),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );

  Widget _metric(String label, String value, [String? detail]) => Container(
    constraints: const BoxConstraints(minWidth: 130),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: const Color(0xffe0679a)),
        ),
        if (detail != null)
          Text(detail, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _BarRow {
  const _BarRow(this.label, this.value, this.color, {this.subtitle});
  final String label;
  final int value;
  final Color color;
  final String? subtitle;
}

class _BarList extends StatelessWidget {
  const _BarList(this.rows);
  final List<_BarRow> rows;
  @override
  Widget build(BuildContext context) {
    final maxValue = math.max(
      1,
      rows.fold<int>(0, (m, r) => math.max(m, r.value)),
    );
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(row.label)),
                    Text('${row.value}'),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: row.value / maxValue,
                    color: row.color,
                    backgroundColor: row.color.withValues(alpha: .12),
                  ),
                ),
                if (row.subtitle != null)
                  Text(
                    row.subtitle!,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = math.max(1.0, values.reduce(math.max));
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * i / (values.length - 1);
      final y = size.height - values[i] / maxValue * (size.height - 8) - 4;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) => old.values != values;
}
