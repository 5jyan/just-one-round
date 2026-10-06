-- Player-facing rename only. Keep western_duel ID, version, sessions, and scores.
-- Rollback: set both display_name values below back to '서부의 한 발'.
update public.game_rule_versions
set display_name = '딱 한 발만'
where game_id = 'western_duel';

update public.games
set display_name = '딱 한 발만'
where id = 'western_duel';
