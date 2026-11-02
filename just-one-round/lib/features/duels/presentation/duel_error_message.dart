import 'package:supabase_flutter/supabase_flutter.dart';

/// Converts server and local duel failures into text that is safe to show in
/// a snackbar or an inline error panel.
///
/// PostgREST's `toString()` includes the raw message, code, details and hint.
/// That is useful for logs, but it exposes implementation details (and, for
/// test accounts, an English server error) when shown directly to a player.
String duelFriendlyError(Object error) {
  final searchable = switch (error) {
    PostgrestException(
      :final message,
      :final code,
      :final details,
      :final hint,
    ) =>
      <String>[
        message,
        if (code != null) code,
        if (details != null) details.toString(),
        if (hint != null) hint,
      ],
    _ => <String>[error.toString()],
  };
  final text = searchable.join(' ').toLowerCase();

  if (text.contains('duel maintenance is unavailable')) {
    return '지금은 대결을 시작할 수 없어요. 잠시 후 다시 시도해 주세요.';
  }
  if (text.contains('duels unavailable for test accounts') ||
      text.contains('test account')) {
    return '테스트 계정에서는 1:1 대결을 이용할 수 없어요.';
  }
  if (text.contains('duel_enabled') ||
      text.contains('duels disabled') ||
      text.contains('duel feature') && text.contains('disabled')) {
    return '지금은 1:1 대결을 이용할 수 없어요. 잠시 후 다시 시도해 주세요.';
  }
  if (text.contains('insufficient') &&
          (text.contains('coin') || text.contains('balance')) ||
      text.contains('잔액')) {
    return '코인이 부족해서 대결을 시작할 수 없어요.';
  }
  if (text.contains('unsupported') || text.contains('runtime_mismatch')) {
    return '상대방 앱을 업데이트한 뒤 다시 입장해 주세요.';
  }
  if (text.contains('target user') && text.contains('not found') ||
      text.contains('opponent') && text.contains('not found')) {
    return '상대를 찾을 수 없어요. 랭킹에서 다시 선택해 주세요.';
  }
  if (text.contains('stake') || text.contains('wager')) {
    return '걸 코인 금액을 확인한 뒤 다시 시도해 주세요.';
  }
  if (text.contains('expired') || text.contains('waiting window')) {
    return '대결 요청이 만료됐어요. 새 대결을 신청해 주세요.';
  }
  if (text.contains('already joined') ||
      text.contains('already in this duel')) {
    return '이미 입장한 대결방이에요.';
  }
  if (text.contains('stale') || text.contains('session')) {
    return '방 연결이 바뀌었어요. 다시 입장해 주세요.';
  }

  // Messages deliberately created by the client are already suitable for a
  // player. Keep those without leaking arbitrary exception internals.
  if (error is StateError) {
    final local = error.message.trim();
    if (local.isNotEmpty) return local;
  }

  if (error is FormatException) {
    return '대결 정보를 읽지 못했어요. 잠시 후 다시 시도해 주세요.';
  }

  return '대결 서버와 통신하지 못했어요. 잠시 후 다시 시도해 주세요.';
}
