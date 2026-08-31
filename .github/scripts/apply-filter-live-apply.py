from pathlib import Path
import re

path = Path('app/lib/widgets/filter_sheet.dart')
text = path.read_text(encoding='utf-8')
original = text

text = text.replace(
    '  Timer? _liveApplyTimer;\n',
    '  Timer? _liveApplyTimer;\n  bool _hydratingControls = false;\n',
    1,
)

text = text.replace(
    '  void _scheduleLiveApply() {\n    _liveApplyTimer?.cancel();\n',
    '  void _scheduleLiveApply() {\n    if (_hydratingControls) return;\n    _liveApplyTimer?.cancel();\n',
    1,
)

old_override = '''  @override\n  void setState(VoidCallback fn) {\n    super.setState(fn);\n    _scheduleLiveApply();\n  }\n'''
new_helper = '''  void _setFilterState(VoidCallback fn) {\n    super.setState(fn);\n    _scheduleLiveApply();\n  }\n'''
if old_override not in text:
    raise SystemExit('setState override not found')
text = text.replace(old_override, new_helper, 1)

# Every unqualified setState in this widget mutates filter state. Route those
# through the explicit helper while leaving super.setState untouched.
text = re.sub(r'(?<!\.)\bsetState\(', '_setFilterState(', text)

start = text.index('  void _loadPreset(Filters f) {')
end = text.index('\n  /// Build a shareable deep link', start)
segment = text[start:end]
needle = '  void _loadPreset(Filters f) {\n    _setFilterState(() {'
if needle not in segment:
    raise SystemExit('preset start not found')
segment = segment.replace(
    needle,
    '  void _loadPreset(Filters f) {\n    _hydratingControls = true;\n    _setFilterState(() {',
    1,
)
closing = '    });\n  }\n'
pos = segment.rfind(closing)
if pos < 0:
    raise SystemExit('preset closing not found')
segment = (
    segment[:pos]
    + '    });\n    _hydratingControls = false;\n    _scheduleLiveApply();\n  }\n'
    + segment[pos + len(closing):]
)
text = text[:start] + segment + text[end:]

if text == original:
    raise SystemExit('no changes')
path.write_text(text, encoding='utf-8')
