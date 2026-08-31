import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/listing.dart';

/// Responsive presentation of the backend's normalized nearby transport data.
///
/// The parent detail screen owns scrolling. This widget deliberately uses a
/// non-scrollable [Wrap]: three mode tables above 768 logical pixels and two at
/// 768 logical pixels or below, with the third table wrapping to the next row.
class NearbyTransportTables extends StatelessWidget {
  const NearbyTransportTables({
    super.key,
    required this.stops,
    required this.s,
  });

  final List<NearbyTransportStop> stops;
  final AppStrings s;

  static const double twoColumnBreakpoint = 768;
  static const double gap = 8;

  List<_TransportSection> get _sections {
    final definitions = <(String, String, IconData)>[
      ('bus', s.t('specBus'), Icons.directions_bus_outlined),
      ('trolleybus', s.t('specTrolleybus'), Icons.electric_rickshaw_outlined),
      ('tram', s.t('specTram'), Icons.tram_outlined),
    ];
    final sections = <_TransportSection>[];

    for (final (mode, title, icon) in definitions) {
      final modeStops = stops
          .where((stop) => stop.mode.trim().toLowerCase() == mode)
          .toList(growable: false);
      if (modeStops.isEmpty) continue;
      sections.add(
        _TransportSection(
          mode: mode,
          title: title,
          icon: icon,
          stops: modeStops,
        ),
      );
    }

    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    if (sections.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final title = s.lang == 'ru' ? 'Транспорт рядом' : 'Transport nearby';

    return Column(
      key: const Key('nearby-transport-tables'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 7),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth <= twoColumnBreakpoint ? 2 : 3;
            final itemWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final section in sections)
                  SizedBox(
                    key: Key('nearby-transport-${section.mode}'),
                    width: itemWidth,
                    child: NearbyTransportModeTable(
                      title: section.title,
                      icon: section.icon,
                      stops: section.stops,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TransportSection {
  const _TransportSection({
    required this.mode,
    required this.title,
    required this.icon,
    required this.stops,
  });

  final String mode;
  final String title;
  final IconData icon;
  final List<NearbyTransportStop> stops;
}

/// One reusable mini-table for a transport mode (bus, trolleybus or tram).
class NearbyTransportModeTable extends StatefulWidget {
  const NearbyTransportModeTable({
    super.key,
    required this.title,
    required this.icon,
    required this.stops,
  });

  final String title;
  final IconData icon;
  final List<NearbyTransportStop> stops;

  @override
  State<NearbyTransportModeTable> createState() =>
      _NearbyTransportModeTableState();
}

class _NearbyTransportModeTableState extends State<NearbyTransportModeTable> {
  static const int _visibleStopCount = 6;
  static const double _rowHeight = 52;

  final ScrollController _scrollController = ScrollController();

  List<NearbyTransportStop> get _orderedStops => [...widget.stops]
    ..sort((left, right) {
      final distance = left.distanceM.compareTo(right.distanceM);
      if (distance != 0) return distance;
      return left.name.compareTo(right.name);
    });

  String _routes(NearbyTransportStop stop) {
    final refs = stop.routeRefs
        .map((route) => route.trim())
        .where((route) => route.isNotEmpty)
        .toList(growable: false);
    return refs.isEmpty ? '—' : refs.join(', ');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _stopRow(NearbyTransportStop stop, int index, int count) {
    return SizedBox(
      height: _rowHeight,
      child: _TransportStopRow(
        stop: stop,
        routes: _routes(stop),
        drawBorder: index < count - 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.dividerColor.withValues(alpha: .58);
    final orderedStops = _orderedStops;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      widget.title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: .35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (orderedStops.length <= _visibleStopCount)
              for (var index = 0; index < orderedStops.length; index++)
                _stopRow(orderedStops[index], index, orderedStops.length)
            else
              SizedBox(
                key: const Key('nearby-transport-scroll-area'),
                height: _rowHeight * _visibleStopCount,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: orderedStops.length,
                    itemExtent: _rowHeight,
                    itemBuilder: (context, index) =>
                        _stopRow(orderedStops[index], index, orderedStops.length),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TransportStopRow extends StatelessWidget {
  const _TransportStopRow({
    required this.stop,
    required this.routes,
    required this.drawBorder,
  });

  final NearbyTransportStop stop;
  final String routes;
  final bool drawBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        border: drawBorder
            ? Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: .42),
                ),
              )
            : null,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // At phone widths each mode table is only about half the viewport.
          // Move the distance under the stop name instead of squeezing all
          // three values into one unreadable line.
          final compact = constraints.maxWidth < 230;
          final routeBadge = Container(
            constraints: const BoxConstraints(minWidth: 30, maxWidth: 64),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: .72),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              routes,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
          final distance = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 12,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 2),
              Text(
                '${stop.distanceM} m',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          );

          if (compact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                routeBadge,
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 3),
                      distance,
                    ],
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              routeBadge,
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  stop.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 6),
              distance,
            ],
          );
        },
      ),
    );
  }
}
