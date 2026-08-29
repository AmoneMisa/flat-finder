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
import '../models/filters.dart';
import '../models/listing.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../state/favorites.dart';
import '../state/hidden.dart';
import '../state/history.dart';
import '../state/settings.dart';
import '../utils/format.dart';
import '../utils/price_tone.dart';
import '../utils/share_link.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listing});

  final Listing listing;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final _shareKey = GlobalKey();

  // Held in state (not just widget.listing) so a manual reload can swap in a
  // fresh copy in place.
  late Listing _listing = widget.listing;
  Listing get listing => _listing;
  bool _reloading = false;
  bool _unavailable = false;

  bool _translating = false;
  String? _translatedText;
  String? _translatedLang;
  bool _showTranslated = false;

  @override
  void initState() {
    super.initState();
    // Every detail open funnels through here, so record "last viewed" once at a
    // single point regardless of where it was opened from (list, map, favorites).
    context.read<HistoryState>().record(listing);
    // Same live-verification the web does on open: crawled OLX data can lag
    // behind the real advert being taken down. Runs silently in the
    // background — the screen opens immediately with what's already known.
    if (listing.source == 'olx') _verifyStillAvailable();
  }

  /// Background OLX re-check on open, mirroring the web's
  /// `verifyOpenOlxListing`: silently refreshes the listing if it's still
  /// live, or flags it unavailable and drops it from the main list if OLX
  /// confirms it's gone. Network hiccups are ignored — fail open, like web.
  Future<void> _verifyStillAvailable() async {
    try {
      final fresh = await context.read<AppState>().reloadListing(_listing);
      if (!mounted) return;
      if (fresh != null) {
        setState(() {
          _listing = fresh;
          _translatedText = null;
          _translatedLang = null;
          _showTranslated = false;
        });
        return;
      }
      // null with no exception means the source confirmed the advert is
      // gone (a network/rate-limit failure throws instead, handled below).
      context.read<AppState>().removeListing(
            listing.source,
            listing.country,
            listing.id,
          );
      setState(() => _unavailable = true);
      _snack(context.read<SettingsState>().s.t('listingUnavailableTitle'));
    } catch (_) {
      // Inconclusive (timeout, rate limit, etc.) — leave the listing as-is.
    }
  }

  /// Re-fetch this single listing fresh from the source. Server flood protection
  /// (429) surfaces as a "wait a moment" message.
  Future<void> _reload(AppStrings s) async {
    if (_reloading) return;
    setState(() => _reloading = true);
    try {
      final fresh = await context.read<AppState>().reloadListing(_listing);
      if (!mounted) return;
      if (fresh != null) {
        setState(() {
          _listing = fresh;
          _translatedText = null;
          _translatedLang = null;
          _showTranslated = false;
        });
        _snack(s.t('reloaded'));
      } else {
        _snack(s.t('reloadFailed'));
      }
    } on RateLimitException {
      _snack(s.t('reloadCooldown'));
    } catch (_) {
      _snack(s.t('reloadFailed'));
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  String _localized(SettingsState settings, String en, String ru) =>
      settings.lang == 'ru' ? ru : en;

  /// Translate on demand into the selected UI language. The API call itself is
  /// asynchronous submit + polling, so this screen can survive long CPU-only
  /// inference without a single request timing out after 2–3 minutes.
  Future<void> _translate(SettingsState settings) async {
    if (_translating) return;

    final lang = settings.lang;
    final alreadyTranslated =
        _translatedText != null && _translatedLang == lang;
    if (alreadyTranslated) {
      setState(() => _showTranslated = !_showTranslated);
      return;
    }

    final sourceText = listing.description.trim().isNotEmpty
        ? listing.description.trim()
        : listing.title.trim();
    if (sourceText.isEmpty) return;

    setState(() => _translating = true);
    try {
      final translated = await context.read<AppState>().translateText(
            sourceText,
            targetLanguage: lang,
          );
      if (!mounted) return;
      setState(() {
        _translatedText = translated;
        _translatedLang = lang;
        _showTranslated = true;
      });
    } catch (_) {
      _snack(
        _localized(
          settings,
          'Could not translate the listing. Try again.',
          'Не удалось перевести объявление. Попробуйте ещё раз.',
        ),
      );
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Compose the parsed-info text shared alongside the screenshot + link.
  String _shareText(
    AppStrings s,
    Map<String, double> rates,
    String? displayCurrency,
  ) {
    final country = context.read<AppState>().countryByCode(listing.country);
    final b = StringBuffer()
      ..writeln(listing.title)
      ..writeln(
        formatPrice(
          listing,
          rates: rates,
          displayCurrency: displayCurrency,
          s: s,
        ),
      );
    final info = <String>[];
    if (listing.rooms != null)
      info.add(s.t('roomsN', {'n': '${listing.rooms}'}));
    if (listing.areaSqm != null) info.add('${listing.areaSqm} m²');
    final fl = floorLabel(listing, s);
    if (fl != null) info.add(fl);
    if (listing.city.isNotEmpty) {
      info.add(country?.cityLabel(listing.city) ?? listing.city);
    }
    if (listing.district != null) {
      info.add(
        country?.locationLabel(
              listing.city,
              listing.district!,
              kind: 'district',
            ) ??
            listing.district!,
      );
    }
    if (info.isNotEmpty) b.writeln(info.join(' · '));
    if (listing.contact != null) {
      b.writeln(
          _contactWithCountryCode(listing.contact!, country?.callingCode));
    }
    if (listing.url.isNotEmpty) b.writeln(listing.url);
    if (listing.publicId != null)
      b.writeln(buildListingWebShareUrl(listing.publicId!));
    return b.toString().trim();
  }

  /// Desktop "Share": OS share sheets are unreliable on Windows, so put a
  /// shareable link on the clipboard and confirm with a SnackBar. Same
  /// priority as the site's own share button: the app's own stable link
  /// (opens straight to this listing) over the original ad, over the full
  /// details as a last resort.
  Future<void> _shareLink(
    AppStrings s,
    Map<String, double> rates,
    String? displayCurrency,
  ) async {
    final link = listing.publicId != null
        ? buildListingWebShareUrl(listing.publicId!)
        : listing.url.isNotEmpty
            ? listing.url
            : _shareText(s, rates, displayCurrency);
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('linkCopied'))));
    }
  }

  Future<void> _share(
    AppStrings s,
    Map<String, double> rates,
    String? displayCurrency,
  ) async {
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
      final boundary = _shareKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
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
    final appState = context.watch<AppState>();
    final rates = appState.rates;
    final country = appState.countryByCode(listing.country);
    final favorites = context.watch<FavoritesState>();
    final hidden = context.watch<HiddenState>();
    final s = settings.s;
    final isFav = favorites.isFavorite(listing.id);
    final isHidden = hidden.isHidden(listing.id);
    final hasTranslation =
        _translatedText != null && _translatedLang == settings.lang;
    final showTranslated = hasTranslation && _showTranslated;
    final hasTranslatableText = listing.description.trim().isNotEmpty ||
        listing.title.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
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
          listing: listing,
          rates: rates,
          s: s,
          country: country,
        ),
        actions: [
          if (listing.source == 'olx')
            IconButton(
              tooltip: s.t('reloadThis'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              icon: _reloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _reloading ? null : () => _reload(s),
            ),
        ],
      ),
      // Favorite/hide/share moved down here, alongside the CTA, so the top
      // bar stays uncluttered and every listing action lives in one place.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: isHidden ? s.t('restoreListing') : s.t('hideListing'),
                icon: Icon(
                  isHidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => hidden.toggle(listing),
              ),
              IconButton(
                tooltip: isFav ? s.t('removeFavorite') : s.t('addFavorite'),
                icon: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? Colors.red : null,
                ),
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
              const Spacer(),
              FilledButton.icon(
                onPressed: _unavailable || listing.url.isEmpty
                    ? null
                    : () => launchUrl(
                          Uri.parse(listing.url),
                          mode: LaunchMode.externalApplication,
                        ),
                icon: const Icon(Icons.open_in_new),
                label: Text(s.t('openOriginal')),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        children: [
          if (_unavailable)
            Container(
              width: double.infinity,
              color: theme.colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.t('listingUnavailableDescription'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                      errorWidget: (_, __, ___) => const SizedBox(
                        height: 200,
                        child: Icon(Icons.home, size: 80),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatPrice(
                            listing,
                            rates: rates,
                            displayCurrency: settings.displayCurrency,
                            s: s,
                          ),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (listing.marketComparison?.goodPrice == true) ...[
                          const SizedBox(height: 8),
                          Tooltip(
                            message: _goodPriceExplanation(listing, s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: BrandColors.toneGreen.withValues(
                                  alpha: .16,
                                ),
                                border: Border.all(
                                  color: BrandColors.toneGreen.withValues(
                                    alpha: .7,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.trending_down,
                                    color: BrandColors.toneGreen,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    s.t('goodPrice'),
                                    style: const TextStyle(
                                      color: BrandColors.toneGreen,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _goodPriceExplanation(listing, s),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        if (postedLabel(listing.createdAt, s) != null)
                          Text(
                            postedLabel(listing.createdAt, s)!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                        const SizedBox(height: 8),
                        SelectableText(
                          listing.title,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        _SpecTable(listing: listing, s: s, country: country),
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
                  _ContactCard(
                    contact: listing.contact!,
                    callingCode: country?.callingCode,
                    s: s,
                  ),
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
                        .map(
                          (n) => Chip(
                            avatar: const Icon(Icons.place_outlined, size: 18),
                            label: Text(s.nearbyLabel(n)),
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                                theme.colorScheme.secondaryContainer,
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (hasTranslatableText) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            _translating ? null : () => _translate(settings),
                        icon: _translating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                showTranslated
                                    ? Icons.article_outlined
                                    : Icons.translate,
                              ),
                        label: Text(
                          _translating
                              ? _localized(settings, 'Translating…', 'Перевод…')
                              : showTranslated
                                  ? _localized(
                                      settings,
                                      'Show original',
                                      'Показать оригинал',
                                    )
                                  : _localized(
                                      settings, 'Translate', 'Перевести'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (showTranslated) ...[
                  const SizedBox(height: 16),
                  Text(
                    _localized(settings, 'Translation', 'Перевод'),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _translatedText!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ] else if (listing.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: Text(
                        s.t('description'),
                        style: theme.textTheme.titleSmall,
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(
                            listing.description,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Same "#12345 Long-term rent, Kyiv" title as the site's detail popup — the
/// public id colored by the same price-vs-median tone as the price itself
/// (falling back to pink when there's no market comparison, matching
/// useFlatDetailsTitle.ts's `?? "pink"`), followed by a deal/city summary.
class _DetailTitle extends StatelessWidget {
  const _DetailTitle({
    required this.listing,
    required this.rates,
    required this.s,
    this.country,
  });

  final Listing listing;
  final Map<String, double> rates;
  final AppStrings s;
  final Country? country;

  String get _dealText {
    if (listing.roomOnly) return s.t('roomOnly');
    if (listing.dealType == 'sale') return s.t('sale');
    if (listing.dealType == 'shortRent') return s.t('shortTerm');
    if (listing.dealType == 'longRent') return s.t('longTerm');
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (listing.publicId == null) {
      final city = country?.cityLabel(listing.city) ?? listing.city;
      return SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('${countryFlags[listing.country] ?? ''} $city'),
        ),
      );
    }
    final color = priceToneColor(listingPriceTone(listing, rates));
    final subtitle = [
      _dealText,
      country?.cityLabel(listing.city) ?? listing.city,
    ].where((e) => e.isNotEmpty).join(', ');
    return SizedBox(
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
  }
}

/// Grouped label/value spec table — same fields and grouping as the site's
/// `UiSpecTable`/`specRows` (advert/property/location/amenities/terms/costs),
/// collapsed to one column since the app is narrow rather than the site's
/// desktop 3-column layout. Empty rows are hidden so the table doesn't pad
/// itself out with "Not specified" for every field a listing lacks.
/// One row in the grouped spec table: an icon (tooltipped with [label]) and
/// its formatted [value].
class _SpecRow {
  const _SpecRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _SpecTable extends StatelessWidget {
  const _SpecTable({required this.listing, required this.s, this.country});

  final Listing listing;
  final AppStrings s;

  /// The listing's country record (fetched with the UI's locale), used to
  /// translate its city/district/metro/microdistrict/quartal/area names —
  /// unlike the client-only [cityLabel] dict, this covers every city, not
  /// just RO/KZ/UZ.
  final Country? country;

  String? _yesNo(bool? value) {
    if (value == null) return null;
    return value ? s.t('yes') : s.t('no');
  }

  /// "Yes 500" / "Yes 50%" / just "Yes"/"No" when no figure known.
  String _costLabel(String base, num? amount, num? percent) {
    if (percent != null) {
      final p =
          percent % 1 == 0 ? percent.toInt().toString() : percent.toString();
      return '$base $p%';
    }
    if (amount != null) return '$base ${amount.round()}';
    return base;
  }

  String? _conditionLabel(String? condition) => switch (condition) {
        'needs_renovation' => s.t('condNeeds'),
        'basic' => s.t('condBasic'),
        'good' => s.t('condGood'),
        'modern' => s.t('condModern'),
        'luxury' => s.t('condLuxury'),
        _ => null,
      };

  String? _money(MoneyAmount? value) {
    if (value == null) return null;
    final amount = value.amount % 1 == 0
        ? value.amount.toInt().toString()
        : value.amount.toString();
    return '${value.approximate ? '≈ ' : ''}$amount ${value.currency ?? listing.currency}'
        .trim();
  }

  /// Groups mirror the web's spec table sections: each group renders under
  /// its own header, its rows laid out as icon+value pairs (no separate
  /// label text, matching the web design) in a 2-column grid on mobile. The
  /// row's field label still comes along (as [_SpecRow.label]) so the icon
  /// can carry it as a tooltip.
  String _capitalize(String key) => key[0].toUpperCase() + key.substring(1);

  List<(String, List<_SpecRow>)> _groups() {
    final l = listing;
    List<_SpecRow> pick(List<(IconData, String, String?)> items) => [
          for (final (icon, key, value) in items)
            if (value != null && value.isNotEmpty)
              _SpecRow(icon, s.t('spec${_capitalize(key)}'), value),
        ];

    final advert = pick([
      (Icons.sell_outlined, 'deal', dealTypeLabel(l.dealType, s)),
      (Icons.home_outlined, 'type', propertyLabel(l.propertyType, s)),
      (
        Icons.person_outline,
        'listedBy',
        l.byAgency ? s.t('agency') : s.t('privateOwner'),
      ),
      (Icons.open_in_new, 'source', sourceLabel(l.source, s)),
    ]);

    final property = pick([
      (Icons.layers_outlined, 'floor', floorLabel(l, s)),
      (
        Icons.aspect_ratio_outlined,
        'area',
        l.areaSqm != null ? '${l.areaSqm} m²' : null,
      ),
      (Icons.meeting_room_outlined, 'rooms', l.rooms?.toString()),
      (Icons.bed_outlined, 'bedrooms', l.bedrooms?.toString()),
      (Icons.bathtub_outlined, 'bathrooms', l.bathrooms?.toString()),
      (Icons.apartment_outlined, 'year', l.buildingYear?.toString()),
      (Icons.new_releases_outlined, 'newBuilding', _yesNo(l.newBuilding)),
      (Icons.brush_outlined, 'condition', _conditionLabel(l.condition)),
      (Icons.location_city_outlined, 'complex', l.residenceComplex),
    ]);

    final location = pick([
      (
        Icons.map_outlined,
        'city',
        l.city.isNotEmpty ? (country?.cityLabel(l.city) ?? l.city) : null,
      ),
      (
        Icons.person_pin_circle_outlined,
        'district',
        l.district == null
            ? null
            : (country?.locationLabel(l.city, l.district!, kind: 'district') ??
                l.district),
      ),
      (
        Icons.grid_view_outlined,
        'kvartal',
        l.kvartal == null
            ? null
            : (country?.locationLabel(l.city, l.kvartal!, kind: 'quartal') ??
                l.kvartal),
      ),
      (
        Icons.directions_subway_outlined,
        'metro',
        l.metro == null
            ? null
            : (country?.locationLabel(l.city, l.metro!, kind: 'metro') ??
                l.metro),
      ),
      (Icons.location_on_outlined, 'address', l.address),
      (
        Icons.storefront_outlined,
        'shops',
        l.nearbyShops.isNotEmpty ? l.nearbyShops.join(', ') : null,
      ),
      (
        Icons.place_outlined,
        'nearby',
        l.nearby.isNotEmpty ? l.nearby.join(', ') : null,
      ),
      (
        Icons.directions_bus_outlined,
        'transitRoutes',
        l.transitRoutes.isEmpty ? null : l.transitRoutes.join(', '),
      ),
    ]);

    final amenities = pick([
      (Icons.local_parking_outlined, 'parking', _yesNo(l.parking)),
      (Icons.elevator_outlined, 'elevator', _yesNo(l.elevator)),
      (Icons.chair_outlined, 'furnished', _yesNo(l.furnished)),
      (Icons.balcony_outlined, 'balcony', _yesNo(l.balcony)),
      (Icons.deck_outlined, 'terrace', _yesNo(l.terrace)),
      (Icons.yard_outlined, 'privateYard', _yesNo(l.privateYard)),
      (Icons.kitchen_outlined, 'dishwasher', _yesNo(l.dishwasher)),
      (Icons.ac_unit_outlined, 'AC', _yesNo(l.airConditioner)),
      (Icons.local_fire_department_outlined, 'gas', _yesNo(l.gas)),
      (Icons.thermostat_outlined, 'heating', _yesNo(l.heating)),
      (Icons.water_drop_outlined, 'hotWater', _yesNo(l.hotWater)),
      (Icons.wifi, 'internet', _yesNo(l.internet)),
      (Icons.tv_outlined, 'TV', _yesNo(l.tv)),
      (Icons.microwave_outlined, 'microwave', _yesNo(l.microwave)),
      (Icons.countertops_outlined, 'oven', _yesNo(l.oven)),
      (Icons.bathroom_outlined, 'bidet', _yesNo(l.bidet)),
      (Icons.checkroom_outlined, 'walkInCloset', _yesNo(l.walkInCloset)),
      (Icons.bathtub, 'bathtub', _yesNo(l.bathtub)),
      (Icons.shower_outlined, 'shower', _yesNo(l.shower)),
      (Icons.straighten_outlined, 'euroLayout', _yesNo(l.euroLayout)),
      (Icons.description_outlined, 'cadastral', _yesNo(l.cadastral)),
    ]);

    final conditions = pick([
      (Icons.groups_outlined, 'audience', audienceLabel(l.audience, s)),
      (Icons.child_care_outlined, 'children', _yesNo(l.childrenAllowed)),
      (Icons.pets_outlined, 'pets', _yesNo(l.petsAllowed)),
      (Icons.smoking_rooms_outlined, 'smoking', _yesNo(l.smokingAllowed)),
      (Icons.meeting_room, 'roomShare', l.roomOnly ? s.t('yes') : null),
      (Icons.info_outline, 'firstRental', _yesNo(l.firstRental)),
      (Icons.school_outlined, 'studentTarget', _yesNo(l.studentTarget)),
      (
        Icons.supervisor_account_outlined,
        'landlordPresent',
        _yesNo(l.landlordPresent),
      ),
      (Icons.event_repeat_outlined, 'minLease', l.minLeaseTerm),
      (Icons.event_available_outlined, 'available', l.availableFrom),
    ]);

    // Money/payment terms get their own full-width group below Conditions,
    // matching the web's separate "Оплата" section.
    final costs = pick([
      (Icons.sell, 'negotiable', _yesNo(l.negotiable)),
      (
        Icons.savings_outlined,
        'deposit',
        l.deposit == null
            ? null
            : _costLabel(_yesNo(l.deposit)!, l.depositAmount, null),
      ),
      (
        Icons.percent_outlined,
        'commission',
        l.commission == null && l.commissionAmount == null
            ? null
            : l.commissionAmount != null
                ? '${_yesNo(l.commission ?? true)} ${_money(l.commissionAmount)}'
                : _costLabel(_yesNo(l.commission)!, null, l.commissionPercent),
      ),
      (Icons.call_split_outlined, 'communal', _yesNo(l.communalSeparated)),
      (Icons.receipt_long_outlined, 'utilAmount', _money(l.utilitiesAmount)),
      (Icons.person_pin_outlined, 'perPersonPrice', _money(l.perPersonPrice)),
    ]);

    return [
      for (final (title, items) in [
        (s.t('specGroupAdvert'), advert),
        (s.t('specGroupProperty'), property),
        (s.t('specGroupLocation'), location),
        (s.t('specGroupAmenities'), amenities),
        (s.t('specGroupConditions'), conditions),
        (s.t('specGroupCosts'), costs),
      ])
        if (items.isNotEmpty) (title, items),
    ];
  }

  Widget _groupBlock(ThemeData theme, String title, List<_SpecRow> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.hintColor,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final row in items) ...[
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: .4)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Tooltip(
                  message: row.label,
                  triggerMode: TooltipTriggerMode.tap,
                  child: Icon(
                    row.icon,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(row.value, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final byTitle = {for (final g in _groups()) g.$1: g.$2};
    if (byTitle.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    // The web's table is two columns: left stacks Advert then Property,
    // right stacks Location then Amenities. Conditions and Costs (Payment)
    // then span full width below, each as their own single-column block.
    final left = <(String, List<_SpecRow>)>[
      for (final key in [s.t('specGroupAdvert'), s.t('specGroupProperty')])
        if (byTitle[key] case final items?) (key, items),
    ];
    final right = <(String, List<_SpecRow>)>[
      for (final key in [s.t('specGroupLocation'), s.t('specGroupAmenities')])
        if (byTitle[key] case final items?) (key, items),
    ];
    final full = <(String, List<_SpecRow>)>[
      for (final key in [s.t('specGroupConditions'), s.t('specGroupCosts')])
        if (byTitle[key] case final items?) (key, items),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.t('specifications'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (left.isNotEmpty || right.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (left.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (title, items) in left)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _groupBlock(theme, title, items),
                        ),
                    ],
                  ),
                ),
              if (left.isNotEmpty && right.isNotEmpty)
                const SizedBox(width: 12),
              if (right.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (title, items) in right)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _groupBlock(theme, title, items),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        for (final (title, items) in full)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _groupBlock(theme, title, items),
          ),
      ],
    );
  }
}

String _contactWithCountryCode(String raw, String? callingCode) {
  final value = raw.trim();
  if (value.isEmpty || value.startsWith('@') || value.contains('+'))
    return value;

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

/// Prominent contact card shown near the top of the detail screen so the user
/// can reach the poster in one tap. A @handle opens Telegram; a phone number
/// opens the dialer.
class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.s,
    this.callingCode,
  });

  final String contact;
  final String? callingCode;
  final AppStrings s;

  bool get _isHandle => contact.startsWith('@');
  String get _displayContact => _contactWithCountryCode(contact, callingCode);

  Uri? get _uri {
    if (_isHandle) return Uri.parse('https://t.me/${contact.substring(1)}');
    final digits = _displayContact.replaceAll(RegExp(r'[^\d+]'), '');
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
              Icon(
                _isHandle ? Icons.alternate_email : Icons.call,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t('contact'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      _displayContact,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: uri == null
                    ? null
                    : () =>
                        launchUrl(uri, mode: LaunchMode.externalApplication),
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
    _controller.animateToPage(
      to,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            _FullscreenGallery(photos: widget.photos, initialIndex: _index),
      ),
    );
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
            child: _pill(
              const Icon(Icons.zoom_out_map, color: Colors.white, size: 16),
            ),
          ),
          if (multi) ...[
            Positioned(
              left: 4,
              child: _navButton(
                Icons.chevron_left,
                _index > 0,
                () => _go(_index - 1),
              ),
            ),
            Positioned(
              right: 4,
              child: _navButton(
                Icons.chevron_right,
                _index < widget.photos.length - 1,
                () => _go(_index + 1),
              ),
            ),
          ],
          if (multi)
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
String _goodPriceExplanation(Listing listing, AppStrings s) {
  final comparison = listing.marketComparison;
  final median = comparison?.medianUsd;
  if (median == null) return s.t('goodPrice');
  final medianLabel = median == median.roundToDouble()
      ? median.toInt().toString()
      : median.toStringAsFixed(2);
  return s.t('goodPriceCompared', {
    'count': '${comparison?.comparableCount ?? 0}',
    'median': medianLabel,
  });
}

class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({required this.photos, required this.initialIndex});
  final List<String> photos;
  final int initialIndex;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late int _index = widget.initialIndex;
  final TransformationController _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _go(int to) {
    if (to < 0 || to >= widget.photos.length) return;
    setState(() {
      _index = to;
      _transform.value = Matrix4.identity();
    });
  }

  void _toggleZoom(TapDownDetails details) {
    if (_transform.value.getMaxScaleOnAxis() > 1.05) {
      _transform.value = Matrix4.identity();
      return;
    }
    final p = details.localPosition;
    _transform.value = Matrix4.identity()
      ..translate(-p.dx * 1.5, -p.dy * 1.5)
      ..scale(2.5);
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.photos.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.photos.length}',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onDoubleTapDown: _toggleZoom,
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 6,
              panEnabled: true,
              scaleEnabled: true,
              trackpadScrollCausesScale: true,
              clipBehavior: Clip.none,
              boundaryMargin: const EdgeInsets.all(80),
              child: SizedBox.expand(
                child: CachedNetworkImage(
                  imageUrl: widget.photos[_index],
                  fit: BoxFit.contain,
                  placeholder: (_, __) =>
                      const Center(child: CircularProgressIndicator()),
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 80,
                  ),
                ),
              ),
            ),
          ),
          if (multi) ...[
            Positioned(
              left: 8,
              child: _navButton(
                Icons.chevron_left,
                _index > 0,
                () => _go(_index - 1),
              ),
            ),
            Positioned(
              right: 8,
              child: _navButton(
                Icons.chevron_right,
                _index < widget.photos.length - 1,
                () => _go(_index + 1),
              ),
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
