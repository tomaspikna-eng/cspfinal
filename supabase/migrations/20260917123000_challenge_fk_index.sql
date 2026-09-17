-- Cover the reverse lookup used when a challenge is removed or archived.
create index if not exists player_challenges_challenge_id_idx
  on public.player_challenges(challenge_id);

