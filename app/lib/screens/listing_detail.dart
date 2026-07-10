import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../models/listing.dart';
import '../state/app_state.dart';
import '../state/favorites.dart';
import '../state/history.dart';
import '../state/settings.dart';
import '../utils/format.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listing});

  final Listing listing;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final _shareKey = GlobalKey();

  Listing get listing => widget.listing;

  @override
  void initState() {
    super.initState();
    // Every detail open funnels through here, so record "last viewed" once at a
    // single point regardless of where it was opened from (list, map, favorites).
    context.read<HistoryState>().record(listing);
  }

  bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Compose the parsed-info text shared alongside the screenshot + link.
  String _shareText(AppStrings s, Map<String, double> rates, String? displayCurrency) {
    final b = StringBuffer()
      ..writeln(listing.title)
      ..writeln(formatPrice(listing, rates: rates, displayCurrency: displayCurrency, s: s));
    final info = <String>[];
    if (listing.rooms != null) info.add(s.t('roomsN', {'n': '${listing.rooms}'}));
    if (listing.areaSqm != null) info.add('${listing.areaSqm} m²');
    final fl = floorLabel(listing, s);
    if (fl != null) info.add(fl);
    if (listing.city.isNotEmpty) info.add(listing.city);
    if (listing.district != null) info.add(listing.district!);
    if (info.isNotEmpty) b.writeln(info.join(' · '));
    if (listing.contact != null) b.writeln(listing.contact!);
    if (listing.url.isNotEmpty) b.writeln(listing.url);
    return b.toString().trim();
  }

  /// Desktop "Share": OS share sheets are unreliable on Windows, so put a
  /// shareable link (the original listing URL, falling back to the full
  /// details) on the clipboard and confirm with a SnackBar.
  Future<void> _shareLink(AppStrings s, Map<String, double> rates, String? displayCurrency) async {
    final link = listing.url.isNotEmpty ? listing.url : _shareText(s, rates, displayCurrency);
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('linkCopied'))));
    }
  }

  Future<void> _share(AppStrings s, Map<String, double> rates, String? displayCurrency) async {
    final text = _shareText(s, rates, displayCurrency);
    // Desktop OS share sheets (esp. Windows) are unreliable, so copy the listing
    // details to the clipboard and confirm with a SnackBar instead.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('copied'))));
      }
      return;
    }
    try {
      final boundary =
          _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/listing_${listing.id}.png');
          await file.writeAsBytes(bytes.buffer.asUint8List());
          await Share.shareXFiles([XFile(file.path)], text: text);
          return;
        }
      }
    } catch (_) {
      // Fall back to text-only sharing if the screenshot capture fails.
    }
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsState>();
    final rates = context.watch<AppState>().rates;
    final favorites = context.watch<FavoritesState>();
    final s = settings.s;
    final isFav = favorites.isFavorite(listing.id);
    return Scaffold(
      appBar: AppBar(
        title: Text('${countryFlags[listing.country] ?? ''} ${listing.city}'),
        actions: [
          IconButton(
            tooltip: isFav ? s.t('removeFavorite') : s.t('addFavorite'),
            icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? Colors.red : null),
            onPressed: () => favorites.toggle(listing),
          ),
          if (_isDesktop)
            IconButton(
              tooltip: s.t('copyDetails'),
              icon: const Icon(Icons.copy),
              onPressed: () => _share(s, rates, settings.displayCurrency),
            ),
          IconButton(
            tooltip: s.t('share'),
            icon: const Icon(Icons.share),
            onPressed: () => _isDesktop
                ? _shareLink(s, rates, settings.displayCurrency)
                : _share(s, rates, settings.displayCurrency),
          ),
        ],
      ),
      body: ListView(
        children: [
          RepaintBoundary(
            key: _shareKey,
            child: Container(
              color: theme.colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (listing.photos.isNotEmpty)
                    _PhotoGallery(photos: listing.photos)
                  else if (listing.photo != null)
                    CachedNetworkImage(
                      imageUrl: listing.photo!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          const SizedBox(height: 200, child: Icon(Icons.home, size: 80)),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            formatPrice(listing,
                                rates: rates,
                                displayCurrency: settings.displayCurrency,
                                s: s),
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        if (postedLabel(listing.createdAt, s) != null)
                          Text(postedLabel(listing.createdAt, s)!,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor)),
                        const SizedBox(height: 8),
                        SelectableText(listing.title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _chip(Icons.home_work_outlined,
                                propertyLabel(listing.propertyType, s)),
                            if (dealTypeLabel(listing.dealType, s) != null)
                              _chip(Icons.sell_outlined, dealTypeLabel(listing.dealType, s)!),
                            _chip(
                              listing.byAgency ? Icons.business : Icons.person,
                              listing.byAgency ? s.t('agency') : s.t('privateOwner'),
                            ),
                            if (listing.rooms != null)
                              _chip(Icons.meeting_room_outlined,
                                  s.t('roomsN', {'n': '${listing.rooms}'})),
                            if (listing.bedrooms != null)
                              _chip(Icons.bed_outlined,
                                  s.t('bedroomsN', {'n': '${listing.bedrooms}'})),
                            if (listing.areaSqm != null)
                              _chip(Icons.square_foot, '${listing.areaSqm} m²'),
                            if (floorLabel(listing, s) != null)
                              _chip(Icons.stairs_outlined, floorLabel(listing, s)!),
                            if (listing.buildingYear != null)
                              _chip(Icons.calendar_today_outlined,
                                  s.t('yearBuiltN', {'n': '${listing.buildingYear}'})),
                            if (audienceLabel(listing.audience, s) != null)
                              _chip(Icons.groups_outlined, audienceLabel(listing.audience, s)!),
                            if (listing.roomOnly)
                              _chip(Icons.single_bed_outlined, s.t('roomOnly')),
                            if (listing.petsAllowed == true)
                              _chip(Icons.pets, s.t('petsAllowed')),
                            if (listing.childrenAllowed == true)
                              _chip(Icons.child_care, s.t('childrenAllowed')),
                            if (listing.deposit == true)
                              _chip(Icons.savings_outlined,
                                  _costLabel(s, s.t('deposit'), listing.depositAmount, null)),
                            if (listing.commission == true)
                              _chip(Icons.percent,
                                  _costLabel(s, s.t('commission'), null, listing.commissionPercent)),
                            if (listing.district != null)
                              _chip(Icons.map_outlined, listing.district!),
                            if (listing.metro != null)
                              _chip(Icons.subway_outlined, listing.metro!),
                            _chip(Icons.source_outlined, sourceLabel(listing.source, s)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (listing.contact != null) ...[
                  _ContactCard(contact: listing.contact!, s: s),
                  const SizedBox(height: 16),
                ],
                if (listing.nearby.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(s.t('nearby'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: listing.nearby
                        .map((n) => Chip(
                              avatar: const Icon(Icons.place_outlined, size: 18),
                              label: Text(n),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: theme.colorScheme.secondaryContainer,
                            ))
                        .toList(),
                  ),
                ],
                if (listing.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(s.t('tags'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: listing.tags
                        .map((t) => Chip(
                              label: Text(tagLabel(t, s)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: theme.colorScheme.primaryContainer,
                            ))
                        .toList(),
                  ),
                ],
                if (listing.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(s.t('description'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SelectableText(listing.description, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: listing.url.isEmpty
                      ? null
                      : () => launchUrl(Uri.parse(listing.url),
                          mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(s.t('openOriginal')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Chip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
      );

  /// "Deposit 500" / "Commission 50%" / just the base word when no figure known.
  String _costLabel(AppStrings s, String base, num? amount, num? percent) {
    if (percent != null) {
      final p = percent % 1 == 0 ? percent.toInt().toString() : percent.toString();
      return '$base $p%';
    }
    if (amount != null) return '$base ${amount.round()}';
    return base;
  }
}

/// Prominent contact card shown near the top of the detail screen so the user
/// can reach the poster in one tap. A @handle opens Telegram; a phone number
/// opens the dialer.
class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact, required this.s});

  final String contact;
  final AppStrings s;

  bool get _isHandle => contact.startsWith('@');

  Uri? get _uri {
    if (_isHandle) return Uri.parse('https://t.me/${contact.substring(1)}');
    final digits = contact.replaceAll(RegExp(r'[^\d+]'), '');
    return digits.isEmpty ? null : Uri.parse('tel:$digits');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uri = _uri;
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: uri == null
            ? null
            : () => launchUrl(uri, mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(_isHandle ? Icons.alternate_email : Icons.call,
                  color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.t('contact'),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer)),
                    Text(contact,
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: uri == null
                    ? null
                    : () => launchUrl(uri, mode: LaunchMode.externalApplication),
                icon: Icon(_isHandle ? Icons.send : Icons.call, size: 18),
                label: Text(_isHandle ? s.t('message') : s.t('call')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Swipeable gallery of all listing photos with a page counter. Tapping any
/// photo opens a fullscreen, zoomable viewer. Left/right arrows allow navigation
/// with a mouse on desktop where swiping isn't obvious.
class _PhotoGallery extends StatefulWidget {
  const _PhotoGallery({required this.photos});
  final List<String> photos;

  @override
  State<_PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<_PhotoGallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int to) {
    if (to < 0 || to >= widget.photos.length) return;
    _controller.animateToPage(to,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _openFullscreen() {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _FullscreenGallery(photos: widget.photos, initialIndex: _index),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.photos.length > 1;
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: _openFullscreen,
              child: CachedNetworkImage(
                imageUrl: widget.photos[i],
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) => const Icon(Icons.home, size: 80),
              ),
            ),
          ),
          // A hint that the image opens fullscreen.
          Positioned(
            left: 12,
            bottom: 12,
            child: _pill(const Icon(Icons.zoom_out_map, color: Colors.white, size: 16)),
          ),
          if (multi) ...[
            Positioned(
              left: 4,
              child: _navButton(Icons.chevron_left, _index > 0, () => _go(_index - 1)),
            ),
            Positioned(
              right: 4,
              child: _navButton(Icons.chevron_right,
                  _index < widget.photos.length - 1, () => _go(_index + 1)),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: _pill(Text(
                '${_index + 1} / ${widget.photos.length}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              )),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _navButton(IconData icon, bool enabled, VoidCallback onTap) => Opacity(
        opacity: enabled ? 1 : 0.3,
        child: Material(
          color: Colors.black38,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
      );
}

/// Fullscreen, pinch/scroll-zoomable photo viewer with page navigation.
class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({required this.photos, required this.initialIndex});
  final List<String> photos;
  final int initialIndex;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int to) {
    if (to < 0 || to >= widget.photos.length) return;
    _controller.animateToPage(to,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.photos.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.photos.length}',
            style: const TextStyle(fontSize: 14)),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.photos[i],
                  fit: BoxFit.contain,
                  placeholder: (_, __) =>
                      const Center(child: CircularProgressIndicator()),
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.broken_image, color: Colors.white54, size: 80),
                ),
              ),
            ),
          ),
          if (multi) ...[
            Positioned(
              left: 8,
              child: _navButton(Icons.chevron_left, _index > 0, () => _go(_index - 1)),
            ),
            Positioned(
              right: 8,
              child: _navButton(Icons.chevron_right,
                  _index < widget.photos.length - 1, () => _go(_index + 1)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, bool enabled, VoidCallback onTap) => Opacity(
        opacity: enabled ? 1 : 0.25,
        child: Material(
          color: Colors.white24,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
      );
}
