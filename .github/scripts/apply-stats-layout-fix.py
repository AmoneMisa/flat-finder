from pathlib import Path


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)

stats_path = Path('app/lib/widgets/stats_sheet.dart')
text = stats_path.read_text()

text = replace_once(
    text,
    "        'roomRent' => s.t('roomOnly'),",
    "        'roomRent' => s.t('roomOnlyShort'),",
    'short room label',
)

old_deals = '''        _card(
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
                    metricWithPercent(deal.count, dealTotal),
                    '${s.t('statsMedian')}: ${money(deal.medianUsd)}',
                  ),
                ),
            ],
          ),
        ),
'''
new_deals = '''        _card(
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
'''
text = replace_once(text, old_deals, new_deals, 'deal metric grid')

old_geo = '''              _segments<String>(
                const ['country', 'city', 'district', 'microdistrict', 'metro'],
                _geoDimension,
                (v) => _geoLabel(s, v),
                (v) => setState(() => _geoDimension = v),
              ),
'''
new_geo = '''              _geoRadios(s),
'''
text = replace_once(text, old_geo, new_geo, 'geo radios')

old_owner = '''        _card(
          s.t('statsOwnership'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
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
            ],
          ),
        ),
'''
new_owner = '''        _card(
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
'''
text = replace_once(text, old_owner, new_owner, 'ownership metric grid')

old_quality = '''        _card(
          s.t('statsDataQuality'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
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
            ],
          ),
        ),
'''
new_quality = '''        _card(
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
'''
text = replace_once(text, old_quality, new_quality, 'quality metric grid')

segments_start = text.index('  Widget _segments<T extends Object>(')
card_start = text.index('  Widget _card(', segments_start)
segments_block = text[segments_start:card_start]
geo_radios = '''  Widget _geoRadios(AppStrings s) {
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
              for (final metric in metrics) SizedBox(width: width, child: metric),
            ],
          );
        },
      );

'''
text = text[:segments_start] + geo_radios + text[card_start:]

metric_start = text.index('  Widget _metric(String label, String value, [String? detail]) => Container(')
metric_end = text.index('\n}\n\nclass _BarRow', metric_start)
old_metric = text[metric_start:metric_end]
new_metric = '''  Widget _metric(String label, String value, [String? detail]) => Container(
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
'''
text = text.replace(old_metric, new_metric, 1)
stats_path.write_text(text)

strings_path = Path('app/lib/l10n/strings.dart')
strings = strings_path.read_text()
strings = replace_once(
    strings,
    "      'roomOnly': 'Room only (shared)',\n",
    "      'roomOnly': 'Room only (shared)',\n      'roomOnlyShort': 'Room only',\n",
    'english short room label',
)
strings = replace_once(
    strings,
    "      'roomOnly': 'Только комната (подселение)',\n",
    "      'roomOnly': 'Только комната (подселение)',\n      'roomOnlyShort': 'Только комната',\n",
    'russian short room label',
)
strings_path.write_text(strings)

print('stats layout fix applied')
