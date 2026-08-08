-- Keep games introduced by build 11 out of the daily rotation until the
-- corresponding store releases are publicly installable.
update public.games
set minimum_app_build = 11,
    is_active = false
where id in ('ten_pitch_slugger', 'ramen_timer');
