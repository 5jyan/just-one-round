-- This is a player-facing title change, not a rules change. Keep the stored
-- snapshots and current catalog row aligned before the immutability trigger
-- validates the current version.
update public.game_rule_versions
set display_name = '홈런왕'
where game_id = 'ten_pitch_slugger';

update public.games
set display_name = '홈런왕'
where id = 'ten_pitch_slugger';
