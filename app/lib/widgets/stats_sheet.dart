import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/filters.dart';
import '../models/search_statistics.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
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
        'roomRent' => s.t('roomOnlyShort'),
        'unknown' => s.t('notSpecified'),
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

  String _localizedGeographyLabel(
    AppState state,
    AppStrings s,
    String dimension,
    String raw,
  ) {
    if (dimension == 'country') return s.countryName(raw, raw);
    final code = widget.filters.countries.isNotEmpty
        ? widget.filters.countries.first
        : '';
    final country = state.countryByCode(code);
    if (country == null) return raw;
    if (dimension == 'city') return country.cityLabel(raw);
    final city = widget.filters.city.trim();
    if (city.isNotEmpty) {
      return country.locationLabel(city, raw, kind: dimension);
    }
    return country.locationLabelAnyCity(raw, kind: dimension);
  }

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
    final appState = context.watch<AppState>();
    final number = NumberFormat.decimalPattern(settings.lang);
    final percent = NumberFormat.percentPattern(settings.lang)
      ..maximumFractionDigits = 1;
    final dealTotal = stats.dealTypes.fold<int>(
      0,
      (sum, row) => sum + row.count,
    );
    final ownershipTotal = stats.ownership.owners + stats.ownership.agencies;
    final commissionTotal =
        stats.ownership.commission + stats.ownership.noCommission;
    final rawQualityTotal = stats.rawTotal > 0 ? stats.rawTotal : stats.total;

    String metricWithPercent(int value, int total) =>
        '${number.format(value)} · ${percent.format(total <= 0 ? 0 : value / total)}';

    String money(double? usd) => usd == null
        ? s.t('notSpecified')
        : '${number.format(usd.round())} ${stats.currency}';
    final cutoff = DateTime.now().subtract(Duration(days: _activityDays));
    final activity =
        stats.activity.where((row) => row.date.isAfter(cutoff)).toList();
    const knownDealScopes = {'sale', 'longRent', 'shortRent', 'roomRent'};
    final dealScopes = stats.dealTypes
        .where((row) => row.count > 0 && knownDealScopes.contains(row.key))
        .map((row) => row.key)
        .toList();
    final effectiveDealScope = dealScopes.contains(_dealScope)
        ? _dealScope
        : (dealScopes.isNotEmpty ? dealScopes.first : null);
    final scopedGeo = effectiveDealScope == null
        ? null
        : stats.geographiesByDeal[effectiveDealScope]?[_geoDimension];
    final geography = (scopedGeo?.isNotEmpty == true
            ? scopedGeo!
            : stats.geographies[_geoDimension] ?? const <GeoStat>[])
        .take(8)
        .toList();
    final bands = effectiveDealScope == null
        ? const <PriceBandStat>[]
        : stats.priceBandsByDeal[effectiveDealScope] ?? const <PriceBandStat>[];

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
          trailing: _activityDayPills(),
          child: SizedBox(
            height: 190,
            width: double.infinity,
            child: activity.isEmpty
                ? Center(child: Text(s.t('statsNoData')))
                : CustomPaint(
                    size: Size.infinite,
                    painter: _LineChartPainter(
                      activity,
                      const Color(0xff24a7d6),
                      locale: settings.lang,
                      seriesLabel: s.t('statsListingsSeries'),
                    ),
                  ),
          ),
        ),
        _card(
          s.t('statsDeals'),
          child: _metricGrid([
            for (final deal in stats.dealTypes)
              _metric(
                _dealLabel(s, deal.key),
                metricWithPercent(deal.count, dealTotal),
                '${s.t('statsMedian')}: ${money(deal.medianUsd)}',
              ),
          ]),
        ),
        if (bands.isNotEmpty)
          _card(
            s.t('statsPriceBands'),
            trailing: _dealRadios(stats, s),
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
              _dealRadios(stats, s),
              const SizedBox(height: 6),
              _geoRadios(s),
            ],
          ),
          child: geography.isEmpty
              ? Text(s.t('statsNoData'))
              : _BarList([
                  for (final row in geography)
                    _BarRow(
                      _localizedGeographyLabel(
                        appState,
                        s,
                        _geoDimension,
                        row.label,
                      ),
                      row.count,
                      const Color(0xff24a7d6),
                      subtitle:
                          '${s.t('statsMedian')}: ${money(row.medianUsd)}',
                    ),
                ]),
        ),
        _card(
          s.t('statsOwnership'),
          child: _metricGrid([
            _metric(
              s.t('privateOwner'),
              metricWithPercent(stats.ownership.owners, ownershipTotal),
            ),
            _metric(
              s.t('agency'),
              metricWithPercent(stats.ownership.agencies, ownershipTotal),
            ),
            _metric(
              s.t('noCommission'),
              metricWithPercent(
                stats.ownership.noCommission,
                commissionTotal,
              ),
            ),
            _metric(
              s.t('commission'),
              metricWithPercent(stats.ownership.commission, commissionTotal),
            ),
          ]),
        ),
        _card(
          s.t('statsDataQuality'),
          child: _metricGrid([
            _metric(
              s.t('statsVisible'),
              metricWithPercent(stats.total, rawQualityTotal),
            ),
            _metric(
              s.t('statsDuplicates'),
              metricWithPercent(
                stats.quality.duplicatesRejected,
                rawQualityTotal,
              ),
            ),
            _metric(
              s.t('statsFake'),
              metricWithPercent(stats.quality.suspectedFake, stats.total),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _activityDayPills() => Wrap(
        spacing: 6,
        runSpacing: 5,
        children: [
          for (final days in const [7, 14, 21])
            ChoiceChip(
              label: Text('$days', textAlign: TextAlign.center),
              selected: _activityDays == days,
              showCheckmark: false,
              visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              onSelected: (_) => setState(() => _activityDays = days),
            ),
        ],
      );

  Widget _dealRadios(SearchStatistics stats, AppStrings s) {
    const known = {'sale', 'longRent', 'shortRent', 'roomRent'};
    final values = stats.dealTypes
        .where((e) => e.count > 0 && known.contains(e.key))
        .map((e) => e.key)
        .toList();
    if (values.isEmpty) return const SizedBox.shrink();
    final selected = values.contains(_dealScope) ? _dealScope : values.first;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final value in values)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _dealScope = value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected == value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected == value
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(_dealLabel(s, value), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _geoRadios(AppStrings s) {
    const values = ['country', 'city', 'district', 'microdistrict', 'metro'];
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final value in values)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _geoDimension = value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _geoDimension == value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: _geoDimension == value
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(_geoLabel(s, value), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _metricGrid(List<Widget> metrics) => LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final width = math.max(0.0, (constraints.maxWidth - gap) / 2);
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final metric in metrics)
                SizedBox(width: width, child: metric),
            ],
          );
        },
      );

  Widget _card(String title, {Widget? trailing, required Widget child}) => Card(
        // Material 3's auto-derived surfaceContainer tone (from the pink seed)
        // reads as a muddy brown on this dark theme — pin it to the app's own
        // panel color like every other card/section in the app.
        color: Theme.of(context).colorScheme.surface,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title always sits on its own line above the stat block; a
              // trailing segmented control gets its own full-width line below
              // it instead of being squeezed beside the title, where it used
              // to get clipped.
              Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (trailing != null) ...[const SizedBox(height: 8), trailing],
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );

  Widget _metric(String label, String value, [String? detail]) => Container(
        height: detail != null ? 100 : 82,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 30,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            SizedBox(
              height: 30,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: const Color(0xffe0679a)),
                  ),
                ),
              ),
            ),
            if (detail != null)
              SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
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
  const _LineChartPainter(
    this.rows,
    this.color, {
    required this.locale,
    required this.seriesLabel,
  });

  final List<ActivityStat> rows;
  final Color color;
  final String locale;
  final String seriesLabel;

  TextPainter _text(
    String value, {
    double size = 9,
    FontWeight weight = FontWeight.w500,
    Color color = Colors.white70,
  }) =>
      TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(fontSize: size, fontWeight: weight, color: color),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;

    const left = 6.0;
    const right = 6.0;
    const top = 30.0;
    const bottom = 28.0;
    final plotWidth = math.max(1.0, size.width - left - right);
    final plotHeight = math.max(1.0, size.height - top - bottom);
    final maxValue = math.max(
      1.0,
      rows.map((row) => row.count.toDouble()).reduce(math.max),
    );

    // Legend / direct line label.
    const legendY = 10.0;
    canvas.drawLine(
      const Offset(left, legendY),
      const Offset(left + 20, legendY),
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(left + 10, legendY), 3, Paint()..color = color);
    final legend = _text(
      seriesLabel,
      size: 10,
      weight: FontWeight.w600,
      color: Colors.white,
    );
    legend.paint(canvas, Offset(left + 27, legendY - legend.height / 2));

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = top + plotHeight * i / 3;
      canvas.drawLine(Offset(left, y), Offset(left + plotWidth, y), grid);
    }

    final points = <Offset>[];
    for (var i = 0; i < rows.length; i++) {
      final x = rows.length == 1
          ? left + plotWidth / 2
          : left + plotWidth * i / (rows.length - 1);
      final y =
          top + plotHeight - rows[i].count / maxValue * (plotHeight - 8) - 4;
      points.add(Offset(x, y));
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final dateFormat = DateFormat.Md(locale);
    final xStep = rows.length <= 7
        ? 1
        : rows.length <= 14
            ? 2
            : 3;

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      canvas.drawCircle(
        point,
        4,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        point,
        4,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );

      // Value directly on each point.
      final value = _text(
        '${rows[i].count}',
        size: 9,
        weight: FontWeight.w700,
        color: Colors.white,
      );
      var valueX = point.dx - value.width / 2;
      valueX = valueX.clamp(left, size.width - right - value.width).toDouble();
      var valueY = point.dy - value.height - 7;
      if (valueY < top - 2) valueY = point.dy + 7;
      value.paint(canvas, Offset(valueX, valueY));

      // Date labels are thinned on 14/21-day views to avoid collisions,
      // while the final date is always shown.
      if (i % xStep == 0 || i == rows.length - 1) {
        final date = _text(dateFormat.format(rows[i].date), size: 8);
        var dateX = point.dx - date.width / 2;
        dateX = dateX.clamp(left, size.width - right - date.width).toDouble();
        date.paint(canvas, Offset(dateX, size.height - date.height - 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.rows != rows ||
      old.color != color ||
      old.locale != locale ||
      old.seriesLabel != seriesLabel;
}
