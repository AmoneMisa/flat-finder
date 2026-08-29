from pathlib import Path


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, got {count}')
    return text.replace(old, new, 1)

# SearchableDropdown must use exactly the same field geometry as the Country
# DropdownButtonFormField: 48 logical px, dense, 12x10 content padding.
path = Path('app/lib/widgets/searchable_dropdown.dart')
text = path.read_text()
old = """        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
"""
new = """        decoration: InputDecoration(
          isDense: true,
          constraints: const BoxConstraints.tightFor(height: 48),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
"""
text = replace_once(text, old, new, 'searchable dropdown country geometry')
path.write_text(text)

# Header icons: +2 logical px without widening the 30px action slots.
path = Path('app/lib/screens/home_screen.dart')
text = path.read_text()
replacements = [
    ('iconSize: 20,', 'iconSize: 22,'),
    ('Icons.sort,\n              size: 20,', 'Icons.sort,\n              size: 22,'),
    ('Icons.currency_exchange,\n              size: 20,', 'Icons.currency_exchange,\n              size: 22,'),
    ('icon: const Icon(Icons.more_vert, size: 20),', 'icon: const Icon(Icons.more_vert, size: 22),'),
]
for old, new in replacements:
    if old == 'iconSize: 20,':
        count = text.count(old)
        if count != 2:
            raise SystemExit(f'header IconButton sizes: expected 2 matches, got {count}')
        text = text.replace(old, new)
    else:
        text = replace_once(text, old, new, old.splitlines()[0])
path.write_text(text)

# Guard the shared theme: every ordinary TextField/Dropdown in filter sheets
# inherits the same fixed height as Country.
settings = Path('app/lib/state/settings.dart').read_text()
needle = 'constraints: const BoxConstraints.tightFor(height: 48),'
if needle not in settings:
    raise SystemExit('shared 48px input constraint missing')

print('aligned filter input height with Country and enlarged header icons')
