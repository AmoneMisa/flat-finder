from pathlib import Path
import re


def read(path):
    return Path(path).read_text()


def write(path, text):
    Path(path).write_text(text)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


def regex_once(text, pattern, repl, label, flags=0):
    out, count = re.subn(pattern, lambda _m: repl, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return out


# ---------------------------------------------------------------------------
# Country calling codes travel with country metadata so contact normalization
# stays data-driven on the Flutter side.
# ---------------------------------------------------------------------------
path = 'backend/src/countries.js'
text = read(path)
for code, calling in [('RO', '+40'), ('UA', '+380'), ('KZ', '+7'), ('UZ', '+998')]:
    text = replace_once(
        text,
        f"    code: '{code}',\n    center:",
        f"    code: '{code}',\n    callingCode: '{calling}',\n    center:",
        f'{code} calling code',
    )
write(path, text)

path = 'backend/src/catalog-routes.js'
text = read(path)
text = replace_once(
    text,
    """            currency: country.currency,
            center: country.center,
""",
    """            currency: country.currency,
            callingCode: country.callingCode ?? null,
            center: country.center,
""",
    'catalog calling code',
)
write(path, text)

path = 'app/lib/models/filters.dart'
text = read(path)
text = replace_once(
    text,
    """  final String currency;
  final double centerLat;
""",
    """  final String currency;
  final String? callingCode;
  final double centerLat;
""",
    'country calling code field',
)
text = replace_once(
    text,
    """    required this.currency,
    required this.centerLat,
""",
    """    required this.currency,
    this.callingCode,
    required this.centerLat,
""",
    'country calling code constructor',
)
text = replace_once(
    text,
    """    currency: j['currency'] ?? '',
    centerLat:""",
    """    currency: j['currency'] ?? '',
    callingCode: j['callingCode']?.toString(),
    centerLat:""",
    'country calling code json',
)
write(path, text)


# ---------------------------------------------------------------------------
# Map feed: keep points compact but include enough UI metadata to open a useful
# popup immediately, before any background hydration request finishes.
# ---------------------------------------------------------------------------
path = 'backend/src/map-feed.js'
text = read(path)
text = replace_once(
    text,
    """    title: String(listing?.title || ''),
    price: listing?.price != null && Number.isFinite(Number(listing.price)) ? Number(listing.price) : null,
    currency: String(listing?.currency || ''),
""",
    """    title: String(listing?.title || ''),
    price: listing?.price != null && Number.isFinite(Number(listing.price)) ? Number(listing.price) : null,
    currency: String(listing?.currency || ''),
    publicId: Number.isInteger(Number(listing?.publicId)) ? Number(listing.publicId) : null,
    city: String(listing?.city || ''),
    district: listing?.district ? String(listing.district) : null,
    dealType: listing?.dealType ? String(listing.dealType) : null,
    roomOnly: listing?.roomOnly === true,
    byAgency: listing?.byAgency === true,
    propertyType: String(listing?.propertyType || 'flat'),
    rooms: listing?.rooms == null ? null : Number(listing.rooms),
    areaSqm: listing?.areaSqm == null ? null : Number(listing.areaSqm),
    photo: listing?.photo ? String(listing.photo) : null,
    createdAt: listing?.createdAt || null,
""",
    'richer map point metadata',
)
write(path, text)


# ---------------------------------------------------------------------------
# Fast cached listing lookup: enrich the DB-backed listing with the same market
# comparison used by cards. This is still much faster than a live OLX reload.
# ---------------------------------------------------------------------------
path = 'backend/src/listing-item-routes.js'
text = read(path)
text = replace_once(
    text,
    "import {pool} from './db.js';\n",
    """import {pool} from './db.js';
import {getRates} from './fx.js';
import {attachMarketComparisons} from './market-comparison.js';
""",
    'listing item market imports',
)
text = replace_once(
    text,
    """      return res.json({
        listing: {
          ...(row.data || {}),
          publicId: Number(row.id),
        },
        source: row.source,
        country: row.country,
        sourceId: row.source_id,
      });
""",
    """      let listing = {
        ...(row.data || {}),
        id: String(row.source_id || row.data?.id || ''),
        source: row.source,
        country: row.country,
        publicId: Number(row.id),
      };
      try {
        const {rates} = await getRates();
        [listing] = await attachMarketComparisons([listing], rates);
      } catch (err) {
        console.warn('[listing-item] market comparison failed:', err?.message ?? err);
      }

      return res.json({
        listing,
        source: row.source,
        country: row.country,
        sourceId: row.source_id,
      });
""",
    'fast listing market enrichment',
)
write(path, text)


# ---------------------------------------------------------------------------
# Home/map popup: open immediately from the map point/current result and hydrate
# asynchronously from the cached public-id endpoint. No tap waits on a live
# source reload anymore.
# ---------------------------------------------------------------------------
path = 'app/lib/screens/home_screen.dart'
text = read(path)
text = regex_once(
    text,
    r"  void _showMapPreview\(Listing l\) async \{.*?\n  \}\n\n  LatLng _centerFor",
    r'''  void _showMapPreview(Listing l) {
    final state = context.read<AppState>();
    var initial = l;
    for (final item in state.listings) {
      if (item.id == l.id && item.source == l.source) {
        initial = item;
        break;
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _MapListingPreview(
        api: _api,
        initial: initial,
        onOpen: (resolved) {
          Navigator.pop(context);
          _openListing(resolved);
        },
      ),
    );
  }

  LatLng _centerFor''',
    'instant map preview',
    flags=re.S,
)

marker = "/// The primary web filters stay visible on phones. Advanced filters remain in\n"
preview_widget = r'''class _MapListingPreview extends StatefulWidget {
  const _MapListingPreview({
    required this.api,
    required this.initial,
    required this.onOpen,
  });

  final ApiService api;
  final Listing initial;
  final ValueChanged<Listing> onOpen;

  @override
  State<_MapListingPreview> createState() => _MapListingPreviewState();
}

class _MapListingPreviewState extends State<_MapListingPreview> {
  late Listing _listing = widget.initial;
  bool _hydrating = false;

  @override
  void initState() {
    super.initState();
    final needsHydration =
        _listing.marketComparison == null ||
        _listing.city.isEmpty ||
        (_listing.photos.isEmpty && _listing.photo == null);
    if (needsHydration) _hydrate();
  }

  Future<void> _hydrate() async {
    if (_hydrating) return;
    _hydrating = true;
    Listing? full;
    try {
      final publicId = _listing.publicId;
      if (publicId != null) {
        full = await widget.api.fetchListingByPublicId(publicId);
      }
    } catch (_) {
      // The preview is already usable from the map point; hydration is best effort.
    }
    if (!mounted) return;
    setState(() {
      if (full != null) _listing = full!;
      _hydrating = false;
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Stack(
      children: [
        ListingCard(
          listing: _listing,
          onTap: () => widget.onOpen(_listing),
        ),
        if (_hydrating)
          const Positioned(
            left: 8,
            right: 8,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    ),
  );
}

'''
if text.count(marker) != 1:
    raise SystemExit(f'map preview widget anchor: expected 1 match, got {text.count(marker)}')
text = text.replace(marker, preview_widget + marker, 1)
write(path, text)


# ---------------------------------------------------------------------------
# Listing detail: tighter title geometry, reliable pinch zoom, no photo heart,
# country-aware phone normalization.
# ---------------------------------------------------------------------------
path = 'app/lib/screens/listing_detail.dart'
text = read(path)
text = replace_once(
    text,
    """      appBar: AppBar(
        title: _DetailTitle(
""",
    """      appBar: AppBar(
        toolbarHeight: 44,
        leadingWidth: 40,
        titleSpacing: 0,
        centerTitle: false,
        actionsPadding: EdgeInsets.zero,
        leading: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 44),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: _DetailTitle(
""",
    'detail appbar geometry',
)
text = replace_once(
    text,
    """            IconButton(
              tooltip: s.t('reloadThis'),
              icon: _reloading
""",
    """            IconButton(
              tooltip: s.t('reloadThis'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              icon: _reloading
""",
    'detail reload alignment',
)
text = replace_once(
    text,
    "_PhotoGallery(photos: listing.photos, listing: listing)",
    "_PhotoGallery(photos: listing.photos)",
    'photo gallery no listing heart dependency',
)
text = replace_once(
    text,
    """                  _ContactCard(contact: listing.contact!, s: s),
""",
    """                  _ContactCard(
                    contact: listing.contact!,
                    callingCode: country?.callingCode,
                    s: s,
                  ),
""",
    'contact calling code',
)
text = replace_once(
    text,
    """    if (listing.contact != null) b.writeln(listing.contact!);
""",
    """    if (listing.contact != null) {
      b.writeln(_contactWithCountryCode(listing.contact!, country?.callingCode));
    }
""",
    'share normalized contact',
)

# Vertically center the title text in the same 44px toolbar box as the icons.
text = replace_once(
    text,
    """      return Text('${countryFlags[listing.country] ?? ''} $city');
""",
    """      return SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('${countryFlags[listing.country] ?? ''} $city'),
        ),
      );
""",
    'detail title no id alignment',
)
text = replace_once(
    text,
    """    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 16),
        children: [
          TextSpan(
            text: '#${listing.publicId} ',
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          if (subtitle.isNotEmpty) TextSpan(text: subtitle),
        ],
      ),
    );
""",
    """    return SizedBox(
      height: 44,
      child: Align(
        alignment: Alignment.centerLeft,
        child: RichText(
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: DefaultTextStyle.of(
              context,
            ).style.copyWith(fontSize: 16, height: 1),
            children: [
              TextSpan(
                text: '#${listing.publicId} ',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
              if (subtitle.isNotEmpty) TextSpan(text: subtitle),
            ],
          ),
        ),
      ),
    );
""",
    'detail id title alignment',
)

# Contact normalization helper and country-aware card.
contact_anchor = """/// Prominent contact card shown near the top of the detail screen so the user
/// can reach the poster in one tap. A @handle opens Telegram; a phone number
/// opens the dialer.
"""
contact_helper = r'''String _contactWithCountryCode(String raw, String? callingCode) {
  final value = raw.trim();
  if (value.isEmpty || value.startsWith('@') || value.contains('+')) return value;

  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 6) return value;

  final prefix = callingCode?.trim() ?? '';
  final prefixDigits = prefix.replaceAll(RegExp(r'\D'), '');
  if (prefixDigits.isEmpty) return value;

  if (digits.startsWith('00') && digits.length > 4) {
    return '+${digits.substring(2)}';
  }
  if (digits.startsWith(prefixDigits)) return '+$digits';

  // Strip the common domestic trunk prefix before appending an E.164 country
  // code. Kazakhstan commonly writes national mobile numbers as 8XXXXXXXXXX.
  if (prefixDigits == '7' && digits.length == 11 && digits.startsWith('8')) {
    digits = digits.substring(1);
  } else if (digits.length > 7 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return '+$prefixDigits$digits';
}

'''
if text.count(contact_anchor) != 1:
    raise SystemExit(f'contact helper anchor: expected 1 match, got {text.count(contact_anchor)}')
text = text.replace(contact_anchor, contact_helper + contact_anchor, 1)
text = replace_once(
    text,
    """class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact, required this.s});

  final String contact;
  final AppStrings s;

  bool get _isHandle => contact.startsWith('@');

  Uri? get _uri {
    if (_isHandle) return Uri.parse('https://t.me/${contact.substring(1)}');
    final digits = contact.replaceAll(RegExp(r'[^\\d+]'), '');
    return digits.isEmpty ? null : Uri.parse('tel:$digits');
  }
""",
    """class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.s,
    this.callingCode,
  });

  final String contact;
  final String? callingCode;
  final AppStrings s;

  bool get _isHandle => contact.startsWith('@');
  String get _displayContact =>
      _contactWithCountryCode(contact, callingCode);

  Uri? get _uri {
    if (_isHandle) return Uri.parse('https://t.me/${contact.substring(1)}');
    final digits = _displayContact.replaceAll(RegExp(r'[^\\d+]'), '');
    return digits.isEmpty ? null : Uri.parse('tel:$digits');
  }
""",
    'country aware contact card',
)
text = replace_once(
    text,
    """                      contact,
                      style: theme.textTheme.titleMedium?.copyWith(
""",
    """                      _displayContact,
                      style: theme.textTheme.titleMedium?.copyWith(
""",
    'normalized contact display',
)

# Photo gallery: remove favorite heart overlay completely; favorite remains in
# the detail bottom action bar.
text = replace_once(
    text,
    """class _PhotoGallery extends StatefulWidget {
  const _PhotoGallery({required this.photos, required this.listing});
  final List<String> photos;
  final Listing listing;
""",
    """class _PhotoGallery extends StatefulWidget {
  const _PhotoGallery({required this.photos});
  final List<String> photos;
""",
    'photo gallery constructor',
)
text = replace_once(
    text,
    """    final multi = widget.photos.length > 1;
    final favorites = context.watch<FavoritesState>();
    final isFav = favorites.isFavorite(widget.listing.id);
    return SizedBox(
""",
    """    final multi = widget.photos.length > 1;
    return SizedBox(
""",
    'photo gallery remove favorite state',
)
text = regex_once(
    text,
    r"          // Photo counter \(when there's more than one\) with the favorite toggle.*?          \),\n        \],\n      \),\n    \);\n  \}\n\n  Widget _favButton\(bool isFav, VoidCallback onTap\) => Material\(.*?\n  \);\n",
    r'''          if (multi)
            Positioned(
              right: 12,
              bottom: 12,
              child: _pill(
                Text(
                  '${_index + 1} / ${widget.photos.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
''',
    'remove photo heart overlay',
    flags=re.S,
)

# Let InteractiveViewer own the multi-pointer gesture arena. Page navigation is
# still available through arrows; double tap remains as a convenience.
text = regex_once(
    text,
    r"          GestureDetector\(\n            onDoubleTapDown: _toggleZoom,\n            onHorizontalDragEnd: \(details\) \{.*?\n            \},\n            child: InteractiveViewer\(",
    """          GestureDetector(
            onDoubleTapDown: _toggleZoom,
            child: InteractiveViewer(""",
    'reliable pinch gesture',
    flags=re.S,
)
text = replace_once(
    text,
    """              scaleEnabled: true,
              clipBehavior: Clip.none,
""",
    """              scaleEnabled: true,
              trackpadScrollCausesScale: true,
              clipBehavior: Clip.none,
""",
    'fullscreen zoom interaction',
)
write(path, text)

print('Detail/map polish patch applied')
