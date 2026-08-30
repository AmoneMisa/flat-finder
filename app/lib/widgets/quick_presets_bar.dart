import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/filters.dart';
import '../state/presets.dart';
import '../state/settings.dart';

/// Compact access to the user's already-saved filter presets.
///
/// The full filter editor stays behind the Filters FAB; the home surface only
/// exposes the reusable presets so it does not duplicate the filter form.
class QuickPresetsBar extends StatelessWidget {
  const QuickPresetsBar({
    super.key,
    required this.onApply,
    required this.onManage,
  });

  final Future<void> Function(Filters filters) onApply;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final presets = context.watch<PresetsState>().presets;
    final settings = context.watch<SettingsState>();
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(Icons.bookmarks_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              settings.t('presets'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: presets.isEmpty
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onManage,
                        icon: const Icon(Icons.add, size: 17),
                        label: Text(settings.t('savePreset')),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: presets.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, index) {
                        final preset = presets[index];
                        return ActionChip(
                          avatar: Icon(
                            preset.notificationsEnabled
                                ? Icons.notifications_active_outlined
                                : Icons.tune,
                            size: 16,
                          ),
                          label: Text(
                            preset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () => onApply(
                            Filters.fromJson(preset.filters.toJson()),
                          ),
                        );
                      },
                    ),
            ),
            IconButton(
              tooltip: settings.t('presets'),
              onPressed: onManage,
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }
}
