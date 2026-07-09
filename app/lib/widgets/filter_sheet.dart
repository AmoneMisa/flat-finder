import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/filters.dart';
import '../state/settings.dart';

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
  late PropertyType _type;
  late DealType _deal;
  late AgencyFilter _agency;
  late Audience _audience;
  String? _city;
  String? _district;
  String? _metro;
  late TextEditingController _minCtl;
  late TextEditingController _maxCtl;
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
    _type = widget.initial.propertyType;
    _deal = widget.initial.dealType;
    _agency = widget.initial.agency;
    _audience = widget.initial.audience;
    _city = widget.initial.city.trim().isEmpty ? null : widget.initial.city.trim();
    _district = widget.initial.district.trim().isEmpty ? null : widget.initial.district.trim();
    _metro = widget.initial.metro.trim().isEmpty ? null : widget.initial.metro.trim();
    _minCtl = TextEditingController(text: widget.initial.priceMin?.toString() ?? '');
    _maxCtl = TextEditingController(text: widget.initial.priceMax?.toString() ?? '');
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

  void _apply() {
    num? parse(String s) => s.trim().isEmpty ? null : num.tryParse(s.trim());
    Navigator.pop(
      context,
      Filters(
        countries: _countries,
        sources: _sources,
        propertyType: _type,
        dealType: _deal,
        agency: _agency,
        audience: _audience,
        city: _city ?? '',
        district: _district ?? '',
        metro: _metro ?? '',
        priceMin: parse(_minCtl.text),
        priceMax: parse(_maxCtl.text),
        roomsMin: parse(_roomsMinCtl.text),
        roomsMax: parse(_roomsMaxCtl.text),
        bedroomsMin: parse(_bedroomsMinCtl.text),
        bedroomsMax: parse(_bedroomsMaxCtl.text),
        floorMin: parse(_floorMinCtl.text),
        floorMax: parse(_floorMaxCtl.text),
        yearMin: parse(_yearMinCtl.text),
        yearMax: parse(_yearMaxCtl.text),
        query: _queryCtl.text,
      ),
    );
  }

  String _audienceLabel(SettingsState s, Audience a) => switch (a) {
        Audience.any => s.t('any'),
        Audience.women => s.t('women'),
        Audience.men => s.t('men'),
        Audience.family => s.t('family'),
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
            _label(s.t('countries')),
            Wrap(
              spacing: 8,
              children: widget.countries.map((c) {
                final selected = _countries.contains(c.code);
                return FilterChip(
                  label: Text(c.name),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _countries.add(c.code);
                    } else {
                      _countries.remove(c.code);
                    }
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
            _label(s.t('city')),
            Builder(builder: (context) {
              final options = _cityOptions;
              final value = options.contains(_city) ? _city : null;
              return DropdownButtonFormField<String?>(
                initialValue: value,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(s.t('anyCity'))),
                  ...options.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                ],
                onChanged: (v) => setState(() {
                  _city = v;
                  _district = null; // district/metro depend on the chosen city
                  _metro = null;
                }),
              );
            }),
            // District & metro dropdowns only appear when the picked city has data.
            if (_cityLoc != null && _cityLoc!.districts.isNotEmpty) ...[
              const SizedBox(height: 20),
              _label(s.t('district')),
              _locationDropdown(
                hint: s.t('anyDistrict'),
                options: _cityLoc!.districts,
                value: _district,
                onChanged: (v) => setState(() => _district = v),
              ),
            ],
            if (_cityLoc != null && _cityLoc!.metro.isNotEmpty) ...[
              const SizedBox(height: 20),
              _label(s.t('metro')),
              _locationDropdown(
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

  Widget _locationDropdown({
    required String hint,
    required List<String> options,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final safe = options.contains(value) ? value : null;
    return DropdownButtonFormField<String?>(
      initialValue: safe,
      isExpanded: true,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(hint)),
        ...options.map((o) => DropdownMenuItem<String?>(value: o, child: Text(o))),
      ],
      onChanged: onChanged,
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
