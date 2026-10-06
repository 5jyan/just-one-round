-- Decorate the existing authoritative ranking payload with server-validated
-- nickname color tokens.

alter function public.get_my_daily_result(date)
rename to get_my_daily_result_before_nickname_colors;

create function public.get_my_daily_result(target_date date default null)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  result jsonb := public.get_my_daily_result_before_nickname_colors(target_date);
  decorated_nearby jsonb;
  decorated_leaders jsonb;
begin
  select coalesce(jsonb_agg(entry || jsonb_build_object(
    'nickname_color', coalesce(profile.nickname_color, 'default'))
    order by (entry->>'rank')::integer), '[]'::jsonb)
  into decorated_nearby
  from jsonb_array_elements(coalesce(result->'nearby', '[]'::jsonb)) entry
  left join public.profiles profile on profile.id = nullif(entry->>'user_id', '')::uuid;

  select coalesce(jsonb_agg(entry || jsonb_build_object(
    'nickname_color', coalesce(profile.nickname_color, 'default'))
    order by (entry->>'rank')::integer), '[]'::jsonb)
  into decorated_leaders
  from jsonb_array_elements(coalesce(result->'leaders', '[]'::jsonb)) entry
  left join public.profiles profile on profile.id = nullif(entry->>'user_id', '')::uuid;

  return result || jsonb_build_object(
    'nearby', decorated_nearby,
    'leaders', decorated_leaders
  );
end;
$$;

revoke all on function public.get_my_daily_result_before_nickname_colors(date)
  from public, anon, authenticated, service_role;
revoke all on function public.get_my_daily_result(date) from public, anon;
grant execute on function public.get_my_daily_result(date) to authenticated;
