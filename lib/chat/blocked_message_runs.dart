import '../tdlib/td_models.dart';

/// Whether [message] is collapsed into a tappable placeholder rather than
/// rendered normally.
///
/// Two independent filters collapse messages: the blocked-user feature and the
/// ad filter. A message is never collapsed by both, because the transcript pass
/// writes at most one of the flags.
bool isCollapsedMessage(ChatMessage message) =>
    message.blockedByUser || message.blockedByAdFilter;

/// Returns the exclusive end index of one uninterrupted collapsed-message run.
/// Date/unread boundaries are supplied by the transcript so those semantic
/// separators remain visible even when the adjacent senders are collapsed.
///
/// A run only spans messages collapsed for the *same* reason. A blocked-user
/// message next to an ad-filtered one therefore keeps two placeholders — each
/// with its own label — instead of merging into one ambiguous blob.
int blockedMessageRunEnd(
  List<ChatMessage> messages,
  int start, {
  required bool Function(int index) startsNewSection,
}) {
  if (start < 0 || start >= messages.length) return start;
  final first = messages[start];
  if (!isCollapsedMessage(first)) return start;
  var end = start + 1;
  while (end < messages.length &&
      messages[end].blockedByUser == first.blockedByUser &&
      messages[end].blockedByAdFilter == first.blockedByAdFilter &&
      isCollapsedMessage(messages[end]) &&
      !startsNewSection(end)) {
    end++;
  }
  return end;
}
