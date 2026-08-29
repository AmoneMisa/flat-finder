import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/filters.dart';
import '../state/app_state.dart';
import '../state/presets.dart';
import '../state/settings.dart';

class PresetsScreen extends StatelessWidget {
  const PresetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final presets = context.watch<PresetsState>();
    final settings = context.watch<SettingsState>();
    return Scaffold(
      appBar: AppBar(title: Text(settings.t('presetHousingTitle'))),
      body: presets.presets.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  settings.t('noPresets'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
              itemCount: presets.presets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final preset = presets.presets[index];
                return _PresetListCard(preset: preset, settings: settings);
              },
            ),
    );
  }
}

class _PresetListCard extends StatelessWidget {
  const _PresetListCard({required this.preset, required this.settings});

  final FilterPreset preset;
  final SettingsState settings;

  Future<void> _open(BuildContext context) async {
    final state = context.read<AppState>();
    state.updateFilters(preset.filters);
    await state.search();
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _togglePush(BuildContext context, bool enabled) async {
    final state = context.read<PresetsState>();
    final ok = await state.setNotificationsEnabled(preset.id, enabled);
    if (!ok && enabled && context.mounted) {
      final key = state.pushError == 'firebase_not_configured'
          ? 'pushSetupRequired'
          : 'pushEnableFailed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(settings.t(key))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Switch(
                value: preset.enabled,
                onChanged: (value) =>
                    context.read<PresetsState>().setEnabled(preset.id, value),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Opacity(
                  opacity: preset.enabled ? 1 : .55,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _filterSummary(preset.filters, settings),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: preset.notificationsEnabled
                    ? settings.t('disablePresetPush')
                    : settings.t('enablePresetPush'),
                onPressed: () =>
                    _togglePush(context, !preset.notificationsEnabled),
                icon: Icon(
                  preset.notificationsEnabled
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                  color: preset.notificationsEnabled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  String _filterSummary(Filters f, SettingsState s) {
    final parts = <String>[];
    if (f.city.isNotEmpty) parts.add(f.city);
    if (f.district.isNotEmpty) parts.add(f.district);
    if (f.microdistrict.isNotEmpty) parts.add(f.microdistrict);
    if (f.dealType != DealType.any) {
      parts.add(s.t(switch (f.dealType) {
        DealType.sale => 'sale',
        DealType.longRent => f.roomOnly ? 'roomOnlyShort' : 'longTerm',
        DealType.shortRent => 'shortTerm',
        DealType.any => 'any',
      }));
    }
    if (f.priceMin != null || f.priceMax != null) {
      final min = f.priceMin == null ? '…' : '${f.priceMin}';
      final max = f.priceMax == null ? '…' : '${f.priceMax}';
      parts.add('$min–$max ${f.priceCurrency ?? ''}'.trim());
    }
    if (f.roomsMin != null || f.roomsMax != null) {
      parts.add('${s.t('rooms')}: ${f.roomsMin ?? '…'}–${f.roomsMax ?? '…'}');
    }
    return parts.isEmpty ? s.t('allListingsPreset') : parts.take(5).join(' · ');
  }
}
