from pathlib import Path

path = Path("app/lib/screens/listing_detail.dart")
source = path.read_text(encoding="utf-8")

import_anchor = "import '../utils/share_link.dart';\n"
import_line = "import '../widgets/nearby_transport_tables.dart';\n"
if import_line not in source:
    assert source.count(import_anchor) == 1, "share_link import anchor changed"
    source = source.replace(import_anchor, import_anchor + import_line, 1)

spec_anchor = "                        _SpecTable(listing: listing, s: s, country: country),\n"
spec_replacement = spec_anchor + """                        if (listing.nearbyTransport.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          NearbyTransportTables(
                            stops: listing.nearbyTransport,
                            s: s,
                          ),
                        ],
"""
if "NearbyTransportTables(" not in source:
    assert source.count(spec_anchor) == 1, "SpecTable insertion anchor changed"
    source = source.replace(spec_anchor, spec_replacement, 1)

legacy_rows = [
    "      (Icons.tram_outlined, 'tram', l.transportSummary('tram')),\n",
    "      (Icons.directions_bus_outlined, 'bus', l.transportSummary('bus')),\n",
    "      (Icons.electric_rickshaw_outlined, 'trolleybus', l.transportSummary('trolleybus')),\n",
]
for row in legacy_rows:
    if row in source:
        assert source.count(row) == 1, f"legacy transport row duplicated: {row.strip()}"
        source = source.replace(row, "", 1)

assert import_line in source
assert "NearbyTransportTables(" in source
for row in legacy_rows:
    assert row not in source

path.write_text(source, encoding="utf-8")
