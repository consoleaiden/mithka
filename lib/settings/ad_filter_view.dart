//
//  ad_filter_view.dart
//
//  Ad filter settings: the on/off switch, what happens to a matching message,
//  and the keyword list matched against channel content.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/settings_selection_row.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import 'ad_filter.dart';

class AdFilterView extends StatefulWidget {
  const AdFilterView({super.key});

  @override
  State<AdFilterView> createState() => _AdFilterViewState();
}

class _AdFilterViewState extends State<AdFilterView> {
  final _controller = TextEditingController();
  final _filter = AdFilter.shared;

  @override
  void initState() {
    super.initState();
    _filter.addListener(_onChanged);
  }

  @override
  void dispose() {
    _filter.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _add() {
    _filter.add(_controller.text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final keywords = _filter.keywords;
    final enabled = _filter.enabled;
    return SettingsPageScaffold(
      title: AppStringKeys.adFilterTitle.l10n(context),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsCard.rows(
            rows: [
              SettingsSwitchRow(
                title: AppStringKeys.adFilterTitle,
                value: enabled,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.ban),
                onChanged: _filter.setEnabled,
              ),
              SettingsSelectionRow<AdFilterAction>(
                title: AppStringKeys.adFilterActionTitle,
                value: _filter.action == AdFilterAction.hide
                    ? AppStringKeys.adFilterActionHide
                    : AppStringKeys.adFilterActionCollapse,
                enabled: enabled,
                options: const [
                  SettingsSelectionOption<AdFilterAction>(
                    id: 'ad-action-hide',
                    value: AdFilterAction.hide,
                    label: AppStringKeys.adFilterActionHide,
                    subtitle: AppStringKeys.adFilterActionHideSubtitle,
                    icon: HeroAppIcons.eyeSlash,
                  ),
                  SettingsSelectionOption<AdFilterAction>(
                    id: 'ad-action-collapse',
                    value: AdFilterAction.collapse,
                    label: AppStringKeys.adFilterActionCollapse,
                    subtitle: AppStringKeys.adFilterActionCollapseSubtitle,
                    icon: HeroAppIcons.eye,
                  ),
                ],
                isSelected: (action) => _filter.action == action,
                onSelected: _filter.setAction,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _inputCard(),
          const SizedBox(height: AppSpacing.lg),
          if (keywords.isEmpty)
            SettingsNote(text: AppStringKeys.adFilterEmpty.l10n(context))
          else
            _keywordCard(keywords),
          const SizedBox(height: AppSpacing.lg),
          SettingsNote(text: AppStringKeys.adFilterDescription.l10n(context)),
        ],
      ),
    );
  }

  Widget _inputCard() {
    final c = context.colors;
    return SettingsPanel(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(),
              style: TextStyle(fontSize: 16, color: c.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: AppStringKeys.adFilterInputPlaceholder.l10n(context),
                hintStyle: TextStyle(color: c.textTertiary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _add,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text(
                AppStringKeys.imageEditAdd.l10n(context),
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.onBrand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _keywordCard(List<String> keywords) {
    final c = context.colors;
    return SettingsCard.rows(
      rows: [
        for (final keyword in keywords)
          SettingsRow(
            title: keyword,
            leading: SettingsLeadingIcon(
              icon: HeroAppIcons.ban,
              color: AppTheme.tagRed,
            ),
            showChevron: false,
            trailing: AppInteractiveSurface(
              semanticLabel: AppStringKeys.chatInfoRemove.l10n(context),
              onTap: () => _filter.remove(keyword),
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: AppIcon(
                  HeroAppIcons.xmark,
                  size: 16,
                  color: c.textTertiary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
