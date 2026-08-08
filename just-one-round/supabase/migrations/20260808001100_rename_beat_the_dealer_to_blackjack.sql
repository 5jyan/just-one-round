-- `beat_the_dealer` keeps its canonical id and rules version. This migration
-- changes only its player-facing title.
update public.game_rule_versions
set display_name = '블랙잭'
where game_id = 'beat_the_dealer';

update public.games
set display_name = '블랙잭'
where id = 'beat_the_dealer';
