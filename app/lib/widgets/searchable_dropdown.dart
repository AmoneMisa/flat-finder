import 'package:flutter/material.dart';

/// A type-to-search field over a fixed option list. Empty text means "any"
/// (null). Plain `DropdownButtonFormField`s become unusable once a country
/// has hundreds of cities (Ukraine alone has 326) — this filters as you type
/// instead of showing one giant unscrollable-by-search list.
///
/// [options] are the actual values sent to the backend (e.g. raw city names)
/// and are what [onChanged]/[onSelected] return. Pass [labelOf] when the
/// display text should differ from that value (e.g. a localized city name) —
/// typing matches against both the raw value and its label, so a Russian
/// speaker can find "Ташкент" even though the underlying/sent value stays
/// "Tashkent".
///
/// Pass a [key] that changes when the option list itself changes (e.g. a new
/// country/city was picked) so the field resets to match.
class SearchableDropdown extends StatelessWidget {
  const SearchableDropdown({
    super.key,
    required this.hint,
    required this.options,
    required this.value,
    required this.onChanged,
    this.onTextChanged,
    this.labelOf,
  });

  final String hint;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String>? onTextChanged;
  final String Function(String)? labelOf;

  String _label(String option) => labelOf?.call(option) ?? option;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: value == null ? '' : _label(value!)),
      displayStringForOption: _label,
      optionsBuilder: (t) {
        final q = t.text.trim().toLowerCase();
        if (q.isEmpty) return options;
        return options.where(
          (o) => o.toLowerCase().contains(q) || _label(o).toLowerCase().contains(q),
        );
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
          onTextChanged?.call(t);
          final trimmed = t.trim();
          if (trimmed.isEmpty) {
            onChanged(null);
            return;
          }
          // Commit as soon as the text exactly matches a known option (by
          // value or by its localized label), so the choice sticks even if
          // the user doesn't tap the suggestion.
          for (final o in options) {
            if (o.toLowerCase() == trimmed.toLowerCase() ||
                _label(o).toLowerCase() == trimmed.toLowerCase()) {
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
                  .map(
                    (o) => ListTile(
                      dense: true,
                      title: Text(_label(o)),
                      onTap: () => onSelected(o),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}
