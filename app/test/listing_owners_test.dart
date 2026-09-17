import 'package:flat_finder/l10n/strings.dart';
import 'package:flat_finder/models/filters.dart';
import 'package:flat_finder/models/listing_line.dart';
import 'package:flat_finder/models/listing_owner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const key = 'a1b2c3d4e5f6a1b2c3d4e5f6';

  test('owner keys are opaque 24-hex values; phone numbers are never keys', () {
    expect(ListingOwner.isKey(key), isTrue);
    for (final value in ['+998901234567', '@agent', key.toUpperCase(), 'a1b2', '', null]) {
      expect(ListingOwner.isKey(value), isFalse, reason: '$value');
    }
  });

  test('owners parse from the API, including line and sample', () {
    final owner = ListingOwner.fromJson({
      'ownerKey': key,
      'contact': '+998901234567',
      'country': 'UZ',
      'city': 'Tashkent',
      'properties': 3,
      'listings': 4,
      'listingLine': 'steady',
      'sample': {'publicId': 5, 'title': 'Flat', 'photo': 'https://img.test/1.jpg'},
    });
    expect(owner.properties, 3);
    expect(owner.line, ListingLine.steady);
    expect(owner.samplePhoto, 'https://img.test/1.jpg');
    expect(owner.label, '+998 90 123 45 67');
  });

  test('contacts are grouped per covered country and never guessed otherwise', () {
    expect(ownerContactLabel('+40721234567'), '+40 721 234 567');
    expect(ownerContactLabel('+380671234567'), '+380 67 123 45 67');
    expect(ownerContactLabel('+77012345678'), '+7 701 234 56 78');
    expect(ownerContactLabel('+4915112345678'), '+4915112345678');
    expect(ownerContactLabel('@agent_one'), '@agent_one');
  });

  test('the owner filter is sent, persisted, and malformed keys are dropped', () {
    final filters = Filters().copyWith(owner: key);
    expect(filters.toQueryParams()['owner'], key);
    expect(Filters.fromJson(filters.toJson()).owner, key);
    expect(Filters.fromQueryParams(filters.toQueryParams()).owner, key);
    expect(Filters.fromQueryParams({'owner': '+998901234567'}).owner, '');
    expect(Filters().toQueryParams().containsKey('owner'), isFalse);
    expect(filters.copyWith(owner: '').owner, '');
  });

  test('owners screen and breadcrumbs are labelled in both languages', () {
    for (final lang in ['ru', 'en']) {
      final s = AppStrings(lang);
      for (final name in ['ownersTab', 'ownersIntro', 'ownerListings', 'ownersEmpty', 'ownersFailed', 'ownersMore', 'ownerFallback', 'breadcrumbListings']) {
        expect(s.t(name), isNot(name), reason: '$lang $name');
      }
    }
    expect(const AppStrings('ru').t('ownerListings', {'n': '3'}), '3 объявл.');
  });
}
