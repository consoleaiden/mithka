import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'ad_filter.dart';
import 'ad_filter_view.dart';
import 'blocked_user_service.dart';
import 'country_message_filter.dart';
import 'country_message_filter_view.dart';
import 'hidden_sender_store.dart';
import 'hidden_senders_view.dart';
import 'keyword_blocker_view.dart';
import 'minor_mode_filter.dart';
import 'minor_mode_view.dart';

class BlockingSettingsView extends StatelessWidget {
  const BlockingSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final country = CountryMessageFilter.shared;
    return SettingsPageScaffold(
      title: AppStringKeys.settingsContentFilters.l10n(context),
      onBack: () => Navigator.of(context).pop(),
      child: ListenableBuilder(
        listenable: country,
        builder: (context, _) => SettingsListView(
          children: [
            _card(context, [
              SettingsSwitchRow(
                title: AppStringKeys.appearanceHideBlockedUserMessages,
                value: theme.hideBlockedUserMessages,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.eyeSlash),
                onChanged: (value) {
                  theme.hideBlockedUserMessages = value;
                  BlockedUserService.shared.enabled = value;
                  if (value) {
                    BlockedUserService.shared.loadBlockedUsers();
                  }
                },
              ),
              SettingsRow(
                title: AppStringKeys.keywordBlockerTitle,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.ban),
                onTap: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => const KeywordBlockerView(),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: AdFilter.shared,
                builder: (context, _) => SettingsRow(
                  key: const ValueKey('content-filters-ad-filter'),
                  title: AppStringKeys.adFilterTitle,
                  value: _ruleCountValue(
                    enabled: AdFilter.shared.enabled,
                    count: AdFilter.shared.keywords.length,
                  ),
                  leading: const SettingsLeadingIcon(
                    icon: HeroAppIcons.volumeHigh,
                  ),
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute<void>(
                      pageBuilder: (_, _, _) => const AdFilterView(),
                    ),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: MinorModeFilter.shared,
                builder: (context, _) => SettingsRow(
                  key: const ValueKey('content-filters-minor-mode'),
                  title: AppStringKeys.minorModeTitle,
                  value: _ruleCountValue(
                    enabled: MinorModeFilter.shared.enabled,
                    count: MinorModeFilter.shared.keywords.length,
                  ),
                  leading: const SettingsLeadingIcon(
                    icon: HeroAppIcons.shieldHalved,
                  ),
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute<void>(
                      pageBuilder: (_, _, _) => const MinorModeView(),
                    ),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: HiddenSenderStore.shared,
                builder: (context, _) {
                  final count = HiddenSenderStore.shared.entries.length;
                  return SettingsRow(
                    key: const ValueKey('content-filters-hidden-members'),
                    title: AppStringKeys.hiddenSendersTitle,
                    value: count == 0 ? '' : '$count',
                    leading: const SettingsLeadingIcon(
                      icon: HeroAppIcons.users,
                    ),
                    onTap: () => Navigator.of(context).push(
                      AppPageRoute<void>(
                        pageBuilder: (_, _, _) => const HiddenSendersView(),
                      ),
                    ),
                  );
                },
              ),
            ]),
            SettingsSection(
              titleKey: AppStringKeys.blockingCountry,
              rows: [
                SettingsRow(
                  title: AppStringKeys.blockingCountry,
                  value: country.selectedCountries.isEmpty
                      ? AppStringKeys.blockingCountryOff
                      : AppStrings.t(AppStringKeys.blockingCountrySelected, {
                          'value1': country.selectedCountries.length,
                        }),
                  leading: const SettingsLeadingIcon(icon: HeroAppIcons.globe),
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute<void>(
                      pageBuilder: (_, _, _) =>
                          const CountryMessageFilterView(),
                    ),
                  ),
                ),
              ],
            ),
            const SettingsNote(text: AppStringKeys.blockingCountryDescription),
            SettingsSection(
              titleKey: AppStringKeys.blockingExemptions,
              dividerInset: AppMetric.settingsTextDividerInset,
              rows: [
                SettingsSwitchRow(
                  title: AppStringKeys.blockingExemptCommonPrivateGroup,
                  value: country.exemptCommonPrivateGroup,
                  onChanged: country.setExemptCommonPrivateGroup,
                ),
                SettingsSwitchRow(
                  title: AppStringKeys.blockingExemptThreeCommonGroups,
                  value: country.exemptThreeCommonGroups,
                  onChanged: country.setExemptThreeCommonGroups,
                ),
                SettingsSwitchRow(
                  title: AppStringKeys.blockingExemptPlainText,
                  value: country.exemptPlainText,
                  onChanged: country.setExemptPlainText,
                ),
                SettingsSwitchRow(
                  title: AppStringKeys.blockingExemptNonDefaultAvatar,
                  value: country.exemptNonDefaultAvatar,
                  onChanged: country.setExemptNonDefaultAvatar,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> children) =>
      SettingsCard.rows(rows: children);
}

/// Trailing summary for a keyword-driven filter row: "Off" until it is both
/// switched on and has at least one rule, then the rule count.
String _ruleCountValue({required bool enabled, required int count}) {
  if (!enabled || count == 0) return AppStringKeys.blockingCountryOff;
  return AppStrings.t(AppStringKeys.filterRuleCount, {'value1': count});
}
