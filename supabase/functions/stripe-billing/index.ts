
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") || "";

const CATALOG: Record<string,{priceId:string,plan:string,billing:string}> = {
  pro_monthly: {priceId:"price_1UUjj4ASo7INQStSaZMLeGLS",plan:"pro",billing:"monthly"},
  pro_annual: {priceId:"price_1UUjtPASo7INQStSuSOXb1ON",plan:"pro",billing:"annual"},
  pro_plus_monthly: {priceId:"price_1UUjj6ASo7INQStSqs29OBxm",plan:"pro_plus",billing:"monthly"},
  pro_plus_annual: {priceId:"price_1UUjtRASo7INQStSuocD1Gjs",plan:"pro_plus",billing:"annual"},
  ultra_monthly: {priceId:"price_1UUjl2ASo7INQStSmZAeyYd5",plan:"ultra",billing:"monthly"},
  ultra_annual: {priceId:"price_1UUjtUASo7INQStSPPhhQHC6",plan:"ultra",billing:"annual"},
};

const cors = {
  "access-control-allow-origin": "https://connectsportspro.com",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json",
};

function json(body: unknown, status=200) {
  return new Response(JSON.stringify(body), { status, headers: cors });
}

async function stripePost(path:string, params:URLSearchParams) {
  const res = await fetch("https://api.stripe.com/v1/" + path, {
    method:"POST",
    headers:{
      "authorization":"Bearer " + STRIPE_SECRET_KEY,
      "content-type":"application/x-www-form-urlencoded",
    },
    body:params.toString(),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data?.error?.message || "Stripe request failed");
  return data;
}

async function stripeGet(path:string) {
  const res = await fetch("https://api.stripe.com/v1/" + path, {
    headers:{"authorization":"Bearer " + STRIPE_SECRET_KEY}
  });
  const data = await res.json();
  if (!res.ok) {
    const err = new Error(data?.error?.message || "Stripe request failed");
    (err as any).status = res.status;
    throw err;
  }
  return data;
}


Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
  if (req.method !== "POST") return json({error:"METHOD_NOT_ALLOWED"},405);
  if (!STRIPE_SECRET_KEY) return json({configured:false,error:"STRIPE_NOT_CONFIGURED"},503);

  const authHeader = req.headers.get("authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i,"");
  if (!token) return json({error:"UNAUTHORIZED"},401);

  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global:{headers:{Authorization:"Bearer "+token}}
  });
  const { data:{user}, error:userError } = await authClient.auth.getUser(token);
  if (userError || !user) return json({error:"UNAUTHORIZED"},401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const {data:profile} = await admin.from("profiles").select("is_admin,email").eq("id",user.id).maybeSingle();

  const body = await req.json().catch(()=>({}));
  const action = body?.action || "status";

  if (action === "status") return json({configured:true,liveMode:STRIPE_SECRET_KEY.startsWith("sk_live_")});

  const { data:sub } = await admin
    .from("stripe_subscriptions")
    .select("*")
    .eq("user_id",user.id)
    .maybeSingle();

  if (action === "subscription_status") {
    return json({
      subscription: sub ? {
        plan: sub.plan || "free",
        billingInterval: sub.billing_interval || null,
        status: sub.status || null,
        currentPeriodEnd: sub.current_period_end || null,
        cancelAtPeriodEnd: !!sub.cancel_at_period_end
      } : null
    });
  }

  if (action === "cancel" || action === "resume") {
    if (!sub?.stripe_subscription_id) return json({error:"NO_ACTIVE_SUBSCRIPTION"},400);
    const p = new URLSearchParams();
    p.set("cancel_at_period_end", action === "cancel" ? "true" : "false");
    const updated = await stripePost("subscriptions/" + encodeURIComponent(sub.stripe_subscription_id), p);
    await admin.from("stripe_subscriptions").update({
      status: updated?.status || sub.status,
      current_period_end: updated?.current_period_end ? new Date(updated.current_period_end*1000).toISOString() : sub.current_period_end,
      cancel_at_period_end: !!updated?.cancel_at_period_end,
      updated_at: new Date().toISOString()
    }).eq("user_id",user.id);
    return json({
      ok:true,
      subscription:{
        plan: sub.plan || "free",
        billingInterval: sub.billing_interval || null,
        status: updated?.status || sub.status || null,
        currentPeriodEnd: updated?.current_period_end ? new Date(updated.current_period_end*1000).toISOString() : sub.current_period_end || null,
        cancelAtPeriodEnd: !!updated?.cancel_at_period_end
      }
    });
  }

  if (action === "portal") {
    if (!sub?.stripe_customer_id) return json({error:"NO_STRIPE_CUSTOMER"},400);
    const p = new URLSearchParams();
    p.set("customer", sub.stripe_customer_id);
    p.set("return_url","https://connectsportspro.com/predplatne/");
    const session = await stripePost("billing_portal/sessions",p);
    return json({url:session.url});
  }

  if (action !== "checkout") return json({error:"UNKNOWN_ACTION"},400);

  const productCode = String(body?.productCode || "");
  const def = CATALOG[productCode];
  if (!def) return json({error:"INVALID_PRODUCT"},400);
  const priceId = def.priceId;
  const plan = def.plan;
  const billing = def.billing;

  const p = new URLSearchParams();
  p.set("mode","subscription");
  p.set("success_url","https://connectsportspro.com/cennik/?stripe=success&session_id={CHECKOUT_SESSION_ID}");
  p.set("cancel_url","https://connectsportspro.com/cennik/?stripe=cancelled");
  p.set("line_items[0][price]",priceId);
  p.set("line_items[0][quantity]","1");
  p.set("client_reference_id",user.id);
  p.set("metadata[csp_user_id]",user.id);
  p.set("metadata[csp_plan]",plan);
  p.set("metadata[csp_billing]",billing);
  p.set("subscription_data[metadata][csp_user_id]",user.id);
  p.set("subscription_data[metadata][csp_plan]",plan);
  p.set("subscription_data[metadata][csp_billing]",billing);

  if (sub?.stripe_customer_id) p.set("customer",sub.stripe_customer_id);
  else if (user.email) p.set("customer_email",user.email);

  const session = await stripePost("checkout/sessions",p);
  return json({url:session.url});
  } catch (e) {
    console.error(e);
    return json({error:String((e as Error)?.message || e || "STRIPE_ERROR")},500);
  }
});
