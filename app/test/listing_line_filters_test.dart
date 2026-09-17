import 'package:flat_finder/l10n/strings.dart';
import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('line toggles are off by default and sent only when on', () {
    final off = Filters();
    expect(off.trustedOnly, isFalse);
    expect(off.hideDanger, isFalse);
    expect(off.toQueryParams().containsKey('trustedOnly'), isFalse);
    expect(off.toQueryParams().containsKey('hideDanger'), isFalse);

    final on = off.copyWith(trustedOnly: true, hideDanger: true);
    expect(on.toQueryParams()['trustedOnly'], 'true');
    expect(on.toQueryParams()['hideDanger'], 'true');
    expect(on.toUpstreamQueryParams()['trustedOnly'], 'true');
  });

  test('line toggles survive saved presets and share links', () {
    final on = Filters().copyWith(trustedOnly: true, hideDanger: true);
    final fromJson = Filters.fromJson(on.toJson());
    expect(fromJson.trustedOnly, isTrue);
    expect(fromJson.hideDanger, isTrue);
    final fromLink = Filters.fromQueryParams(on.toQueryParams());
    expect(fromLink.trustedOnly, isTrue);
    expect(fromLink.hideDanger, isTrue);
  });

  test('contact listing count is read from the backend field', () {
    Map<String, dynamic> json([Map<String, dynamic> extra = const {}]) => {
          'id': 'olx-42',
          'source': 'olx',
          'country': 'UZ',
          'title': 'Flat',
          'url': 'https://example.test/42',
          'description': '',
          'tags': <String>[],
          ...extra,
        };
    expect(Listing.fromJson(json({'contactListingCount': 3})).contactListingCount, 3);
    expect(Listing.fromJson(json()).contactListingCount, 0);
    expect(Listing.fromJson(json({'contactListingCount': -1})).contactListingCount, 0);
    expect(Listing.fromJson(json({'contactListingCount': 'x'})).contactListingCount, 0);
    final restored = Listing.fromJson(Listing.fromJson(json({'contactListingCount': 2})).toJson());
    expect(restored.contactListingCount, 2);
  });

  test('toggles and the contact tab are labelled in both languages', () {
    for (final lang in ['ru', 'en']) {
      final s = AppStrings(lang);
      for (final key in [
        'trustedOnly',
        'hideDanger',
        'listingDetailsTab',
        'contactListingsTab',
        'contactListingsEmpty',
        'contactListingsFailed',
      ]) {
        expect(s.t(key), isNot(key), reason: '$lang $key');
      }
    }
    expect(const AppStrings('ru').t('contactListingsTab', {'n': '2'}), 'Ещё у этого контакта (2)');
  });
}
