import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/listing_line.dart';
import '../state/settings.dart';

/// The card-line legend, on demand.
///
/// It used to be a fixed-height strip pinned under the results, which cost
/// screen space on every scroll and clipped its own text. Now it opens from the
/// "?" button in the header, so the explanation is still reachable on a phone,
/// where a card's own long-press tooltip is easy to miss.
Future<void> showListingLineLegend(BuildContext context, AppStrings s) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => ListingLineLegendSheet(s: s),
  );
}

class ListingLineLegendSheet extends StatelessWidget {
  const ListingLineLegendSheet({super.key, required this.s});

  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    // A column, not the old four-across row: entries get the full width, so
    // long titles wrap instead of being ellipsized, at any text size.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.t('lineLegend'),
              style: const TextStyle(
                color: BrandColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            for (final (line, titleKey, hintKey) in listingLineLegendKeys)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _LegendRow(
                  color: ListingLineColors.of(line),
                  title: s.t(titleKey),
                  hint: s.t(hintKey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.title,
    required this.hint,
  });

  final Color color;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A short bar in the line's colour, echoing the card's outline.
        Container(
          width: 22,
          height: 4,
          margin: const EdgeInsets.only(top: 7),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: BrandColors.textPrimary,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
              Text(
                hint,
                style: const TextStyle(
                  color: BrandColors.textMuted,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
