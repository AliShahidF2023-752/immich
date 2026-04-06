import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/offline_features.provider.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/services/placeholder.service.dart';
import 'package:immich_mobile/utils/bytes_units.dart';
import 'package:immich_mobile/utils/hooks/app_settings_update_hook.dart';
import 'package:immich_mobile/widgets/settings/settings_slider_list_tile.dart';
import 'package:immich_mobile/widgets/settings/settings_sub_page_scaffold.dart';
import 'package:immich_mobile/widgets/settings/settings_switch_list_tile.dart';

/// Settings page for placeholder images and on-device OCR.
///
/// Located under Settings → Special Customizations.
class SpecialCustomizationsSettings extends HookConsumerWidget {
  const SpecialCustomizationsSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Placeholder settings
    final placeholderEnabled = useAppSettingsState(AppSettingsEnum.placeholderImagesEnabled);
    final placeholderResolution = useAppSettingsState(AppSettingsEnum.placeholderMaxResolution);
    final placeholderCompression = useAppSettingsState(AppSettingsEnum.placeholderCompression);

    // OCR settings
    final ocrEnabled = useAppSettingsState(AppSettingsEnum.localOcrEnabled);
    final ocrMode = useAppSettingsState(AppSettingsEnum.localOcrMode);
    final ocrAccuracy = useAppSettingsState(AppSettingsEnum.localOcrAccuracy);
    final ocrScope = useAppSettingsState(AppSettingsEnum.localOcrScope);

    // Placeholder storage indicator
    final storageUsed = useState<int?>(null);

    useEffect(() {
      () async {
        final service = ref.read(placeholderServiceProvider);
        storageUsed.value = await service.getTotalStorageUsed();
      }();
      return null;
    }, [placeholderEnabled.value]);

    final resolutionLabels = ['240p', '480p', '720p'];
    final ocrModeLabels = [
      'special_customizations_ocr_mode_server'.tr(),
      'special_customizations_ocr_mode_local'.tr(),
    ];
    final ocrAccuracyLabels = [
      'special_customizations_ocr_accuracy_low'.tr(),
      'special_customizations_ocr_accuracy_balanced'.tr(),
      'special_customizations_ocr_accuracy_high'.tr(),
    ];
    final ocrScopeLabels = [
      'special_customizations_ocr_scope_new'.tr(),
      'special_customizations_ocr_scope_all'.tr(),
    ];

    final settingWidgets = <Widget>[
      // -----------------------------------------------------------------------
      // Section: Placeholder images
      // -----------------------------------------------------------------------
      _SectionHeader('special_customizations_placeholder_section_title'.tr()),
      SettingsSwitchListTile(
        valueNotifier: placeholderEnabled,
        title: 'special_customizations_placeholder_enabled_title'.tr(),
        subtitle: 'special_customizations_placeholder_enabled_subtitle'.tr(),
        icon: Icons.image_outlined,
      ),
      if (placeholderEnabled.value) ...[
        // Resolution picker
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          dense: true,
          title: Text(
            'special_customizations_placeholder_resolution_title'.tr(
              namedArgs: {'resolution': resolutionLabels[placeholderResolution.value]},
            ),
            style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: _SegmentedRow<int>(
            items: List.generate(3, (i) => i),
            labels: resolutionLabels,
            selected: placeholderResolution.value,
            onSelected: (v) => placeholderResolution.value = v,
          ),
        ),
        // Compression quality
        SettingsSliderListTile(
          text: 'special_customizations_placeholder_compression_title'.tr(
            namedArgs: {'quality': '${placeholderCompression.value}'},
          ),
          valueNotifier: placeholderCompression,
          minValue: 10,
          maxValue: 95,
          noDivisons: 17,
          label: '${placeholderCompression.value}%',
        ),
        // Storage indicator
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          dense: true,
          leading: const Icon(Icons.storage_outlined),
          title: Text(
            'special_customizations_placeholder_storage_title'.tr(),
            style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            storageUsed.value == null
                ? '...'
                : formatHumanReadableBytes(storageUsed.value ?? 0, 2),
            style: context.textTheme.bodyMedium,
          ),
          trailing: TextButton(
            onPressed: () async {
              await ref.read(placeholderServiceProvider).clearAll();
              storageUsed.value = 0;
            },
            child: Text(
              'special_customizations_placeholder_clear_button'.tr(),
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],

      const SizedBox(height: 8),

      // -----------------------------------------------------------------------
      // Section: On-device OCR
      // -----------------------------------------------------------------------
      _SectionHeader('special_customizations_ocr_section_title'.tr()),
      SettingsSwitchListTile(
        valueNotifier: ocrEnabled,
        title: 'special_customizations_ocr_enabled_title'.tr(),
        subtitle: 'special_customizations_ocr_enabled_subtitle'.tr(),
        icon: Icons.text_fields_outlined,
      ),
      if (ocrEnabled.value) ...[
        // OCR Mode
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          dense: true,
          title: Text(
            'special_customizations_ocr_mode_title'.tr(),
            style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          subtitle: _SegmentedRow<int>(
            items: List.generate(2, (i) => i),
            labels: ocrModeLabels,
            selected: ocrMode.value,
            onSelected: (v) => ocrMode.value = v,
          ),
        ),
        // OCR accuracy (only relevant for local mode)
        if (ocrMode.value == 1) ...[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            dense: true,
            title: Text(
              'special_customizations_ocr_accuracy_title'.tr(),
              style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
            ),
            subtitle: _SegmentedRow<int>(
              items: List.generate(3, (i) => i),
              labels: ocrAccuracyLabels,
              selected: ocrAccuracy.value,
              onSelected: (v) => ocrAccuracy.value = v,
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            dense: true,
            title: Text(
              'special_customizations_ocr_scope_title'.tr(),
              style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
            ),
            subtitle: _SegmentedRow<int>(
              items: List.generate(2, (i) => i),
              labels: ocrScopeLabels,
              selected: ocrScope.value,
              onSelected: (v) => ocrScope.value = v,
            ),
          ),
        ],
      ],
      const SizedBox(height: 60),
    ];

    return SettingsSubPageScaffold(settings: settingWidgets);
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        title,
        style: context.textTheme.titleSmall?.copyWith(
          color: context.primaryColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A horizontally scrollable segmented control.
class _SegmentedRow<T> extends StatelessWidget {
  final List<T> items;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onSelected;

  const _SegmentedRow({
    required this.items,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 8),
              child: ChoiceChip(
                label: Text(labels[i]),
                selected: selected == items[i],
                onSelected: (_) => onSelected(items[i]),
              ),
            ),
        ],
      ),
    );
  }
}
