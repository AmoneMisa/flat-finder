from pathlib import Path

path = Path('app/lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')
needle = "import 'package:flutter/foundation.dart'\n"
if text.count(needle) != 1:
    raise SystemExit(f'expected one foundation import, found {text.count(needle)}')
text = text.replace(needle, "import 'dart:async' show Timer;\n\n" + needle, 1)
path.write_text(text, encoding='utf-8')
