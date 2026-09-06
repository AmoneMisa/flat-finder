from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


home_path = Path('app/lib/screens/home_screen.dart')
home = home_path.read_text(encoding='utf-8')
home = replace_once(
    home,
    '  final ApiService _api = ApiService();\n',
    '  ApiService get _api => context.read<ApiService>();\n',
    'home shared ApiService',
)
home_path.write_text(home, encoding='utf-8')


map_path = Path('app/lib/widgets/map_view.dart')
map_text = map_path.read_text(encoding='utf-8')
map_text = replace_once(
    map_text,
    '  final ApiService _api = ApiService();\n',
    '  ApiService get _api => context.read<ApiService>();\n',
    'map shared ApiService',
)
map_text = replace_once(
    map_text,
    '  MapZones _zones = const MapZones();\n',
    '  MapZones _zones = const MapZones();\n  int _zonesLoadGeneration = 0;\n',
    'map zones generation field',
)
map_text = replace_once(
    map_text,
    """  Future<void> _loadZones({bool focusCity = false}) async {
    if (widget.country.isEmpty || widget.city.isEmpty) return;
    final zones = await _api.fetchMapZones(
      widget.country,
      widget.city,
      locale: widget.locale,
    );
    if (!mounted) return;
    setState(() => _zones = zones);
""",
    """  Future<void> _loadZones({bool focusCity = false}) async {
    if (widget.country.isEmpty || widget.city.isEmpty) return;
    final generation = ++_zonesLoadGeneration;
    final country = widget.country;
    final city = widget.city;
    final locale = widget.locale;
    final zones = await _api.fetchMapZones(country, city, locale: locale);
    if (!mounted ||
        generation != _zonesLoadGeneration ||
        country != widget.country ||
        city != widget.city ||
        locale != widget.locale) {
      return;
    }
    setState(() => _zones = zones);
""",
    'map zones request guard',
)
map_text = replace_once(
    map_text,
    """    if (cityChanged) {
      _selectedDistrictId = null;
""",
    """    if (cityChanged) {
      // Invalidate a request for the previous city even when the new city is
      // empty (in that case _loadZones itself deliberately does not start).
      _zonesLoadGeneration += 1;
      _selectedDistrictId = null;
""",
    'map invalidate stale city request',
)
map_text = replace_once(
    map_text,
    "userAgentPackageName: 'com.example.flat_finder',",
    "userAgentPackageName: 'com.flatfinder.flat_finder',",
    'OSM user agent package id',
)
map_path.write_text(map_text, encoding='utf-8')
