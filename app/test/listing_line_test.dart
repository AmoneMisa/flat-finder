import 'package:flat_finder/l10n/strings.dart';
import 'package:flat_finder/models/listing.dart';
import 'package:flat_finder/models/listing_line.dart';
import 'package:flat_finder/widgets/listing_line_legend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> listingJson([Map<String, dynamic> extra = const {}]) => {
        'id': 'olx-42',
        'source': 'olx',
        'country': 'UZ',
        'title': 'Tashkent flat',
        'propertyType': 'flat',
        'dealType': 'longRent',
        'byAgency': false,
        'price': 500,
        'currency': 'USD',
        'city': 'Tashkent',
        'photos': <String>[],
        'url': 'https://example.test/listing/42',
        'description': 'Flat description',
        'tags': <String>[],
        ...extra,
      };

  test('backend line values parse to the four lines', () {
    expect(listingLineFromJson('steady'), ListingLine.steady);
    expect(listingLineFromJson('check'), ListingLine.check);
    expect(listingLineFromJson('phantom_risk'), ListingLine.phantomRisk);
    expect(listingLineFromJson('multi_listing'), ListingLine.multiListing);
  });

  test('unknown or missing values draw no line', () {
    for (final value in [null, '', 'fraud', 'red', 42, true]) {
      expect(listingLineFromJson(value), isNull, reason: '$value');
    }
  });

  test('colours match the website tokens', () {
    expect(ListingLineColors.of(ListingLine.steady), const Color(0xFF4ADE80));
    expect(ListingLineColors.of(ListingLine.check), const Color(0xFFFACC15));
    expect(ListingLineColors.of(ListingLine.phantomRisk), const Color(0xFFF43F5E));
    expect(ListingLineColors.of(ListingLine.multiListing), const Color(0xFFA855F7));
    expect(ListingLineColors.of(null), const Color(0xFF6B7091));
  });

  test('the line survives favorites/history persistence', () {
    final listing = Listing.fromJson(listingJson({'listingLine': 'multi_listing'}));
    expect(listing.listingLine, ListingLine.multiListing);
    final restored = Listing.fromJson(listing.toJson());
    expect(restored.listingLine, ListingLine.multiListing);
    expect(Listing.fromJson(listingJson()).listingLine, isNull);
  });

  test('legend has five entries in design order with both translations', () {
    expect(
      listingLineLegendKeys.map((entry) => entry.$1).toList(),
      [
        ListingLine.steady,
        ListingLine.check,
        ListingLine.phantomRisk,
        ListingLine.multiListing,
        null,
      ],
    );
    for (final lang in ['ru', 'en']) {
      final s = AppStrings(lang);
      for (final (_, titleKey, hintKey) in listingLineLegendKeys) {
        expect(s.t(titleKey), isNot(titleKey), reason: '$lang $titleKey');
        expect(s.t(hintKey), isNot(hintKey), reason: '$lang $hintKey');
      }
    }
  });

  test('line wording describes listings, never accuses people', () {
    final pattern = RegExp(
      r'мошенник|не связываться|fraud|scam|проверен|verified|надёжный риелтор',
      caseSensitive: false,
    );
    for (final lang in ['ru', 'en']) {
      final s = AppStrings(lang);
      for (final (_, titleKey, hintKey) in listingLineLegendKeys) {
        expect(pattern.hasMatch(s.t(titleKey)), isFalse);
        expect(pattern.hasMatch(s.t(hintKey)), isFalse);
      }
    }
  });

  testWidgets('legend fits a phone width without overflow, at large text', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ListingLineLegend(s: const AppStrings('ru')),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Похоже на фантом'), findsOneWidget);
    expect(find.text('без метки'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ListingLineLegend)).height,
      ListingLineLegend.height,
    );
  });
}
