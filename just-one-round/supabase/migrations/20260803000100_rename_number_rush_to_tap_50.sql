-- `number_rush` is the canonical game id for the game branded as 탭50.
-- Update the immutable metadata snapshot first so the catalog trigger can
-- accept the presentation-only rename without changing the rules version.
update public.game_rule_versions
set display_name = '탭50'
where game_id = 'number_rush';

update public.games
set display_name = '탭50'
where id = 'number_rush';
