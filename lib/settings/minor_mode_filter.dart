//
//  minor_mode_filter.dart
//
//  Underage (minor) mode: a keyword list whose matches are removed from the
//  transcript completely, so unsuitable channel content is never rendered.
//
//  Unlike the ad filter there is no collapsed state — a match is always
//  dropped. Rules share the grammar documented in keyword_rules.dart.
//

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'keyword_rules.dart';

class MinorModeFilter extends ChangeNotifier {
  MinorModeFilter._();
  static final MinorModeFilter shared = MinorModeFilter._();

  static const _keywordsKey = 'minorModeKeywords';
  static const _enabledKey = 'minorModeEnabled';

  SharedPreferences? _prefs;
  List<String> _keywords = const [];
  bool _enabled = false;
  KeywordRuleSet _rules = KeywordRuleSet.empty;

  List<String> get keywords => List.unmodifiable(_keywords);
  bool get enabled => _enabled;

  /// Whether the filter can affect anything at all.
  bool get isActive => _enabled && _keywords.isNotEmpty;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _keywords = normalizeKeywordList(
      prefs.getStringList(_keywordsKey) ?? const [],
    );
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _rules = KeywordRuleSet.compile(_keywords);
    notifyListeners();
  }

  /// True when [text] matches a rule and the mode is turned on. Callers drop
  /// matching messages rather than collapsing them.
  bool matches(String text) => isActive && _rules.matches(text);

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _prefs?.setBool(_enabledKey, value);
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
