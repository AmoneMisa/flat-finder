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
    String money(double? usd) => usd == null
"""
if text.count(old) != 1:
    raise SystemExit(f'stats formatter anchor: expected 1 match, got {text.count(old)}')
text = text.replace(old, new, 1)

old = """                    number.format(deal.count),
                    '${s.t('statsMedian')}: ${money(deal.medianUsd)}',
"""
new = """                    '${number.format(deal.count)} · ${dealTotal == 0 ? percent.format(0) : percent.format(deal.count / dealTotal)}',
                    '${s.t('statsMedian')}: ${money(deal.medianUsd)}',
"""
if text.count(old) != 1:
    raise SystemExit(f'deal metric anchor: expected 1 match, got {text.count(old)}')
text = text.replace(old, new, 1)

path.write_text(text)
print('Deal-type percentage patch applied')
