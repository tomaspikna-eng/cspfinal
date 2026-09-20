alter function public.get_my_player_profile_dashboard() security definer;
alter function public.get_my_pro_plus_dashboard() security definer;

grant execute on function public.get_my_player_profile_dashboard() to authenticated;
grant execute on function public.get_my_pro_plus_dashboard() to authenticated;