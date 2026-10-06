-- One-time reset for the two dedicated physical-device push smoke accounts.
-- Keep gifts, balances, push tokens, and every other account untouched.

delete from public.social_notifications
where action_type in ('poke', 'boast')
  and created_at >= now() - interval '24 hours'
  and (
    sender_id in (
      '8a1605f9-a02c-438f-8500-7c4b16943a70'::uuid,
      'cb7cf631-98d8-4ef4-81d2-418675821fab'::uuid
    )
    or recipient_id in (
      '8a1605f9-a02c-438f-8500-7c4b16943a70'::uuid,
      'cb7cf631-98d8-4ef4-81d2-418675821fab'::uuid
    )
  );
