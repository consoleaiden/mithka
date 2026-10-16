//
//  ad_filter.dart
//
//  Local keyword-based ad filter for channel content. A message whose text
//  matches one of the rules is handled according to [AdFilterAction]: dropped
//  from the transcript entirely, or collapsed into a placeholder the reader can
//  expand.
//
//  Rules share the grammar documented in keyword_rules.dart.
//

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'keyword_rules.dart';

/// What the ad filter does with a message it matches.
enum AdFilterAction {
  /// The message never reaches the transcript.
  hide,

  /// The message collapses into a placeholder that expands on tap.
  collapse,
}

class AdFilter extends ChangeNotifier {
  AdFilter._();
  static final AdFilter shared = AdFilter._();

  static const _keywordsKey = 'adFilterKeywords';
  static const _enabledKey = 'adFilterEnabled';
  static const _actionKey = 'adFilterAction';

  SharedPreferences? _prefs;
  List<String> _keywords = const [];
  bool _enabled = false;
  AdFilterAction _action = AdFilterAction.collapse;
  KeywordRuleSet _rules = KeywordRuleSet.empty;

  List<String> get keywords => List.unmodifiable(_keywords);
  bool get enabled => _enabled;
  AdFilterAction get action => _action;

  /// Whether the filter can affect anything at all.
  bool get isActive => _enabled && _keywords.isNotEmpty;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _keywords = normalizeKeywordList(
      prefs.getStringList(_keywordsKey) ?? const [],
    );
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _action = AdFilterAction.values.firstWhere(
      (value) => value.name == prefs.getString(_actionKey),
      orElse: () => AdFilterAction.collapse,
    );
    _rules = KeywordRuleSet.compile(_keywords);
    notifyListeners();
  }

  /// True when [text] matches a rule and the filter is turned on.
  bool matches(String text) => isActive && _rules.matches(text);

  /// True for a match that collapses instead of disappearing — i.e. a match
  /// whose action is [AdFilterAction.collapse].
  bool collapses(String text) =>
      matches(text) && _action == AdFilterAction.collapse;

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _prefs?.setBool(_enabledKey, value);
    notifyListeners();
  }

  void setAction(AdFilterAction value) {
    if (_action == value) return;
    _action = value;
    _prefs?.setString(_actionKey, value.name);
    notifyListeners();
  }

  void add(String value) {
    final keyword = normalizeKeyword(value);
    if (keyword == null) return;
    if (_keywords.any((k) => k.toLowerCase() == keyword.toLowerCase())) return;
    _keywords = [..._keywords, keyword];
    _save();
  }

  void remove(String value) {
    final lower = value.toLowerCase();
    final next = _keywords.where((k) => k.toLowerCase() != lower).toList();
    if (next.length == _keywords.length) return;
    _keywords = next;
    _save();
  }

  void replaceAll(List<String> values) {
    _keywords = normalizeKeywordList(values);
    _save();
  }

  void _save() {
    _prefs?.setStringList(_keywordsKey, _keywords);
    _rules = KeywordRuleSet.compile(_keywords);
    notifyListeners();
  }
}
