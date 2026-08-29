from pathlib import Path


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, got {count}')
    return text.replace(old, new, 1)

# ---------------------------------------------------------------------------
# Detail contacts: show up to 3 unique contacts/phones. The parsed primary
# contact stays first; additional phone numbers are extracted from description.
# ---------------------------------------------------------------------------
path = Path('app/lib/screens/listing_detail.dart')
text = path.read_text()

text = replace_once(
    text,
    """    if (listing.contact != null) {
      b.writeln(
          _contactWithCountryCode(listing.contact!, country?.callingCode));
    }
""",
    """    for (final contact in _listingContacts(listing, country?.callingCode)) {
      b.writeln(contact);
    }
""",
    'share all contacts',
)

text = replace_once(
    text,
    """    final hasTranslatableText = listing.description.trim().isNotEmpty ||
        listing.title.trim().isNotEmpty;

    return Scaffold(
""",
    """    final hasTranslatableText = listing.description.trim().isNotEmpty ||
        listing.title.trim().isNotEmpty;
    final contacts = _listingContacts(listing, country?.callingCode);

    return Scaffold(
""",
    'compute contacts',
)

text = replace_once(
    text,
    """                if (listing.contact != null) ...[
                  _ContactCard(
                    contact: listing.contact!,
                    callingCode: country?.callingCode,
                    s: s,
                  ),
                  const SizedBox(height: 16),
                ],
""",
    """                if (contacts.isNotEmpty) ...[
                  for (var i = 0; i < contacts.length; i++) ...[
                    _ContactCard(
                      contact: contacts[i],
                      s: s,
                    ),
                    if (i < contacts.length - 1) const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 16),
                ],
""",
    'render multiple contacts',
)

anchor = """String _contactWithCountryCode(String raw, String? callingCode) {
"""
idx = text.find(anchor)
if idx < 0:
    raise SystemExit('contact helper anchor not found')
# Insert the collector after _contactWithCountryCode, before _ContactCard.
marker = """/// Prominent contact card shown near the top of the detail screen so the user
"""
marker_idx = text.find(marker, idx)
if marker_idx < 0:
    raise SystemExit('contact card marker not found')
collector = r'''/// Primary parsed contact plus phone numbers present in the advert text.
/// Keeps order, normalizes phones to the listing country's calling code, removes
/// duplicates, and intentionally caps the UI/share payload at three contacts.
List<String> _listingContacts(Listing listing, String? callingCode) {
  final contacts = <String>[];
  final seen = <String>{};

  void add(String raw) {
    if (contacts.length >= 3) return;
    final value = raw.trim();
    if (value.isEmpty) return;
    final normalized = value.startsWith('@')
        ? value
        : _contactWithCountryCode(value, callingCode);
    final key = normalized.startsWith('@')
        ? normalized.toLowerCase()
        : normalized.replaceAll(RegExp(r'\D'), '');
    if (key.isEmpty || !seen.add(key)) return;
    contacts.add(normalized);
  }

  final parsed = listing.contact;
  if (parsed != null) add(parsed);

  // Do not let a match span lines: phone numbers are extracted as one visual
  // token/line. Both international (+/00) and national forms are accepted.
  final phonePattern = RegExp(r'(?:\+|00)?\d[\d \t().-]{5,}\d');
  for (final match in phonePattern.allMatches(listing.description)) {
    if (contacts.length >= 3) break;
    final raw = match.group(0)?.trim() ?? '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) continue;
    // Short unprefixed numbers are too ambiguous (floor/year/price fragments).
    final explicitInternational = raw.startsWith('+') || raw.startsWith('00');
    if (!explicitInternational && digits.length < 9) continue;
    add(raw);
  }

  return contacts;
}

'''
text = text[:marker_idx] + collector + text[marker_idx:]
path.write_text(text)

# ---------------------------------------------------------------------------
# Map marker rendering: collision-safe standalone prices, no base cluster below
# an expanded radial group, and a focus ring that never masks the price label.
# ---------------------------------------------------------------------------
path = Path('app/lib/widgets/map_view.dart')
text = path.read_text()

text = replace_once(
    text,
    """      final otherHalfWidth =
          other.listings.length == 1 ? _priceMarkerWidth / 2 : 16.0;
      final otherHalfHeight =
          other.listings.length == 1 ? _priceMarkerHeight / 2 : 16.0;
      if (dx < _priceMarkerWidth / 2 + otherHalfWidth + 4 &&
          dy < _priceMarkerHeight / 2 + otherHalfHeight + 4) {
        return false;
      }
""",
    """      // Use a rotation-independent collision radius. The previous
      // axis-aligned rectangle check could allow two wide pills that are
      // diagonally close to overlap visually after map transforms.
      final ownRadius = math.sqrt(
        math.pow(_priceMarkerWidth / 2, 2) +
            math.pow(_priceMarkerHeight / 2, 2),
      );
      final otherRadius = other.listings.length == 1
          ? ownRadius
          : 16.0;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance < ownRadius + otherRadius + 6) return false;
""",
    'standalone marker collision',
)

text = replace_once(
    text,
    """                for (final group in groups) ..._markersForGroup(group, groups),
                if (expandedGroup != null) _radialMarkerForGroup(expandedGroup),
                if (_isFocused)
                  Marker(
                    point: widget.center,
                    width: 44,
                    height: 44,
                    child: const _FocusMarker(),
                  ),
""",
    """                for (final group in groups)
                  if (expandedGroup == null || group.key != expandedGroup.key)
                    ..._markersForGroup(group, groups),
                if (expandedGroup != null) _radialMarkerForGroup(expandedGroup),
                if (_isFocused && expandedGroup == null)
                  Marker(
                    point: widget.center,
                    width: 54,
                    height: 54,
                    child: const IgnorePointer(child: _FocusMarker()),
                  ),
""",
    'expanded group and focus marker layer',
)

old_focus = """class _FocusMarker extends StatelessWidget {
  const _FocusMarker();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.58), width: 2),
          ),
        ),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.95),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ],
    );
  }
}
"""
new_focus = """class _FocusMarker extends StatelessWidget {
  const _FocusMarker();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    // Focus is an outline only: it must never cover a standalone price label.
    return Center(
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.72), width: 2),
        ),
      ),
    );
  }
}
"""
text = replace_once(text, old_focus, new_focus, 'focus marker')
path.write_text(text)

print('map/contact fixes applied')
