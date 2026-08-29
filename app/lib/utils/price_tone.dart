import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../state/settings.dart';

/// Six-tone price-vs-median scale — ports whiteslove.me's
/// `app/utils/flats/priceTone.ts` exactly (same bands, same colors) so the
/// card and the listing detail screen agree with the site on what "cheap"
/// and "expensive" mean.
enum PriceTone { green, blue, pink, orange, yellow, red }

Color priceToneColor(PriceTone tone) => switch (tone) {
      PriceTone.green => BrandColors.toneGreen,
      PriceTone.blue => BrandColors.toneBlue,
      PriceTone.pink => BrandColors.tonePink,
      PriceTone.orange => BrandColors.toneOrange,
      PriceTone.yellow => BrandColors.toneYellow,
      PriceTone.red => BrandColors.toneRed,
    };

/// Same bands as `priceToneFromRatio` in priceTone.ts.
PriceTone priceToneFromRatio(double ratio) {
  if (ratio >= 1.45) return PriceTone.red;
  if (ratio >= 1.31) return PriceTone.yellow;
  if (ratio >= 1.16) return PriceTone.orange;
  if (ratio >= 0.85) return PriceTone.pink;
  if (ratio >= 0.70) return PriceTone.blue;
  return PriceTone.green;
}

/// Null when there's no usable median/price to compare (matches
/// `flatPriceTone`'s null return) — callers that need a tone regardless
/// (e.g. the popup ID) fall back to [PriceTone.pink] themselves, same as
/// `useFlatDetailsTitle.ts`'s `?? "pink"`.
PriceTone? flatPriceTone(double? priceUsd, double? medianUsd) {
  if (medianUsd == null || medianUsd <= 0 || priceUsd == null || priceUsd <= 0) return null;
  return priceToneFromRatio(priceUsd / medianUsd);
}

/// [listing]'s price converted to USD via [rates] (units of currency per 1
/// USD, as returned by /api/rates), or null if that currency's rate isn't
/// known.
double? listingPriceUsd(Listing listing, Map<String, double> rates) {
  final price = listing.price?.toDouble();
  final rate = rates[listing.currency];
  if (price == null || rate == null || rate <= 0) return null;
  return price / rate;
}

/// The tone for one listing, defaulting to pink when there's no market
/// comparison — matches the site's card/popup behavior of never falling
/// back to a neutral/white price.
PriceTone listingPriceTone(Listing listing, Map<String, double> rates) {
  final priceUsd = listingPriceUsd(listing, rates);
  final medianUsd = listing.marketComparison?.medianUsd?.toDouble();
  return flatPriceTone(priceUsd, medianUsd) ?? PriceTone.pink;
}
