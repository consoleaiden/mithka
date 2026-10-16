//
//  keyword_rules.dart
//
//  Shared compile + match logic for the local keyword rule lists used by the
//  spam blocker, the ad filter and the underage (minor) mode.
//
//  A rule is one of:
//    - `keyword`                  plain, case-insensitive substring match
//    - `re:<pattern>`             RegExp, case-insensitive
//    - `regex:<pattern>`          RegExp, case-insensitive
//    - `/<pattern>/<flags>`       RegExp; `i` in flags makes it insensitive
//
//  Compiling once per rule-list change (rather than once per message) matters:
//  `matches` runs for every loaded message in a transcript.
//

/// A compiled set of keyword rules. Immutable; rebuild it when the rules
/// change.
class KeywordRuleSet {
  const KeywordRuleSet._(this._regexes, this._plainLowered);

  static const KeywordRuleSet empty = KeywordRuleSet._(<RegExp>[], <String>[]);

  final List<RegExp> _regexes;
  final List<String> _plainLowered;

  bool get isEmpty => _regexes.isEmpty && _plainLowered.isEmpty;
  bool get isNotEmpty => !isEmpty;

  factory KeywordRuleSet.compile(Iterable<String> rules) {
    final regexes = <RegExp>[];
    final plain = <String>[];
    for (final rule in rules) {
      final regex = _regexFromRule(rule);
      if (regex != null) {
        regexes.add(regex);
      } else {
        plain.add(rule.toLowerCase());
      }
    }
    return KeywordRuleSet._(regexes, plain);
  }

  /// True when [text] satisfies at least one rule.
  ///
  /// Regex rules see the original text; plain keywords are tested against a
  /// single case-folded copy of it.
  bool matches(String text) {
    if (isEmpty || text.trim().isEmpty) return false;
    for (final regex in _regexes) {
      if (regex.hasMatch(text)) return true;
    }
    if (_plainLowered.isEmpty) return false;
    final normalized = text.toLowerCase();
    for (final keyword in _plainLowered) {
      if (normalized.contains(keyword)) return true;
    }
    return false;
  }

  static RegExp? _regexFromRule(String rule) {
    final trimmed = rule.trim();
    if (trimmed.startsWith('re:') || trimmed.startsWith('regex:')) {
      final pattern = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      if (pattern.isEmpty) return null;
      return _safeRegex(pattern, caseSensitive: false);
    }
    if (trimmed.length >= 2 && trimmed.startsWith('/')) {
      final lastSlash = trimmed.lastIndexOf('/');
      if (lastSlash > 0) {
        final pattern = trimmed.substring(1, lastSlash);
        final flags = trimmed.substring(lastSlash + 1);
        return _safeRegex(pattern, caseSensitive: !flags.contains('i'));
      }
    }
    return null;
  }

  static RegExp? _safeRegex(String pattern, {required bool caseSensitive}) {
    try {
      return RegExp(pattern, caseSensitive: caseSensitive);
    } catch (_) {
      return null;
    }
  }
}

/// Trims a rule, returning null for one that carries nothing to match.
String? normalizeKeyword(String value) {
  final keyword = value.trim();
  return keyword.isEmpty ? null : keyword;
}

/// Trims, drops empties and de-duplicates (case-insensitively), preserving
/// the first spelling of each rule.
List<String> normalizeKeywordList(Iterable<String> values) {
  final out = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final keyword = normalizeKeyword(value);
    if (keyword == null) continue;
    if (seen.add(keyword.toLowerCase())) out.add(keyword);
  }
  return out;
}
