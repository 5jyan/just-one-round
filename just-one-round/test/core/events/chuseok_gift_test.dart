import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/core/events/chuseok_gift.dart';

void main() {
  test(
    'status exposes an account-wide popup only while eligible and unclaimed',
    () {
      final status = ChuseokGiftStatus.fromJson({
        'event_id': 'chuseok-2026',
        'eligible': true,
        'claimed': false,
      });

      expect(status.eventId, 'chuseok-2026');
      expect(status.shouldShow, isTrue);
      expect(
        ChuseokGiftStatus.fromJson({
          'eligible': true,
          'claimed': true,
        }).shouldShow,
        isFalse,
      );
      expect(
        ChuseokGiftStatus.fromJson({
          'eligible': false,
          'claimed': false,
        }).shouldShow,
        isFalse,
      );
    },
  );

  test(
    'claim result distinguishes a new gift from a retry-safe completion',
    () {
      final granted = ChuseokGiftClaim.fromJson({
        'eligible': true,
        'claimed': true,
        'granted': true,
        'tickets_granted': 1,
        'challenge_tickets': 3,
      });
      final retry = ChuseokGiftClaim.fromJson({
        'eligible': true,
        'claimed': true,
        'granted': false,
        'tickets_granted': 0,
        'challenge_tickets': 3,
      });

      expect(granted.completed, isTrue);
      expect(granted.granted, isTrue);
      expect(retry.completed, isTrue);
      expect(retry.granted, isFalse);
    },
  );

  test(
    'migration enforces the Seoul cutoff and a unique authenticated claim',
    () {
      final sql = File(
        'supabase/migrations/20260924000200_chuseok_2026_gift.sql',
      ).readAsStringSync();

      expect(sql, contains('create table public.chuseok_gift_claims'));
      expect(sql, contains("primary key (event_id, user_id)"));
      expect(
        sql,
        contains(
          "(now() at time zone 'Asia/Seoul')::date <= date '2026-09-25'",
        ),
      );
      expect(sql, contains('create function public.get_chuseok_gift_status()'));
      expect(sql, contains('create function public.claim_chuseok_gift()'));
      expect(sql, contains('on conflict (event_id, user_id) do nothing'));
      expect(
        sql,
        contains(
          'grant execute on function public.claim_chuseok_gift() to authenticated',
        ),
      );
    },
  );
}
