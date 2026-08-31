from pathlib import Path
import re

path = Path('backend/src/postgres-search-core.js')
text = path.read_text(encoding='utf-8')

for name in ('jsonNumber', 'jsonTextArrayContains', 'locationEntityMatches'):
    pattern = rf"\nfunction {re.escape(name)}\([^\n]*\) \{{.*?\n\}}\n"
    text, count = re.subn(pattern, '\n', text, count=1, flags=re.DOTALL)
    if count != 1:
        raise RuntimeError(f'Expected exactly one {name} helper, found {count}')

path.write_text(text, encoding='utf-8')
