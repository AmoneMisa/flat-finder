import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/listing_line.dart';
import '../state/settings.dart';

/// Legend for the coloured card lines, pinned to the bottom of the results as
/// in the design. Fixed height so the list padding and the filter button can
/// make room for it.
class ListingLineLegend extends StatelessWidget {
  const ListingLineLegend({super.key, required this.s});

  final AppStrings s;

  static const double height = 72;

  @override
  Widget build(BuildContext context) {
    // Fixed height, so very large system text sizes are clamped here rather
    // than overflowing; 1.2x still fits two title lines and the hint.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Semantics(
        container: true,
        label: s.t('lineLegend'),
        child: Container(
          height: height,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            color: const Color(0xF00A0E24),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BrandColors.line),
            boxShadow: const [
              BoxShadow(
                color: Color(0x52000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (line, titleKey, hintKey) in listingLineLegendKeys)
                Expanded(
                  child: _LegendEntry(
                    color: ListingLineColors.of(line),
                    title: s.t(titleKey),
                    hint: s.t(hintKey),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.color,
    required this.title,
    required this.hint,
  });

  final Color color;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BrandColors.textPrimary,
              fontSize: 10,
              height: 1.2,
            ),
          ),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontSize: 9,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
