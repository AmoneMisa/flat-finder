from pathlib import Path

path = Path('app/lib/widgets/map_view.dart')
s = path.read_text()
s = s.replace('Icons.electric_bus_outlined', 'Icons.directions_bus_outlined')
s = s.replace('_metro200Color', '_metroSelectedColor')
anchor = '''class _MetroStationMarker extends StatelessWidget {'''
legend = '''class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class _MetroStationMarker extends StatelessWidget {'''
if s.count(anchor) != 1:
    raise SystemExit(f'expected one metro marker anchor, found {s.count(anchor)}')
s = s.replace(anchor, legend)
path.write_text(s)
