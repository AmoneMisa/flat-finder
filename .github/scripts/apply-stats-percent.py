from pathlib import Path

path = Path('app/lib/widgets/stats_sheet.dart')
text = path.read_text()

old = """    final number = NumberFormat.decimalPattern(settings.lang);
    String money(double? usd) => usd == null
"""
new = """    final number = NumberFormat.decimalPattern(settings.lang);
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
"""
if text.count(old) != 1:
    raise SystemExit(f'stats formatter anchor: expected 1 match, got {text.count(old)}')
text = text.replace(old, new, 1)

old = """                    number.format(deal.count),
                    '${s.t('statsMedian')}: ${money(deal.medianUsd)}',
"""
new = """                    metricWithPercent(deal.count, dealTotal),
                    '${s.t('statsMedian')}: ${money(deal.medianUsd)}',
"""
if text.count(old) != 1:
    raise SystemExit(f'deal metric anchor: expected 1 match, got {text.count(old)}')
text = text.replace(old, new, 1)

replacements = [
    (
        """                number.format(stats.ownership.owners),
""",
        """                metricWithPercent(stats.ownership.owners, ownershipTotal),
""",
        'owner percent',
    ),
    (
        """              _metric(s.t('agency'), number.format(stats.ownership.agencies)),
""",
        """              _metric(
                s.t('agency'),
                metricWithPercent(stats.ownership.agencies, ownershipTotal),
              ),
""",
        'agency percent',
    ),
    (
        """                number.format(stats.ownership.noCommission),
""",
        """                metricWithPercent(
                  stats.ownership.noCommission,
                  commissionTotal,
                ),
""",
        'no commission percent',
    ),
    (
        """                number.format(stats.ownership.commission),
""",
        """                metricWithPercent(
                  stats.ownership.commission,
                  commissionTotal,
                ),
""",
        'commission percent',
    ),
    (
        """              _metric(s.t('statsVisible'), number.format(stats.total)),
""",
        """              _metric(
                s.t('statsVisible'),
                metricWithPercent(stats.total, rawQualityTotal),
              ),
""",
        'visible percent',
    ),
    (
        """                number.format(stats.quality.duplicatesRejected),
""",
        """                metricWithPercent(
                  stats.quality.duplicatesRejected,
                  rawQualityTotal,
                ),
""",
        'duplicates percent',
    ),
    (
        """                number.format(stats.quality.suspectedFake),
""",
        """                metricWithPercent(
                  stats.quality.suspectedFake,
                  stats.total,
                ),
""",
        'suspected fake percent',
    ),
]
for old, new, label in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, got {count}')
    text = text.replace(old, new, 1)

path.write_text(text)
print('Statistics percentage patch applied')
