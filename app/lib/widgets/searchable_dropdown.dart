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
    this.placeholder,
  });

  final String hint;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String>? onTextChanged;
  final String Function(String)? labelOf;
  final String? placeholder;

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
          (o) =>
              o.toLowerCase().contains(q) ||
              _label(o).toLowerCase().contains(q),
        );
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, ctl, focus, onSubmit) => TextField(
        controller: ctl,
        focusNode: focus,
        decoration: InputDecoration(
          isDense: true,
          // A floating label (not a hint) so this reads the same as every
          // other field — always sitting on the border, matching the
          // dropdowns next to it instead of behaving like a placeholder.
          labelText: hint,
          hintText: placeholder ?? hint,
          border: const OutlineInputBorder(),
          // The default prefixIcon reserves a 48x48 tap target, taller than
          // a Dropdown's own trailing arrow — that mismatch was the field's
          // real extra height next to Country/Agency/etc.
          prefixIcon: const Icon(Icons.search, size: 18),
          // As small as the icon itself needs — no reserved tap-target
          // padding — since even a modest minHeight here was still taller
          // than a plain Dropdown's own (unconstrained) trailing arrow,
          // which was the field's last remaining extra height.
          prefixIconConstraints: const BoxConstraints(
            minWidth: 26,
            minHeight: 20,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 26,
            minHeight: 20,
          ),
          suffixIcon: ctl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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
      optionsViewBuilder: (context, onSelected, opts) {
        final theme = Theme.of(context);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                children: opts
                    .map(
                      (o) => ListTile(
                        dense: true,
                        title: Text(
                          _label(o),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        onTap: () => onSelected(o),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}
