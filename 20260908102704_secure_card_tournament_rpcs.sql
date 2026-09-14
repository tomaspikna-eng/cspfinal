revoke execute on function public.get_card_tournament_state(uuid) from anon;
revoke execute on function public.start_card_tournament(uuid,integer,integer) from anon;
revoke execute on function public.set_card_player_eliminated(uuid,uuid,boolean) from anon;
revoke execute on function public.set_card_table_status(uuid,text) from anon;
revoke execute on function public.advance_card_round(uuid) from anon;
revoke execute on function public.complete_card_tournament(uuid,jsonb) from anon;
revoke execute on function public.reset_card_tournament(uuid) from anon;

