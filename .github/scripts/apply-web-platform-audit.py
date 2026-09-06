from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)

# Home only needs a platform enum check; importing dart:io makes the whole
# screen uncompilable on Flutter Web.
path = Path('app/lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(text, "import 'dart:io' show Platform;\n", '', 'remove home dart:io')
text = replace_once(
    text,
    "import 'package:flutter/foundation.dart' show kIsWeb;\n",
    "import 'package:flutter/foundation.dart'\n    show TargetPlatform, defaultTargetPlatform, kIsWeb;\n",
    'home platform imports',
)
text = replace_once(
    text,
    '    if (kIsWeb || !Platform.isAndroid) return;\n',
    '    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;\n',
    'home android platform check',
)
path.write_text(text, encoding='utf-8')

# Listing details used dart:io only for desktop detection and writing a temporary
# PNG before share. share_plus can share an in-memory XFile, which also works on
# web and removes the File/path_provider dependency from this screen.
path = Path('app/lib/screens/listing_detail.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(text, "import 'dart:io';\n", '', 'remove detail dart:io')
text = replace_once(
    text,
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/foundation.dart'\n    show TargetPlatform, defaultTargetPlatform, kIsWeb;\nimport 'package:flutter/material.dart';\n",
    'detail platform imports',
)
text = replace_once(text, "import 'package:path_provider/path_provider.dart';\n", '', 'remove detail path_provider import')
text = replace_once(
    text,
    """  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
""",
    """  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);
""",
    'detail desktop platform check',
)
text = replace_once(
    text,
    """    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
""",
    """    if (_isDesktop) {
""",
    'detail desktop share check',
)
text = replace_once(
    text,
    """          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/listing_${listing.id}.png');
          await file.writeAsBytes(bytes.buffer.asUint8List());
          await Share.shareXFiles([XFile(file.path)], text: text);
""",
    """          final file = XFile.fromData(
            bytes.buffer.asUint8List(),
            mimeType: 'image/png',
            name: 'listing_${listing.id}.png',
          );
          await Share.shareXFiles([file], text: text);
""",
    'detail in-memory screenshot share',
)
if "dart:io" in text or "Platform.is" in text or "getTemporaryDirectory" in text:
    raise SystemExit('listing detail still has web-incompatible IO usage')
path.write_text(text, encoding='utf-8')
