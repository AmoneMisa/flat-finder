import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/filters.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../state/presets.dart';
import '../state/settings.dart';
import '../utils/share_link.dart';

/// Bottom sheet that edits a working copy of the filters and returns it on Apply.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial, required this.countries});

  final Filters initial;
  final List<Country> countries;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late Set<String> _countries;
  late Set<String> _sources;
  late List<String> _customSources;
  late PropertyType _type;
  late DealType _deal;
  late AgencyFilter _agency;
  late Audience _audience;
  late bool _pets;
  late bool _children;
  late bool _roomOnly;
  late Set<String> _amenities;
  late bool _noElevator;
  late bool _noDeposit;
  late bool _communalIncluded;
  late bool _noCommission;
  int? _maxAgeDays;
  late SortBy _sort;
  String? _city;
  String? _district;
  String? _metro;
  late TextEditingController _minCtl;
  late TextEditingController _maxCtl;
  late TextEditingController _toleranceCtl;
  bool _tolerance = false;
  late TextEditingController _roomsMinCtl;
  late TextEditingController _roomsMaxCtl;
  late TextEditingController _bedroomsMinCtl;
  late TextEditingController _bedroomsMaxCtl;
  late TextEditingController _floorMinCtl;
  late TextEditingController _floorMaxCtl;
  late TextEditingController _yearMinCtl;
  late TextEditingController _yearMaxCtl;
  late TextEditingController _queryCtl;

  @override
  void initState() {
    super.initState();
    _countries = {...widget.initial.countries};
    _sources = {...widget.initial.sources};
    _customSources = [...widget.initial.customSources];
    _type = widget.initial.propertyType;
    _deal = widget.initial.dealType;
    _agency = widget.initial.agency;
    _audience = widget.initial.audience;
    _pets = widget.initial.pets;
    _children = widget.initial.children;
    _roomOnly = widget.initial.roomOnly;
    _amenities = {...widget.initial.amenities};
    _noElevator = widget.initial.noElevator;
    _noDeposit = widget.initial.noDeposit;
    _communalIncluded = widget.initial.communalIncluded;
    _noCommission = widget.initial.noCommission;
    _maxAgeDays = widget.initial.maxAgeDays;
    _sort = widget.initial.sort;
    _city = widget.initial.city.trim().isEmpty ? null : widget.initial.city.trim();
    _district = widget.initial.district.trim().isEmpty ? null : widget.initial.district.trim();
    _metro = widget.initial.metro.trim().isEmpty ? null : widget.initial.metro.trim();
    _minCtl = TextEditingController(text: widget.initial.priceMin?.toString() ?? '');
    _maxCtl = TextEditingController(text: widget.initial.priceMax?.toString() ?? '');
    _tolerance = (widget.initial.priceTolerance ?? 0) > 0;
    _toleranceCtl =
        TextEditingController(text: widget.initial.priceTolerance?.toString() ?? '');
    _roomsMinCtl = TextEditingController(text: widget.initial.roomsMin?.toString() ?? '');
    _roomsMaxCtl = TextEditingController(text: widget.initial.roomsMax?.toString() ?? '');
    _bedroomsMinCtl = TextEditingController(text: widget.initial.bedroomsMin?.toString() ?? '');
    _bedroomsMaxCtl = TextEditingController(text: widget.initial.bedroomsMax?.toString() ?? '');
    _floorMinCtl = TextEditingController(text: widget.initial.floorMin?.toString() ?? '');
    _floorMaxCtl = TextEditingController(text: widget.initial.floorMax?.toString() ?? '');
    _yearMinCtl = TextEditingController(text: widget.initial.yearMin?.toString() ?? '');
    _yearMaxCtl = TextEditingController(text: widget.initial.yearMax?.toString() ?? '');
    _queryCtl = TextEditingController(text: widget.initial.query);
  }

  @override
  void dispose() {
    _minCtl.dispose();
    _maxCtl.dispose();
    _toleranceCtl.dispose();
    _roomsMinCtl.dispose();
    _roomsMaxCtl.dispose();
    _bedroomsMinCtl.dispose();
    _bedroomsMaxCtl.dispose();
    _floorMinCtl.dispose();
    _floorMaxCtl.dispose();
    _yearMinCtl.dispose();
    _yearMaxCtl.dispose();
    _queryCtl.dispose();
    super.dispose();
  }

  /// Cities offered in the dropdown: the union across the selected countries.
  List<String> get _cityOptions {
    final set = <String>{};
    for (final c in widget.countries) {
      if (_countries.contains(c.code)) set.addAll(c.cities);
    }
    return set.toList()..sort();
  }

  /// District/metro data for the currently selected city, if any is available.
  CityLocations? get _cityLoc {
    if (_city == null) return null;
    for (final c in widget.countries) {
      final loc = c.locations[_city];
      if (loc != null) return loc;
    }
    return null;
  }

  /// Build a Filters snapshot from the current form state.
  Filters _currentFilters() {
    num? parse(String s) => s.trim().isEmpty ? null : num.tryParse(s.trim());
    return Filters(
      countries: _countries,
      sources: _sources,
      customSources: _customSources,
      propertyType: _type,
      dealType: _deal,
      agency: _agency,
      audience: _audience,
      city: _city ?? '',
      district: _district ?? '',
      metro: _metro ?? '',
      priceMin: parse(_minCtl.text),
      priceMax: parse(_maxCtl.text),
      priceTolerance: _tolerance ? parse(_toleranceCtl.text) : null,
      roomsMin: parse(_roomsMinCtl.text),
      roomsMax: parse(_roomsMaxCtl.text),
      bedroomsMin: parse(_bedroomsMinCtl.text),
      bedroomsMax: parse(_bedroomsMaxCtl.text),
      floorMin: parse(_floorMinCtl.text),
      floorMax: parse(_floorMaxCtl.text),
      yearMin: parse(_yearMinCtl.text),
      yearMax: parse(_yearMaxCtl.text),
      query: _queryCtl.text,
      pets: _pets,
      children: _children,
      roomOnly: _roomOnly,
      amenities: _amenities,
      noElevator: _noElevator,
      noDeposit: _noDeposit,
      communalIncluded: _communalIncluded,
      noCommission: _noCommission,
      maxAgeDays: _maxAgeDays,
      sort: _sort,
    );
  }

  void _apply() => Navigator.pop(context, _currentFilters());

  /// Ask for a name and save the current filters as a reusable preset.
  Future<void> _savePreset(SettingsState s) async {
    final ctl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(s.t('savePreset')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.t('presetName'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, ctl.text.trim()),
            child: Text(s.t('save')),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (name != null && name.isNotEmpty && mounted) {
      await context.read<PresetsState>().save(name, _currentFilters());
    }
  }

  /// Load a saved preset into the form.
  void _loadPreset(Filters f) {
    setState(() {
      _countries = {...f.countries};
      _sources = {...f.sources};
      _customSources = [...f.customSources];
      _type = f.propertyType;
      _deal = f.dealType;
      _agency = f.agency;
      _audience = f.audience;
      _pets = f.pets;
      _children = f.children;
      _roomOnly = f.roomOnly;
      _amenities = {...f.amenities};
      _noElevator = f.noElevator;
      _noDeposit = f.noDeposit;
      _communalIncluded = f.communalIncluded;
      _noCommission = f.noCommission;
      _maxAgeDays = f.maxAgeDays;
      _sort = f.sort;
      _city = f.city.trim().isEmpty ? null : f.city.trim();
      _district = f.district.trim().isEmpty ? null : f.district.trim();
      _metro = f.metro.trim().isEmpty ? null : f.metro.trim();
      _minCtl.text = f.priceMin?.toString() ?? '';
      _maxCtl.text = f.priceMax?.toString() ?? '';
      _tolerance = (f.priceTolerance ?? 0) > 0;
      _toleranceCtl.text = f.priceTolerance?.toString() ?? '';
      _roomsMinCtl.text = f.roomsMin?.toString() ?? '';
      _roomsMaxCtl.text = f.roomsMax?.toString() ?? '';
      _bedroomsMinCtl.text = f.bedroomsMin?.toString() ?? '';
      _bedroomsMaxCtl.text = f.bedroomsMax?.toString() ?? '';
      _floorMinCtl.text = f.floorMin?.toString() ?? '';
      _floorMaxCtl.text = f.floorMax?.toString() ?? '';
      _yearMinCtl.text = f.yearMin?.toString() ?? '';
      _yearMaxCtl.text = f.yearMax?.toString() ?? '';
      _queryCtl.text = f.query;
    });
  }

  /// Build a shareable deep link for a set of filters and offer it via the
  /// system share sheet, copying it to the clipboard as a fallback.
  Future<void> _shareFilters(SettingsState s, Filters filters) async {
    final url = buildSearchUrl(filters);
    await Clipboard.setData(ClipboardData(text: url));
    try {
      await Share.share(url, subject: s.t('shareSearch'));
    } catch (_) {
      // Sharing isn't available on every platform (e.g. some desktops); the
      // clipboard copy above still lets the user paste the link.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.t('searchLinkCopied'))),
      );
    }
  }

  /// Rename an existing preset via a small text dialog.
  Future<void> _renamePreset(SettingsState s, FilterPreset p) async {
    final ctl = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(s.t('renamePreset')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.t('presetName'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, ctl.text.trim()),
            child: Text(s.t('rename')),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (name != null && name.isNotEmpty && mounted) {
      await context.read<PresetsState>().rename(p.name, name);
    }
  }

  /// Present the edit menu for a preset (update to current filters, rename,
  /// share as a link, or delete).
  Future<void> _editPreset(SettingsState s, FilterPreset p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(p.name),
              onTap: () => Navigator.pop(sheetCtx, 'load'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.save_as_outlined),
              title: Text(s.t('updatePreset')),
              onTap: () => Navigator.pop(sheetCtx, 'update'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(s.t('renamePreset')),
              onTap: () => Navigator.pop(sheetCtx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(s.t('sharePreset')),
              onTap: () => Navigator.pop(sheetCtx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(s.t('deletePreset')),
              onTap: () => Navigator.pop(sheetCtx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final presets = context.read<PresetsState>();
    switch (action) {
      case 'load':
        _loadPreset(p.filters);
      case 'update':
        await presets.save(p.name, _currentFilters());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t('presetUpdated'))),
          );
        }
      case 'rename':
        await _renamePreset(s, p);
      case 'share':
        await _shareFilters(s, p.filters);
      case 'delete':
        await presets.remove(p.name);
    }
  }

  /// Prompt for a URL, validate it against the backend, and add it if it yields
  /// listings. Anything unreachable/unsupported is reported inline.
  Future<void> _promptAddCustomSource(SettingsState s) async {
    final appState = context.read<AppState>();
    final ctl = TextEditingController();
    final added = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        String? error;
        bool busy = false;
        return StatefulBuilder(
          builder: (dialogCtx, setDialog) => AlertDialog(
            title: Text(s.t('addSource')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctl,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'https://…',
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(s.t('customSourcesHint'),
                    style: Theme.of(dialogCtx).textTheme.bodySmall),
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogCtx),
                child: Text(s.t('cancel')),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final url = ctl.text.trim();
                        if (!RegExp(r'^https?://').hasMatch(url)) {
                          setDialog(() => error = s.t('invalidUrl'));
                          return;
                        }
                        if (_customSources.contains(url)) {
                          setDialog(() => error = s.t('sourceExists'));
                          return;
                        }
                        setDialog(() {
                          busy = true;
                          error = null;
                        });
                        final SourceValidation r =
                            await appState.validateSource(url);
                        if (!dialogCtx.mounted) return;
                        if (r.ok) {
                          Navigator.pop(dialogCtx, url);
                        } else {
                          setDialog(() {
                            busy = false;
                            error = r.error ?? s.t('sourceUnreadable');
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(s.t('validateAdd')),
              ),
            ],
          ),
        );
      },
    );
    ctl.dispose();
    if (added != null) setState(() => _customSources.add(added));
  }

  String _audienceLabel(SettingsState s, Audience a) => switch (a) {
        Audience.any => s.t('any'),
        Audience.women => s.t('women'),
        Audience.men => s.t('men'),
        Audience.family => s.t('family'),
      };

  String _sortLabel(SettingsState s, SortBy v) => switch (v) {
        SortBy.relevance => s.t('sortRelevance'),
        SortBy.dateNew => s.t('sortDate'),
        SortBy.priceAsc => s.t('sortPriceAsc'),
        SortBy.priceDesc => s.t('sortPriceDesc'),
        SortBy.areaDesc => s.t('sortArea'),
        SortBy.distanceCenter => s.t('sortCenter'),
        SortBy.distanceMetro => s.t('sortMetro'),
      };

  String _dealLabel(SettingsState s, DealType d) => switch (d) {
        DealType.any => s.t('any'),
        DealType.sale => s.t('sale'),
        DealType.longRent => s.t('longTerm'),
        DealType.shortRent => s.t('shortTerm'),
      };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          controller: scroll,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(s.t('filters'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _label(s.t('presets')),
            Builder(builder: (context) {
              final presets = context.watch<PresetsState>().presets;
              return Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final p in presets)
                    InputChip(
                      label: Text(p.name),
                      // Tap applies; the edit icon opens rename/update/share/delete.
                      onPressed: () => _loadPreset(p.filters),
                      avatar: GestureDetector(
                        onTap: () => _editPreset(s, p),
                        child: const Icon(Icons.edit, size: 16),
                      ),
                      onDeleted: () => context.read<PresetsState>().remove(p.name),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: Text(s.t('savePreset')),
                    onPressed: () => _savePreset(s),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.share_outlined, size: 18),
                    label: Text(s.t('shareSearch')),
                    onPressed: () => _shareFilters(s, _currentFilters()),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: Text(s.t('clearFilters')),
                    onPressed: () => _loadPreset(Filters()),
                  ),
                ],
              );
            }),
            const SizedBox(height: 20),
            // One country at a time: the sources and cities differ per country.
            _label(s.t('country')),
            Wrap(
              spacing: 8,
              children: widget.countries.map((c) {
                final selected = _countries.contains(c.code);
                return ChoiceChip(
                  label: Text(c.name),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (!v) return; // can't deselect the only country
                    _countries = {c.code};
                    _city = null; // city/district/metro belong to a country
                    _district = null;
                    _metro = null;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _label(s.t('sources')),
            Wrap(
              spacing: 8,
              children: kAllSources.map((s) {
                final selected = _sources.contains(s);
                return FilterChip(
                  label: Text(kSourceLabels[s] ?? s),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _sources.add(s);
                    } else {
                      _sources.remove(s);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _label(s.t('customSources')),
            Text(s.t('customSourcesHint'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final url in _customSources)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link, size: 20),
                title: Text(url,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: s.t('remove'),
                  onPressed: () => setState(() => _customSources.remove(url)),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(s.t('addSource')),
                onPressed: () => _promptAddCustomSource(s),
              ),
            ),
            const SizedBox(height: 20),
            _label(s.t('propertyType')),
            SegmentedButton<PropertyType>(
              segments: [
                ButtonSegment(value: PropertyType.any, label: Text(s.t('any'))),
                ButtonSegment(value: PropertyType.flat, label: Text(s.t('apartment'))),
                ButtonSegment(value: PropertyType.house, label: Text(s.t('house'))),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 20),
            _label(s.t('dealType')),
            SegmentedButton<DealType>(
              segments: DealType.values
                  .map((d) => ButtonSegment(value: d, label: Text(_dealLabel(s, d))))
                  .toList(),
              selected: {_deal},
              onSelectionChanged: (v) => setState(() => _deal = v.first),
            ),
            const SizedBox(height: 20),
            _label(s.t('realEstateAgency')),
            SegmentedButton<AgencyFilter>(
              segments: [
                ButtonSegment(value: AgencyFilter.any, label: Text(s.t('any'))),
                ButtonSegment(value: AgencyFilter.owner, label: Text(s.t('owner'))),
                ButtonSegment(value: AgencyFilter.agency, label: Text(s.t('agency'))),
              ],
              selected: {_agency},
              onSelectionChanged: (v) => setState(() => _agency = v.first),
            ),
            const SizedBox(height: 20),
            _label(s.t('priceRange')),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: s.t('min'), border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: s.t('max'), border: const OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              value: _tolerance,
              onChanged: (v) => setState(() => _tolerance = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(s.t('priceTolerance')),
              subtitle: Text(s.t('priceToleranceHint'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            if (_tolerance)
              TextField(
                controller: _toleranceCtl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '+ ${s.t('max')}',
                  prefixText: '+ ',
                  border: const OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 20),
            _label(s.t('rooms')),
            _minMaxRow(s, _roomsMinCtl, _roomsMaxCtl),
            const SizedBox(height: 20),
            _label(s.t('bedrooms')),
            _minMaxRow(s, _bedroomsMinCtl, _bedroomsMaxCtl),
            const SizedBox(height: 20),
            _label(s.t('floor')),
            _minMaxRow(s, _floorMinCtl, _floorMaxCtl),
            const SizedBox(height: 20),
            _label(s.t('buildingYear')),
            _minMaxRow(s, _yearMinCtl, _yearMaxCtl),
            const SizedBox(height: 20),
            _label(s.t('audience')),
            SegmentedButton<Audience>(
              segments: Audience.values
                  .map((a) => ButtonSegment(value: a, label: Text(_audienceLabel(s, a))))
                  .toList(),
              selected: {_audience},
              onSelectionChanged: (v) => setState(() => _audience = v.first),
            ),
            const SizedBox(height: 20),
            _label(s.t('tenantConditions')),
            SwitchListTile(
              value: _pets,
              onChanged: (v) => setState(() => _pets = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('petsAllowed')),
            ),
            SwitchListTile(
              value: _children,
              onChanged: (v) => setState(() => _children = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('childrenAllowed')),
            ),
            SwitchListTile(
              value: _roomOnly,
              onChanged: (v) => setState(() => _roomOnly = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('roomOnly')),
              subtitle: Text(s.t('roomOnlyHint'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            SwitchListTile(
              value: _noElevator,
              onChanged: (v) => setState(() => _noElevator = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('noElevator')),
            ),
            SwitchListTile(
              value: _noDeposit,
              onChanged: (v) => setState(() => _noDeposit = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('noDeposit')),
            ),
            SwitchListTile(
              value: _communalIncluded,
              onChanged: (v) => setState(() => _communalIncluded = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('communalIncluded')),
            ),
            SwitchListTile(
              value: _noCommission,
              onChanged: (v) => setState(() => _noCommission = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('noCommission')),
            ),
            const SizedBox(height: 20),
            _label(s.t('amenities')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kAmenityFilters.map((key) {
                final selected = _amenities.contains(key);
                return FilterChip(
                  label: Text(s.t('amenity_$key')),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _amenities.add(key);
                    } else {
                      _amenities.remove(key);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _label(s.t('postedWithin')),
            DropdownButtonFormField<int?>(
              initialValue: _maxAgeDays,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(s.t('anyTime'))),
                DropdownMenuItem<int?>(value: 1, child: Text(s.t('lastDay'))),
                DropdownMenuItem<int?>(value: 3, child: Text(s.t('last3Days'))),
                DropdownMenuItem<int?>(value: 7, child: Text(s.t('lastWeek'))),
                DropdownMenuItem<int?>(value: 31, child: Text(s.t('lastMonth'))),
              ],
              onChanged: (v) => setState(() => _maxAgeDays = v),
            ),
            const SizedBox(height: 20),
            _label(s.t('sortBy')),
            DropdownButtonFormField<SortBy>(
              initialValue: _sort,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: SortBy.values
                  .map((v) => DropdownMenuItem(value: v, child: Text(_sortLabel(s, v))))
                  .toList(),
              onChanged: (v) => setState(() => _sort = v ?? SortBy.relevance),
            ),
            const SizedBox(height: 20),
            _label(s.t('city')),
            _searchableDropdown(
              key: ValueKey('city-${_countries.join(',')}'),
              hint: s.t('anyCity'),
              options: _cityOptions,
              value: _city,
              onChanged: (v) => setState(() {
                _city = v;
                _district = null; // district/metro depend on the chosen city
                _metro = null;
              }),
            ),
            // District & metro inputs only appear when the picked city has data.
            if (_cityLoc != null && _cityLoc!.districts.isNotEmpty) ...[
              const SizedBox(height: 20),
              _label(s.t('district')),
              _searchableDropdown(
                key: ValueKey('district-$_city'),
                hint: s.t('anyDistrict'),
                options: _cityLoc!.districts,
                value: _district,
                onChanged: (v) => setState(() => _district = v),
              ),
            ],
            if (_cityLoc != null && _cityLoc!.metro.isNotEmpty) ...[
              const SizedBox(height: 20),
              _label(s.t('metro')),
              _searchableDropdown(
                key: ValueKey('metro-$_city'),
                hint: s.t('anyStation'),
                options: _cityLoc!.metro,
                value: _metro,
                onChanged: (v) => setState(() => _metro = v),
              ),
            ],
            const SizedBox(height: 20),
            _label(s.t('keyword')),
            TextField(
              controller: _queryCtl,
              decoration: InputDecoration(
                hintText: s.t('keywordHint'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: (_countries.isEmpty || _sources.isEmpty) ? null : _apply,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(s.t('applyFilters')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  /// A type-to-search field over a fixed option list. Empty text = "any"
  /// (null). Keyed by the parent so it resets when the city/country changes.
  Widget _searchableDropdown({
    Key? key,
    required String hint,
    required List<String> options,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Autocomplete<String>(
      key: key,
      initialValue: TextEditingValue(text: value ?? ''),
      optionsBuilder: (t) {
        final q = t.text.trim().toLowerCase();
        if (q.isEmpty) return options;
        return options.where((o) => o.toLowerCase().contains(q));
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, ctl, focus, onSubmit) => TextField(
        controller: ctl,
        focusNode: focus,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: ctl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    ctl.clear();
                    onChanged(null);
                  },
                ),
        ),
        onChanged: (t) {
          final trimmed = t.trim();
          if (trimmed.isEmpty) {
            onChanged(null);
            return;
          }
          // Commit as soon as the text exactly matches a known option, so the
          // choice sticks even if the user doesn't tap the suggestion.
          for (final o in options) {
            if (o.toLowerCase() == trimmed.toLowerCase()) {
              onChanged(o);
              return;
            }
          }
        },
      ),
      optionsViewBuilder: (context, onSelected, opts) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: opts
                  .map((o) => ListTile(
                        dense: true,
                        title: Text(o),
                        onTap: () => onSelected(o),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _minMaxRow(SettingsState s, TextEditingController min, TextEditingController max) => Row(
        children: [
          Expanded(
            child: TextField(
              controller: min,
              keyboardType: TextInputType.number,
              decoration:
                  InputDecoration(labelText: s.t('min'), border: const OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: max,
              keyboardType: TextInputType.number,
              decoration:
                  InputDecoration(labelText: s.t('max'), border: const OutlineInputBorder()),
            ),
          ),
        ],
      );
}
