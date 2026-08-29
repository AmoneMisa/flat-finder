from pathlib import Path

path = Path('app/lib/screens/home_screen.dart')
text = path.read_text()


def matching_paren(source: str, open_index: int) -> int:
    depth = 0
    for i in range(open_index, len(source)):
        ch = source[i]
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return i
    raise SystemExit('unmatched parenthesis')

# Make all compact form fields an exact, shared height rather than merely a
# minimum height. SearchableDropdown also receives the same constraint.
text = text.replace(
    'constraints: const BoxConstraints(minHeight: 42),',
    'constraints: const BoxConstraints.tightFor(height: 42),',
)

# Remove the compact deal-type dropdown from the Agency row.
needle = 'DropdownButtonFormField<_QuickDeal>'
deal_index = text.find(needle)
if deal_index < 0:
    raise SystemExit('quick deal dropdown not found')
comment_index = text.rfind('                  // A select', 0, deal_index)
if comment_index < 0:
    raise SystemExit('quick deal comment not found')
spacer_index = text.rfind('                  const SizedBox(width: 5),', 0, comment_index)
if spacer_index < 0:
    raise SystemExit('quick deal spacer not found')
expanded_index = text.find('                  Expanded(', comment_index)
if expanded_index < 0:
    raise SystemExit('quick deal Expanded not found')
open_paren = text.find('(', expanded_index)
close_paren = matching_paren(text, open_paren)
remove_end = close_paren + 1
if remove_end < len(text) and text[remove_end] == ',':
    remove_end += 1
if remove_end < len(text) and text[remove_end] == '\n':
    remove_end += 1
text = text[:spacer_index] + text[remove_end:]

# Add always-visible compact deal pills immediately after the Agency row.
agency_index = text.find('DropdownButtonFormField<AgencyFilter>')
if agency_index < 0:
    raise SystemExit('agency dropdown not found')
row_index = text.rfind('              Row(', 0, agency_index)
if row_index < 0:
    raise SystemExit('agency row not found')
row_open = text.find('(', row_index)
row_close = matching_paren(text, row_open)
row_end = row_close + 1
if row_end < len(text) and text[row_end] == ',':
    row_end += 1

pills = """
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (final deal in _QuickDeal.values)
                      ChoiceChip(
                        label: Text(
                          switch (deal) {
                            _QuickDeal.any => s.t('any'),
                            _QuickDeal.sale => s.t('sale'),
                            _QuickDeal.longRent => s.t('longTerm'),
                            _QuickDeal.room => s.t('roomOnly'),
                            _QuickDeal.shortRent => s.t('shortTerm'),
                          },
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        selected: _quickDealFor(widget.filters) == deal,
                        showCheckmark: false,
                        visualDensity: const VisualDensity(
                          horizontal: -3,
                          vertical: -3,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        onSelected: (_) => _schedule(
                          _withQuickDeal(_withTextValues(), deal),
                          immediate: true,
                        ),
                      ),
                  ],
                ),
              ),
"""
text = text[:row_end] + pills + text[row_end:]

path.write_text(text)
print('Persistent deal pills patch applied')
