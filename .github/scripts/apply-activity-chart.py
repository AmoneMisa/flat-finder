from pathlib import Path
import re


def read(path):
    return Path(path).read_text()


def write(path, text):
    Path(path).write_text(text)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


# Localized series label for the activity chart legend.
path = 'app/lib/l10n/strings.dart'
text = read(path)
text = replace_once(
    text,
    "      'statsActivity': 'Listing activity',\n",
    "      'statsActivity': 'Listing activity',\n      'statsListingsSeries': 'Listings',\n",
    'english activity series label',
)
text = replace_once(
    text,
    "      'statsActivity': 'Активность объявлений',\n",
    "      'statsActivity': 'Активность объявлений',\n      'statsListingsSeries': 'Объявления',\n",
    'russian activity series label',
)
write(path, text)


path = 'app/lib/widgets/stats_sheet.dart'
text = read(path)
text = replace_once(
    text,
    "import 'dart:math' as math;\n",
    "import 'dart:math' as math;\nimport 'dart:ui' as ui;\n",
    'activity chart ui import',
)
text = replace_once(
    text,
    """          trailing: _segments<int>(
            [7, 14, 21],
            _activityDays,
            (v) => '$v',
            (v) => setState(() => _activityDays = v),
          ),
          child: SizedBox(
            height: 150,
            width: double.infinity,
            child: activity.isEmpty
                ? Center(child: Text(s.t('statsNoData')))
                : CustomPaint(
                    size: Size.infinite,
                    painter: _LineChartPainter(
                      activity.map((e) => e.count.toDouble()).toList(),
                      const Color(0xff24a7d6),
                    ),
                  ),
          ),
""",
    """          trailing: _activityDayPills(),
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
""",
    'activity card pills and labeled chart',
)

anchor = """  Widget _dealSegments(SearchStatistics stats, AppStrings s) {
"""
helper = """  Widget _activityDayPills() => Wrap(
    spacing: 6,
    runSpacing: 5,
    children: [
      for (final days in const [7, 14, 21])
        ChoiceChip(
          label: Text('$days'),
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

"""
if text.count(anchor) != 1:
    raise SystemExit(f'activity pills helper anchor: expected 1 match, got {text.count(anchor)}')
text = text.replace(anchor, helper + anchor, 1)

pattern = re.compile(r"class _LineChartPainter extends CustomPainter \{.*?\n\}", re.S)
match = pattern.search(text)
if not match:
    raise SystemExit('line chart painter not found')
new_painter = r'''class _LineChartPainter extends CustomPainter {
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
  }) => TextPainter(
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
      final y = top + plotHeight - rows[i].count / maxValue * (plotHeight - 8) - 4;
      points.add(Offset(x, y));
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
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
}'''
text = text[:match.start()] + new_painter + text[match.end():]
write(path, text)
print('Activity chart labels patch applied')
