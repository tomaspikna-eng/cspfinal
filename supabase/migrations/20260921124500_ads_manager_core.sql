create table if not exists public.ads_advertisers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text,
  category text not null default 'other',
  website_url text,
  contact_name text,
  contact_email text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ads_placements (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  description text,
  surface text not null,
  format text not null default 'native',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.ads_campaigns (
  id uuid primary key default gen_random_uuid(),
  advertiser_id uuid not null references public.ads_advertisers(id) on delete cascade,
  name text not null,
  status text not null default 'draft' check (status in ('draft','active','paused','completed','archived')),
  category text not null default 'other',
  starts_at timestamptz,
  ends_at timestamptz,
  pricing_model text not null default 'fixed' check (pricing_model in ('fixed','cpm','cpc')),
  budget_eur numeric(12,2),
  cpm_eur numeric(10,4),
  cpc_eur numeric(10,4),
  countries text[] not null default '{}',
  sports text[] not null default '{}',
  account_plans text[] not null default '{}',
  min_age integer,
  max_age integer,
  creative_title text,
  creative_body text,
  creative_image_url text,
  cta_label text,
  cta_url text,
  sponsor_label text not null default 'Sponzorované',
  weight integer not null default 100 check (weight between 1 and 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (min_age is null or min_age between 0 and 120),
  check (max_age is null or max_age between 0 and 120),
  check (min_age is null or max_age is null or min_age <= max_age),
  check (lower(category) <> 'alcohol' or coalesce(min_age,18) >= 18)
);

create table if not exists public.ads_campaign_placements (
  campaign_id uuid not null references public.ads_campaigns(id) on delete cascade,
  placement_id uuid not null references public.ads_placements(id) on delete cascade,
  primary key (campaign_id, placement_id)
);

create table if not exists public.ads_events (
  id bigint generated always as identity primary key,
  campaign_id uuid not null references public.ads_campaigns(id) on delete cascade,
  placement_id uuid not null references public.ads_placements(id) on delete cascade,
  user_id uuid,
  event_type text not null check (event_type in ('impression','click')),
  occurred_at timestamptz not null default now(),
  country_code text,
  sport text,
  account_plan text
);

create index if not exists ads_campaigns_status_dates_idx on public.ads_campaigns(status,starts_at,ends_at);
create index if not exists ads_events_campaign_time_idx on public.ads_events(campaign_id,occurred_at);
create index if not exists ads_events_placement_time_idx on public.ads_events(placement_id,occurred_at);

alter table public.ads_advertisers enable row level security;
alter table public.ads_placements enable row level security;
alter table public.ads_campaigns enable row level security;
alter table public.ads_campaign_placements enable row level security;
alter table public.ads_events enable row level security;

drop policy if exists ads_advertisers_admin_all on public.ads_advertisers;
create policy ads_advertisers_admin_all on public.ads_advertisers
for all to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

drop policy if exists ads_placements_admin_all on public.ads_placements;
create policy ads_placements_admin_all on public.ads_placements
for all to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

drop policy if exists ads_campaigns_admin_all on public.ads_campaigns;
create policy ads_campaigns_admin_all on public.ads_campaigns
for all to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

drop policy if exists ads_campaign_placements_admin_all on public.ads_campaign_placements;
create policy ads_campaign_placements_admin_all on public.ads_campaign_placements
for all to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

drop policy if exists ads_events_admin_select on public.ads_events;
create policy ads_events_admin_select on public.ads_events
for select to authenticated
using (public.is_admin(auth.uid()));

grant select,insert,update,delete on public.ads_advertisers to authenticated;
grant select,insert,update,delete on public.ads_placements to authenticated;
grant select,insert,update,delete on public.ads_campaigns to authenticated;
grant select,insert,update,delete on public.ads_campaign_placements to authenticated;
grant select on public.ads_events to authenticated;

insert into public.ads_placements(key,name,description,surface,format)
values
 ('free_profile_feed','FREE profil · Feed','Native reklamná karta v profile FREE','profile','native'),
 ('tournament_partner','Turnaj · Partner','Partner kampane pri turnaji a výsledkoch','tournament','native'),
 ('scoreboard_break','Scoreboard · Prestávka','Reklama mimo aktívneho zapisovania skóre','scoreboard','fullscreen'),
 ('magazine_native','Magazín · Native','Native reklamná karta medzi článkami','magazine','native'),
 ('club_profile','Club profil','Partner alebo lokálna reklama v profile klubu','club_profile','native')
on conflict (key) do update set
 name=excluded.name,description=excluded.description,surface=excluded.surface,format=excluded.format;

create or replace function public.can_access_ads_manager()
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(public.is_admin((select auth.uid())),false);
$$;
grant execute on function public.can_access_ads_manager() to authenticated;

create or replace function public.ads_manager_dashboard()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select case when not public.is_admin((select auth.uid())) then
    jsonb_build_object('allowed',false)
  else
    jsonb_build_object(
      'allowed',true,
      'advertisers',(select count(*) from public.ads_advertisers where is_active),
      'active_campaigns',(select count(*) from public.ads_campaigns where status='active' and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>=now())),
      'impressions_30d',(select count(*) from public.ads_events where event_type='impression' and occurred_at>=now()-interval '30 days'),
      'clicks_30d',(select count(*) from public.ads_events where event_type='click' and occurred_at>=now()-interval '30 days'),
      'ctr_30d',(
        select case when count(*) filter(where event_type='impression')=0 then 0
        else round((count(*) filter(where event_type='click'))::numeric*100/
          (count(*) filter(where event_type='impression')),2) end
        from public.ads_events where occurred_at>=now()-interval '30 days'
      )
    )
  end;
$$;
grant execute on function public.ads_manager_dashboard() to authenticated;

create or replace function public.get_ad_for_placement(p_placement_key text,p_sport text default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_plan text;
  v_birth_year integer;
  v_age integer;
  v_result jsonb;
begin
  if v_uid is not null then
    select p.country_code,public.current_plan(p.id)::text,p.birth_year
      into v_country,v_plan,v_birth_year
    from public.profiles p where p.id=v_uid;
    if v_birth_year is not null then
      v_age:=extract(year from current_date)::integer-v_birth_year;
    end if;
  end if;

  select jsonb_build_object(
    'campaign_id',c.id,
    'placement_id',pl.id,
    'sponsor_label',c.sponsor_label,
    'title',c.creative_title,
    'body',c.creative_body,
    'image_url',c.creative_image_url,
    'cta_label',c.cta_label,
    'cta_url',c.cta_url,
    'advertiser_name',a.name
  )
  into v_result
  from public.ads_campaigns c
  join public.ads_advertisers a on a.id=c.advertiser_id and a.is_active
  join public.ads_campaign_placements cp on cp.campaign_id=c.id
  join public.ads_placements pl on pl.id=cp.placement_id and pl.is_active
  where pl.key=p_placement_key
    and c.status='active'
    and (c.starts_at is null or c.starts_at<=now())
    and (c.ends_at is null or c.ends_at>=now())
    and (cardinality(c.countries)=0 or v_country=any(c.countries))
    and (cardinality(c.sports)=0 or p_sport is null or p_sport=any(c.sports))
    and (cardinality(c.account_plans)=0 or v_plan=any(c.account_plans))
    and (c.min_age is null or (v_age is not null and v_age>=c.min_age))
    and (c.max_age is null or (v_age is not null and v_age<=c.max_age))
  order by random()*greatest(c.weight,1) desc
  limit 1;

  return coalesce(v_result,'{}'::jsonb);
end;
$$;
grant execute on function public.get_ad_for_placement(text,text) to authenticated,anon;

create or replace function public.record_ad_event(p_campaign_id uuid,p_placement_id uuid,p_event_type text,p_sport text default null)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_plan text;
begin
  if p_event_type not in ('impression','click') then raise exception 'invalid ad event'; end if;
  if v_uid is not null then
    select p.country_code,public.current_plan(p.id)::text into v_country,v_plan
    from public.profiles p where p.id=v_uid;
  end if;
  insert into public.ads_events(campaign_id,placement_id,user_id,event_type,country_code,sport,account_plan)
  values(p_campaign_id,p_placement_id,v_uid,p_event_type,v_country,p_sport,v_plan);
end;
$$;
grant execute on function public.record_ad_event(uuid,uuid,text,text) to authenticated,anon;