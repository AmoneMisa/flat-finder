from pathlib import Path

path = Path('app/lib/widgets/listing_card.dart')
text = path.read_text(encoding='utf-8')
original = text

old = '''    final theme = Theme.of(context);\n    final settings = context.watch<SettingsState>();\n    final appState = context.watch<AppState>();\n    final favorites = context.watch<FavoritesState>();\n    final history = context.watch<HistoryState>();\n    final hidden = context.watch<HiddenState>();\n    final s = settings.s;\n    final isFav = favorites.isFavorite(listing);\n    final isViewed = history.isViewed(listing);\n    final isHidden = hidden.isHidden(listing);\n    final priceState = listingPriceTone(listing, appState.rates);\n    final mobile = !grid && MediaQuery.sizeOf(context).width < 700;\n    final geographyCountry = appState.countryByCode(listing.country);\n'''
new = '''    final theme = Theme.of(context);\n    final settingsView = context.select<SettingsState, (AppStrings, String?)>(\n      (state) => (state.s, state.displayCurrency),\n    );\n    final appView = context.select<AppState, (Map<String, double>, Filters, Country?)>(\n      (state) => (\n        state.rates,\n        state.filters,\n        state.countryByCode(listing.country),\n      ),\n    );\n    final isFav = context.select<FavoritesState, bool>(\n      (state) => state.isFavorite(listing),\n    );\n    final isViewed = context.select<HistoryState, bool>(\n      (state) => state.isViewed(listing),\n    );\n    final isHidden = context.select<HiddenState, bool>(\n      (state) => state.isHidden(listing),\n    );\n    final s = settingsView.$1;\n    final displayCurrency = settingsView.$2;\n    final rates = appView.$1;\n    final filters = appView.$2;\n    final geographyCountry = appView.$3;\n    final priceState = listingPriceTone(listing, rates);\n    final mobile = !grid && MediaQuery.sizeOf(context).width < 700;\n'''
if old not in text:
    raise SystemExit('state watch block not found')
text = text.replace(old, new, 1)

text = text.replace('onPressed: () => hidden.toggle(listing),', "onPressed: () => context.read<HiddenState>().toggle(listing),", 1)
text = text.replace('onPressed: () => favorites.toggle(listing),', "onPressed: () => context.read<FavoritesState>().toggle(listing),", 1)
text = text.replace('filters: appState.filters,', 'filters: filters,')
text = text.replace('rates: appState.rates,', 'rates: rates,')
text = text.replace('displayCurrency: settings.displayCurrency,', 'displayCurrency: displayCurrency,')

old = '''        PageView.builder(\n          controller: _controller,\n          itemCount: photos.length,\n          onPageChanged: (i) => setState(() => _index = i),\n          itemBuilder: (_, i) => CachedNetworkImage(\n            imageUrl: photos[i],\n            fit: BoxFit.cover,\n            placeholder: (_, __) => const ColoredBox(color: Color(0x11000000)),\n            errorWidget: (_, __, ___) => _placeholder,\n          ),\n        ),\n'''
new = '''        LayoutBuilder(\n          builder: (context, constraints) {\n            final pixelRatio = MediaQuery.devicePixelRatioOf(context);\n            final logicalWidth = constraints.maxWidth;\n            final logicalHeight = constraints.maxHeight;\n            final cacheWidth = logicalWidth.isFinite && logicalWidth > 0\n                ? (logicalWidth * pixelRatio).ceil().clamp(1, 2048).toInt()\n                : null;\n            final cacheHeight = logicalHeight.isFinite && logicalHeight > 0\n                ? (logicalHeight * pixelRatio).ceil().clamp(1, 2048).toInt()\n                : null;\n            return PageView.builder(\n              controller: _controller,\n              itemCount: photos.length,\n              onPageChanged: (i) => setState(() => _index = i),\n              itemBuilder: (_, i) => CachedNetworkImage(\n                imageUrl: photos[i],\n                fit: BoxFit.cover,\n                memCacheWidth: cacheWidth,\n                memCacheHeight: cacheHeight,\n                placeholder: (_, __) =>\n                    const ColoredBox(color: Color(0x11000000)),\n                errorWidget: (_, __, ___) => _placeholder,\n              ),\n            );\n          },\n        ),\n'''
if old not in text:
    raise SystemExit('photo block not found')
text = text.replace(old, new, 1)

if text == original:
    raise SystemExit('no changes')
path.write_text(text, encoding='utf-8')
