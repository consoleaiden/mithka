//
//  minor_mode_view.dart
//
//  Underage mode settings: the on/off switch and the keyword list whose matches
//  are removed from the transcript entirely.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import 'minor_mode_filter.dart';

class MinorModeView extends StatefulWidget {
  const MinorModeView({super.key});

  @override
  State<MinorModeView> createState() => _MinorModeViewState();
}

class _MinorModeViewState extends State<MinorModeView> {
  final _controller = TextEditingController();
  final _filter = MinorModeFilter.shared;

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
    return SettingsPageScaffold(
      title: AppStringKeys.minorModeTitle.l10n(context),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsCard.rows(
            rows: [
              SettingsSwitchRow(
                title: AppStringKeys.minorModeTitle,
                value: _filter.enabled,
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.shieldHalved,
                ),
                onChanged: _filter.setEnabled,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _inputCard(),
          const SizedBox(height: AppSpacing.lg),
          if (keywords.isEmpty)
            SettingsNote(text: AppStringKeys.minorModeEmpty.l10n(context))
          else
            _keywordCard(keywords),
          const SizedBox(height: AppSpacing.lg),
          SettingsNote(
            text: AppStringKeys.minorModeDescription.l10n(context),
          ),
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
                hintText: AppStringKeys.minorModeInputPlaceholder.l10n(context),
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
