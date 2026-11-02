begin;
select plan(20);
insert into auth.users(id,is_anonymous) values
 ('af000001-0000-4000-8000-000000000001',true),
 ('af000002-0000-4000-8000-000000000002',true),
 ('af000003-0000-4000-8000-000000000003',true),
 ('af000004-0000-4000-8000-000000000004',true);
update public.profiles set coin_balance=500, is_test_account=false
 where id in ('af000001-0000-4000-8000-000000000001','af000002-0000-4000-8000-000000000002');
update public.games set is_active=true, duel_enabled=true where id='dung_dodge_v2';
select set_config('request.jwt.claim.sub','af000001-0000-4000-8000-000000000001',true);
insert into public.duel_matches(id,requester_id,opponent_id,game_id,game_version,stake,game_duration_seconds,client_request_id,waiting_expires_at)
values ('ae000001-0000-4000-8000-000000000001','af000001-0000-4000-8000-000000000001','af000002-0000-4000-8000-000000000002','dung_dodge_v2',1,100,300,'ab000001-0000-4000-8000-000000000001',now()-interval '1 second');
insert into public.duel_runs(duel_id,user_id,role,joined_at,presence_expires_at,session_token,loading_complete)
values
 ('ae000001-0000-4000-8000-000000000001','af000001-0000-4000-8000-000000000001','requester',now(),now()+interval '1 minute','ac000001-0000-4000-8000-000000000001',true),
 ('ae000001-0000-4000-8000-000000000001','af000002-0000-4000-8000-000000000002','opponent',now(),now()+interval '1 minute','ac000002-0000-4000-8000-000000000002',true);
select is(public.set_duel_ready('ae000001-0000-4000-8000-000000000001',true,true,'ac000001-0000-4000-8000-000000000001')->>'start_failure_reason','room_expired','expired room refuses ready');
select is((select status from public.duel_matches where id='ae000001-0000-4000-8000-000000000001'),'expired','expired state persists');
select is((select coin_balance::text from public.profiles where id='af000001-0000-4000-8000-000000000001'),'500','expired room does not charge');
update public.duel_matches set status='waiting' where id='ae000001-0000-4000-8000-000000000001';
select throws_ok($$ update public.duel_matches set status='starting' where id='ae000001-0000-4000-8000-000000000001' $$,'P0001','duel room has expired','start transition also guards the deadline');
update public.duel_matches set status='waiting',waiting_expires_at=now()+interval '1 minute' where id='ae000001-0000-4000-8000-000000000001';
update public.games set duel_enabled=false where id='dung_dodge_v2';
select is(public.set_duel_ready('ae000001-0000-4000-8000-000000000001',true,true,'ac000001-0000-4000-8000-000000000001')->>'start_failure_reason','game_unavailable','disabled game refuses ready');
select throws_ok($$ update public.duel_matches set status='starting' where id='ae000001-0000-4000-8000-000000000001' $$,'P0001','duel game is unavailable','start transition guards the game gate');
select is((select coin_balance::text from public.profiles where id='af000002-0000-4000-8000-000000000002'),'500','disabled room does not charge');
update public.games set duel_enabled=true where id='dung_dodge_v2';
select throws_ok($$ update public.profiles set is_test_account=true where id='af000002-0000-4000-8000-000000000002' $$,'P0001','finish or cancel the active duel before changing test mode','test isolation cannot change during a duel');
select is((select is_test_account::text from public.profiles where id='af000002-0000-4000-8000-000000000002'),'false','blocked mode change leaves isolation intact');
select cron.alter_job((select jobid from cron.job where jobname='just-one-round-maintain-duels'), active => false);
select throws_ok($$ update public.duel_matches set status='starting' where id='ae000001-0000-4000-8000-000000000001' $$,'P0001','duel maintenance is unavailable','offline settlement unavailable blocks starting');
select cron.alter_job((select jobid from cron.job where jobname='just-one-round-maintain-duels'), active => true);
update public.duel_matches set status='settled',outcome='requester_win' where id='ae000001-0000-4000-8000-000000000001';
insert into public.duel_payouts(duel_id,user_id,payout_kind,amount,credited_amount)
values ('ae000001-0000-4000-8000-000000000001','af000002-0000-4000-8000-000000000002','payout',100,0);
select throws_ok($$ select public.void_duels_for_account('af000001-0000-4000-8000-000000000001') $$,'P0001','another participant has a pending duel payout','deletion cannot remove opponent payout');
select is((select credited_amount::text from public.duel_payouts where duel_id='ae000001-0000-4000-8000-000000000001'),'0','opponent payout remains intact');
select is((select count(*)::text from public.duel_account_deletions where user_id='af000001-0000-4000-8000-000000000001'),'0','failed cleanup rolls back deletion guard');
update public.duel_payouts set credited_amount=amount where duel_id='ae000001-0000-4000-8000-000000000001';
select lives_ok($$ select public.void_duels_for_account('af000001-0000-4000-8000-000000000001') $$,'cleanup succeeds after payout resolved');
select is((select count(*)::text from public.duel_account_deletions where user_id='af000001-0000-4000-8000-000000000001'),'1','cleanup persists deletion guard');
select throws_ok($$ insert into public.duel_matches(requester_id,opponent_id,game_id,game_version,stake,game_duration_seconds,client_request_id) values ('af000001-0000-4000-8000-000000000001','af000002-0000-4000-8000-000000000002','dung_dodge_v2',1,100,300,gen_random_uuid()) $$,'P0001','duel participant account is being deleted','new room blocked while account deletion is pending');
select ok(not has_table_privilege('authenticated','public.duel_account_deletions','select'),'deletion guard is private');

-- An authenticated participant can recover an overdue game even if the
-- periodic worker has not yet processed it.
update public.profiles set coin_balance=400 where id in
 ('af000003-0000-4000-8000-000000000003','af000004-0000-4000-8000-000000000004');
insert into public.duel_matches(id,requester_id,opponent_id,game_id,game_version,stake,game_duration_seconds,client_request_id,status,charged,start_at,submit_deadline)
values ('ae000002-0000-4000-8000-000000000002','af000003-0000-4000-8000-000000000003','af000004-0000-4000-8000-000000000004','dung_dodge_v2',1,100,300,'ab000002-0000-4000-8000-000000000002','playing',true,now()-interval '10 minutes',now()-interval '1 minute');
insert into public.duel_runs(duel_id,user_id,role,run_status,result_kind,raw_score,duration_ms)
values
 ('ae000002-0000-4000-8000-000000000002','af000003-0000-4000-8000-000000000003','requester','submitted','valid',1000,1000),
 ('ae000002-0000-4000-8000-000000000002','af000004-0000-4000-8000-000000000004','opponent','starting',null,null,null);
select set_config('request.jwt.claim.sub','af000003-0000-4000-8000-000000000003',true);
select is(public.get_duel('ae000002-0000-4000-8000-000000000002')->>'status','settled','viewing overdue room recovers settlement');
select is((select coin_balance::text from public.profiles where id='af000003-0000-4000-8000-000000000003'),'600','recovered winner receives escrow');
select is((select run_status from public.duel_runs where duel_id='ae000002-0000-4000-8000-000000000002' and role='opponent'),'no_result','overdue opponent terminates once');
select * from finish();
rollback;
