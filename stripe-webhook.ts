// Closer: turns Pro on and off automatically when Stripe says someone paid or canceled.
// Supabase Edge Function named "stripe-webhook". Turn OFF "Verify JWT" for it (Stripe can't send one).
// Needs one secret: STRIPE_WEBHOOK_SECRET (the whsec_... signing secret from Stripe).

const enc = new TextEncoder();

async function hmacHex(secret: string, message: string) {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Checks the event really came from Stripe (Stripe-Signature header: t=...,v1=...).
async function verify(raw: string, header: string | null, secret: string) {
  if (!header) return false;
  const parts = header.split(",").map((p) => p.trim().split("="));
  const t = parts.find((p) => p[0] === "t")?.[1];
  const sigs = parts.filter((p) => p[0] === "v1").map((p) => p[1]);
  if (!t || !sigs.length) return false;
  if (Math.abs(Date.now() / 1000 - Number(t)) > 300) return false; // older than 5 minutes
  const expected = await hmacHex(secret, `${t}.${raw}`);
  return sigs.some((s) => safeEqual(s, expected));
}

async function rpc(fn: string, args: Record<string, unknown>) {
  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const r = await fetch(`${url}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${fn} failed: ${r.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Use POST", { status: 405 });
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!secret) return new Response("Webhook secret not set", { status: 500 });

  const raw = await req.text();
  if (!(await verify(raw, req.headers.get("stripe-signature"), secret))) {
    return new Response("Bad signature", { status: 400 });
  }

  let event: { type: string; data: { object: Record<string, any> } };
  try { event = JSON.parse(raw); } catch { return new Response("Bad JSON", { status: 400 }); }
  const o = event.data.object;

  try {
    if (event.type === "checkout.session.completed") {
      if (o.mode === "subscription" && (o.payment_status === "paid" || o.payment_status === "no_payment_required")) {
        const result = await rpc("activate_pro", {
          p_user: o.client_reference_id || null,
          p_email: o.customer_details?.email || o.customer_email || null,
          p_customer: typeof o.customer === "string" ? o.customer : null,
          p_subscription: typeof o.subscription === "string" ? o.subscription : null,
        });
        console.log("activate_pro", result);
      }
    } else if (event.type === "customer.subscription.deleted") {
      await rpc("deactivate_pro", { p_subscription: o.id });
    } else if (event.type === "customer.subscription.updated") {
      if (["canceled", "unpaid", "incomplete_expired"].includes(o.status)) {
        await rpc("deactivate_pro", { p_subscription: o.id });
      }
    }
  } catch (e) {
    console.error(e);
    return new Response("Error handling event", { status: 500 }); // Stripe will retry
  }
  return new Response(JSON.stringify({ received: true }), { headers: { "Content-Type": "application/json" } });
});
