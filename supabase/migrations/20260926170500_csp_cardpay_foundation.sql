-- CardPay payment foundation for Connect Sports Pro.
-- Products remain inactive until merchant credentials and bank tests are complete.

create sequence if not exists public.csp_cardpay_vs_seq
  as bigint start with 1 increment by 1 minvalue 1 maxvalue 99999999 no cycle;

create table if not exists public.csp_payment_products (
  code text primary key,
  plan public.profile_plan not null,
  billing_period text not null check (billing_period in ('monthly','annual')),
  name text not null,
  amount_cents integer not null check (amount_cents > 0),
  currency text not null default 'EUR' check (currency='EUR'),
  active boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.csp_payment_products(code,plan,billing_period,name,amount_cents,currency,active)
values
  ('pro_monthly','pro','monthly','PRO · mesačne',599,'EUR',false),
  ('pro_annual','pro','annual','PRO · ročne',5990,'EUR',false),
  ('pro_plus_monthly','pro_plus','monthly','PRO+ · mesačne',999,'EUR',false),
  ('pro_plus_annual','pro_plus','annual','PRO+ · ročne',9990,'EUR',false),
  ('ultra_monthly','ultra','monthly','ULTRA · mesačne',2490,'EUR',false),
  ('ultra_annual','ultra','annual','ULTRA · ročne',24900,'EUR',false)
on conflict(code) do update set plan=excluded.plan,billing_period=excluded.billing_period,
  name=excluded.name,amount_cents=excluded.amount_cents,currency=excluded.currency,updated_at=now();

alter table public.csp_payment_products enable row level security;
revoke all on table public.csp_payment_products from anon, authenticated;

create table if not exists public.csp_payment_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  provider text not null default 'cardpay' check (provider in ('cardpay')),
  product_code text not null references public.csp_payment_products(code) on update cascade,
  variable_symbol bigint not null unique,
  amount_cents integer not null check (amount_cents > 0),
  currency text not null default 'EUR' check (currency='EUR'),
  status text not null default 'pending' check (status in ('pending','paid','failed','cancelled','expired')),
  provider_result text,provider_auth_code text,provider_tid text,provider_timestamp text,provider_ecdsa_key text,
  paid_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists csp_payment_orders_user_created_idx
  on public.csp_payment_orders(user_id,created_at desc);
alter table public.csp_payment_orders enable row level security;
drop policy if exists csp_payment_orders_select_own on public.csp_payment_orders;
create policy csp_payment_orders_select_own on public.csp_payment_orders for select to authenticated
using (user_id=(select auth.uid()));

create table if not exists public.csp_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan public.profile_plan not null,
  billing_period text not null check (billing_period in ('monthly','annual')),
  status text not null default 'active' check (status in ('active','past_due','cancelled','expired')),
  current_period_start timestamptz not null,
  current_period_end timestamptz not null,
  renewal_mode text not null default 'manual_cardpay' check (renewal_mode in ('manual_cardpay','comfortpay')),
  last_order_id uuid references public.csp_payment_orders(id) on delete set null,
  created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.csp_subscriptions enable row level security;
drop policy if exists csp_subscriptions_select_own on public.csp_subscriptions;
create policy csp_subscriptions_select_own on public.csp_subscriptions for select to authenticated
using (user_id=(select auth.uid()));

create or replace function public.csp_create_cardpay_order(p_user_id uuid,p_product_code text)
returns jsonb language plpgsql security definer set search_path='public','pg_temp'
as $function$
declare
  v_product public.csp_payment_products%rowtype;
  v_order public.csp_payment_orders%rowtype;
  v_vs bigint;
begin
  if current_user not in ('postgres','service_role') then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if p_user_id is null then raise exception 'USER_ID_REQUIRED'; end if;
  select * into v_product from public.csp_payment_products where code=p_product_code and active=true;
  if not found then raise exception 'PRODUCT_NOT_AVAILABLE'; end if;
  v_vs:=100000000+nextval('public.csp_cardpay_vs_seq');
  insert into public.csp_payment_orders(user_id,product_code,variable_symbol,amount_cents,currency,metadata)
  values(p_user_id,v_product.code,v_vs,v_product.amount_cents,v_product.currency,
    jsonb_build_object('productName',v_product.name,'plan',v_product.plan::text,'billingPeriod',v_product.billing_period))
  returning * into v_order;
  return jsonb_build_object('orderId',v_order.id,'variableSymbol',v_order.variable_symbol::text,
    'amountCents',v_order.amount_cents,'currency',v_order.currency,'productCode',v_order.product_code);
end
$function$;

create or replace function public.csp_finalize_cardpay_order(
  p_variable_symbol bigint,p_amount_cents integer,p_currency text,p_result text,
  p_auth_code text,p_tid text,p_provider_timestamp text,p_ecdsa_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path='public','pg_temp'
as $function$
declare
  v_order public.csp_payment_orders%rowtype;
  v_product public.csp_payment_products%rowtype;
  v_subscription public.csp_subscriptions%rowtype;
  v_start timestamptz;v_end timestamptz;v_current_plan text;v_current_rank int;v_new_rank int;
begin
  if current_user not in ('postgres','service_role') then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  select * into v_order from public.csp_payment_orders where variable_symbol=p_variable_symbol for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.status='paid' then return jsonb_build_object('ok',true,'duplicate',true,'status','paid','orderId',v_order.id); end if;
  if v_order.amount_cents<>p_amount_cents then raise exception 'AMOUNT_MISMATCH'; end if;
  if upper(v_order.currency)<>upper(p_currency) then raise exception 'CURRENCY_MISMATCH'; end if;

  update public.csp_payment_orders set provider_result=p_result,provider_auth_code=nullif(p_auth_code,''),
    provider_tid=nullif(p_tid,''),provider_timestamp=nullif(p_provider_timestamp,''),
    provider_ecdsa_key=nullif(p_ecdsa_key,''),metadata=metadata||coalesce(p_metadata,'{}'::jsonb),
    status=case when upper(p_result)='OK' then 'paid' else 'failed' end,
    paid_at=case when upper(p_result)='OK' then coalesce(paid_at,now()) else paid_at end,updated_at=now()
  where id=v_order.id returning * into v_order;
  if v_order.status<>'paid' then return jsonb_build_object('ok',true,'duplicate',false,'status',v_order.status,'orderId',v_order.id); end if;

  select * into v_product from public.csp_payment_products where code=v_order.product_code;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
  select * into v_subscription from public.csp_subscriptions where user_id=v_order.user_id for update;
  v_start:=greatest(now(),coalesce(v_subscription.current_period_end,now()));
  v_end:=case when v_product.billing_period='annual' then v_start+interval '1 year' else v_start+interval '1 month' end;

  insert into public.csp_subscriptions(user_id,plan,billing_period,status,current_period_start,current_period_end,renewal_mode,last_order_id)
  values(v_order.user_id,v_product.plan,v_product.billing_period,'active',v_start,v_end,'manual_cardpay',v_order.id)
  on conflict(user_id) do update set plan=excluded.plan,billing_period=excluded.billing_period,status='active',
    current_period_start=excluded.current_period_start,current_period_end=excluded.current_period_end,
    renewal_mode='manual_cardpay',last_order_id=excluded.last_order_id,updated_at=now();

  select coalesce(plan::text,'free') into v_current_plan from public.profiles where id=v_order.user_id;
  v_current_rank:=case v_current_plan when 'elite' then 5 when 'ultra' then 4 when 'pro_plus' then 3 when 'pro' then 2 else 1 end;
  v_new_rank:=case v_product.plan::text when 'elite' then 5 when 'ultra' then 4 when 'pro_plus' then 3 when 'pro' then 2 else 1 end;
  if v_new_rank>=coalesce(v_current_rank,1) then
    update public.profiles set plan=v_product.plan,plan_updated_at=now(),plan_source='cardpay',updated_at=now()
    where id=v_order.user_id;
  end if;

  return jsonb_build_object('ok',true,'duplicate',false,'status','paid','orderId',v_order.id,
    'plan',v_product.plan::text,'billingPeriod',v_product.billing_period,'currentPeriodEnd',v_end);
end
$function$;

revoke all on function public.csp_create_cardpay_order(uuid,text) from public,anon,authenticated;
revoke all on function public.csp_finalize_cardpay_order(bigint,integer,text,text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.csp_create_cardpay_order(uuid,text) to service_role;
grant execute on function public.csp_finalize_cardpay_order(bigint,integer,text,text,text,text,text,text,jsonb) to service_role;
