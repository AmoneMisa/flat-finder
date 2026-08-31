import 'package:flutter_test/flutter_test.dart';

import '../lib/models/filters.dart';
import '../lib/services/api_service.dart';
import '../lib/state/app_state.dart';

class _LocaleApi extends ApiService {
  _LocaleApi() : super(baseUrl: 'http://test.invalid');

  int calls = 0;
  bool fail = true;

  @override
  Future<List<Country>> fetchCountries({String? locale}) async {
    calls++;
    if (fail) throw Exception('temporary locale outage');
    return [
      Country(
        code: 'UZ',
        name: locale == null ? 'Uzbekistan' : 'Uzbekistan $locale',
        currency: 'UZS',
        centerLat: 41.31,
        centerLng: 69.28,
      ),
    ];
  }
}

const _rawCountry = Country(
  code: 'UZ',
  name: 'Uzbekistan',
  currency: 'UZS',
  centerLat: 41.31,
  centerLng: 69.28,
);

void main() {
  test('same failed locale is not retried on every build', () async {
    final api = _LocaleApi();
    final state = AppState(api)..countries = const [_rawCountry];

    await state.ensureCountriesLocale('ru');
    await state.ensureCountriesLocale('ru');
    await state.ensureCountriesLocale('ru');

    expect(api.calls, 1);
    expect(state.countries.single.name, 'Uzbekistan');
  });

  test('different locale can retry immediately after another locale fails', () async {
    final api = _LocaleApi();
    final state = AppState(api)..countries = const [_rawCountry];

    await state.ensureCountriesLocale('ru');
    expect(api.calls, 1);

    api.fail = false;
    await state.ensureCountriesLocale('en');

    expect(api.calls, 2);
    expect(state.countries.single.name, 'Uzbekistan en');

    // Once loaded, repeated builds for the successful locale are no-ops.
    await state.ensureCountriesLocale('en');
    expect(api.calls, 2);
  });
}
