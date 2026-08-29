from pathlib import Path

path = Path('app/lib/widgets/filter_sheet.dart')
text = path.read_text()
old = 'const SizedBox(height: 10)'
count = text.count(old)
if count == 0:
    raise SystemExit('no 10px vertical filter gaps found')
text = text.replace(old, 'const SizedBox(height: 8)')
path.write_text(text)
print(f'updated {count} vertical gaps from 10px to 8px')
