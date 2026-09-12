alter table public.matches
  drop constraint if exists matches_bracket_side_check;

alter table public.matches
  add constraint matches_bracket_side_check
  check (
    bracket_side is null
    or bracket_side in (
      'group','single','winners','losers','grand_final','placement',
      'W','L','GF','A','B'
    )
  );

