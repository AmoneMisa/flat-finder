import 'package:flutter/material.dart';

/// The coloured line on a listing card, decided by the backend
/// (whiteslove.me-backend-platform, identity/listing-line.js) and sent as
/// `listingLine`. The app only validates and draws it.
///
/// Wording describes the listing, never a verdict about a person: the lines
/// are automatic and nobody reviews them. Same values, colours and legend as
/// the website (Personal-Site utils/flats/listingLine.ts).
/// There is no yellow line: the operator removed it as unnecessary.
enum ListingLine { steady, phantomRisk, multiListing }

/// Parses the API value. Anything unknown draws no line.
ListingLine? listingLineFromJson(Object? value) {
  switch (value) {
    case 'steady':
      return ListingLine.steady;
    case 'phantom_risk':
      return ListingLine.phantomRisk;
    case 'multi_listing':
      return ListingLine.multiListing;
    default:
      return null;
  }
}

/// Matches the site's --flat-line-* CSS tokens.
class ListingLineColors {
  const ListingLineColors._();

  static const steady = Color(0xFF4ADE80);
  static const phantom = Color(0xFFF43F5E);
  static const multi = Color(0xFFA855F7);
  static const none = Color(0xFF6B7091);

  static Color of(ListingLine? line) {
    switch (line) {
      case ListingLine.steady:
        return steady;
      case ListingLine.phantomRisk:
        return phantom;
      case ListingLine.multiListing:
        return multi;
      case null:
        return none;
    }
  }
}

/// String keys for the legend entries, in design order, `null` = no line.
const listingLineLegendKeys = <(ListingLine?, String, String)>[
  (ListingLine.steady, 'lineSteady', 'lineSteadyHint'),
  (ListingLine.phantomRisk, 'linePhantom', 'linePhantomHint'),
  (ListingLine.multiListing, 'lineMulti', 'lineMultiHint'),
  (null, 'lineNone', 'lineNoneHint'),
];

/// The (title, hint) keys for one line, or null when the listing has no line.
/// The legend is no longer a strip under the results; a card explains its own
/// line on long press, so the lookup is per-card now.
(String, String)? listingLineKeys(ListingLine? line) {
  if (line == null) return null;
  for (final (candidate, titleKey, hintKey) in listingLineLegendKeys) {
    if (candidate == line) return (titleKey, hintKey);
  }
  return null;
}
