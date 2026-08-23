// ============================================================
// send-welcome-email — GenAITesting
//
// Fired by a Supabase Database Webhook on INSERT into public.profiles, so it
// runs whichever way the student enrolled: Google, GitHub or email + password.
//
// Deploy: Supabase → Edge Functions → Deploy a new function → Via Editor,
//         name it exactly  send-welcome-email  and paste this file.
//         Then set its Settings → "Verify JWT with legacy secret" to OFF
//         (the webhook is server-to-server and sends no user JWT — we
//         authenticate it with our own shared secret instead).
//
// Secrets required (Edge Functions → Secrets):
//   ZEPTOMAIL_TOKEN     the Send Mail token from ZeptoMail (starts "Zoho-enczapikey ")
//   ZEPTOMAIL_HOST      api.zeptomail.com   — or api.zeptomail.in on the India DC
//   MAIL_FROM           no-reply@qualitythought.in   (must be a verified sender)
//   MAIL_FROM_NAME      GenAITesting
//   WELCOME_HOOK_SECRET a long random string you also paste into the webhook header
//   SITE_URL            https://genaitesting.online
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by Supabase already.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const env = (k: string, d = "") => Deno.env.get(k) ?? d;

const SITE = env("SITE_URL", "https://genaitesting.online").replace(/\/+$/, "");
const ZEPTO_HOST = env("ZEPTOMAIL_HOST", "api.zeptomail.com");
const FROM = env("MAIL_FROM", "no-reply@qualitythought.in");
const FROM_NAME = env("MAIL_FROM_NAME", "GenAITesting");

const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

const rupees = (paise: number) => "₹" + (paise / 100).toLocaleString("en-IN");

/* ---------- the email ---------- */
function renderEmail(name: string, plans: any[], unsubUrl: string) {
  const firstName = name.trim().split(/\s+/)[0] || "there";

  const planRows = plans.map((p) => `
    <tr>
      <td style="padding:14px 16px;border:1px solid #E5E7EB;border-radius:10px;background:#FFFFFF">
        <div style="font:600 15px/1.3 Arial,Helvetica,sans-serif;color:#1F3864">
          ${esc(p.name)}${p.badge ? ` &nbsp;<span style="font:700 10px/1 Arial,sans-serif;letter-spacing:.08em;
            text-transform:uppercase;color:#FFFFFF;background:#EE4C12;padding:3px 8px;border-radius:99px">${esc(p.badge)}</span>` : ""}
        </div>
        <div style="font:800 24px/1.2 Arial,Helvetica,sans-serif;color:#1F3864;margin:6px 0 2px">
          ${rupees(p.amount_paise)}
          <span style="font:400 13px/1 Arial,sans-serif;color:#6B7280">for ${p.duration_days} days</span>
        </div>
        ${p.description ? `<div style="font:400 13px/1.5 Arial,Helvetica,sans-serif;color:#4B5563">${esc(p.description)}</div>` : ""}
      </td>
    </tr>
    <tr><td style="height:10px;line-height:10px">&nbsp;</td></tr>`).join("");

  const html = `<!doctype html>
<html><body style="margin:0;padding:0;background:#F7F5F0">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F7F5F0;padding:28px 12px">
<tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px">

  <tr><td style="background:#1F3864;border-radius:14px 14px 0 0;padding:26px 28px" align="left">
    <img src="${SITE}/icon-192.png" width="44" height="44" alt=""
         style="border-radius:11px;display:block;border:0">
    <div style="font:700 11px/1 Arial,Helvetica,sans-serif;letter-spacing:.24em;text-transform:uppercase;color:#F79420;margin-top:14px">GenAITesting</div>
    <div style="font:700 20px/1.3 Arial,Helvetica,sans-serif;color:#FFFFFF;margin-top:5px">GenAI Application Testing</div>
  </td></tr>

  <tr><td style="background:#FFFFFF;padding:28px">
    <div style="font:700 21px/1.3 Arial,Helvetica,sans-serif;color:#1F3864">Welcome, ${esc(firstName)}.</div>
    <p style="font:400 15px/1.65 Arial,Helvetica,sans-serif;color:#111827;margin:14px 0 0">
      Your account is ready. <strong>Module 1 — Introduction to Gen AI</strong> is open to you right
      now, free, with no card and nothing else to set up.
    </p>
    <p style="font:400 15px/1.65 Arial,Helvetica,sans-serif;color:#111827;margin:14px 0 0">
      The full programme runs to 16 modules and roughly 93 hours: LLM evaluation, red-team testing,
      prompt engineering, RAG, agents and MCP, and automation with Promptfoo, DeepEval and RAGAS.
      There are three certification levels, and each one you pass earns a separate certificate with a
      number anyone can verify.
    </p>

    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0 4px">
      <tr><td style="background:#EE4C12;border-radius:10px">
        <a href="${SITE}/app.html" style="display:inline-block;padding:13px 26px;font:600 15px/1 Arial,Helvetica,sans-serif;color:#FFFFFF;text-decoration:none">Start Module 1 →</a>
      </td></tr>
    </table>
  </td></tr>

  <tr><td style="background:#FFFFFF;padding:4px 28px 8px">
    <div style="font:700 11px/1 Arial,Helvetica,sans-serif;letter-spacing:.18em;text-transform:uppercase;color:#EE4C12;margin-bottom:14px">When you're ready for the rest</div>
    <p style="font:400 14px/1.6 Arial,Helvetica,sans-serif;color:#4B5563;margin:0 0 16px">
      One payment unlocks modules 2–16 and all three exams for the period you choose. Nothing renews
      automatically, and buying again while you still have time left adds to your days rather than replacing them.
    </p>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">${planRows}</table>
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 22px">
      <tr><td style="border:1.5px solid #1F3864;border-radius:10px">
        <a href="${SITE}/pricing.html" style="display:inline-block;padding:11px 22px;font:600 14px/1 Arial,Helvetica,sans-serif;color:#1F3864;text-decoration:none">See all plans</a>
      </td></tr>
    </table>
  </td></tr>

  <tr><td style="background:#FFFFFF;border-radius:0 0 14px 14px;border-top:1px solid #E5E7EB;padding:20px 28px">
    <p style="font:400 12px/1.6 Arial,Helvetica,sans-serif;color:#6B7280;margin:0">
      You're getting this because you created an account at
      <a href="${SITE}" style="color:#1F3864">genaitesting.online</a>.
      Questions? Just reply to this email.
    </p>
    <p style="font:400 12px/1.6 Arial,Helvetica,sans-serif;color:#6B7280;margin:10px 0 0">
      GenAITesting · genaitesting.online ·
      <a href="${unsubUrl}" style="color:#6B7280">Don't send me course offers</a>
    </p>
  </td></tr>

</table>
</td></tr></table>
</body></html>`;

  const text = [
    `Welcome, ${firstName}.`,
    ``,
    `Your account is ready. Module 1 - Introduction to Gen AI is open to you right now, free.`,
    `Start here: ${SITE}/app.html`,
    ``,
    `The full programme is 16 modules and about 93 hours, covering LLM evaluation, red-team`,
    `testing, prompt engineering, RAG, agents and MCP, and automation with Promptfoo,`,
    `DeepEval and RAGAS. Three certification levels, each with its own verifiable certificate.`,
    ``,
    `When you're ready for the rest:`,
    ...plans.map((p) => `  - ${p.name}: ${rupees(p.amount_paise)} for ${p.duration_days} days`),
    `  All plans: ${SITE}/pricing.html`,
    ``,
    `One payment, nothing renews automatically. Buying again adds to your remaining days.`,
    ``,
    `You're getting this because you created an account at genaitesting.online.`,
    `Prefer not to hear about course offers? ${unsubUrl}`,
    `GenAITesting - genaitesting.online`,
  ].join("\n");

  return { html, text };
}

/* ---------- handler ---------- */
Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  // The webhook is the only caller. Supabase lets us attach a custom header;
  // without a matching secret we refuse, so nobody can trigger sends by URL alone.
  const expected = env("WELCOME_HOOK_SECRET");
  if (!expected || req.headers.get("x-welcome-secret") !== expected) {
    return new Response("unauthorized", { status: 401 });
  }

  let userId: string | null = null;
  try {
    const body = await req.json();
    // Database Webhook payload: { type, table, record, old_record, schema }
    userId = body?.record?.id ?? body?.user_id ?? null;
  } catch {
    return new Response("bad request", { status: 400 });
  }
  if (!userId) return new Response("no user id", { status: 400 });

  // Is this student actually owed a welcome? The rule lives in the database.
  const { data: pending, error: pErr } = await admin.rpc("pending_welcome", { p_user_id: userId });
  if (pErr) return new Response(`lookup failed: ${pErr.message}`, { status: 500 });

  const row = Array.isArray(pending) ? pending[0] : pending;
  if (!row) return new Response(JSON.stringify({ skipped: "not eligible" }), { status: 200 });

  // Live prices, so the email can never quote a stale figure.
  const { data: plans } = await admin
    .from("plans").select("*").eq("active", true).order("sort_order");

  const { data: prof } = await admin
    .from("profiles").select("unsubscribe_token").eq("id", userId).single();
  const unsubUrl = `${SITE}/unsubscribe.html?t=${prof?.unsubscribe_token ?? ""}`;

  const { html, text } = renderEmail(row.full_name ?? "", plans ?? [], unsubUrl);

  try {
    const res = await fetch(`https://${ZEPTO_HOST}/v1.1/email`, {
      method: "POST",
      headers: {
        "Authorization": env("ZEPTOMAIL_TOKEN"),
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify({
        from: { address: FROM, name: FROM_NAME },
        to: [{ email_address: { address: row.email, name: row.full_name ?? "" } }],
        subject: "Welcome to GenAITesting — Module 1 is open",
        htmlbody: html,
        textbody: text,
      }),
    });

    const detail = (await res.text()).slice(0, 400);
    if (!res.ok) {
      await admin.rpc("mark_welcome_sent", { p_user_id: userId, p_status: "failed", p_detail: detail });
      return new Response(JSON.stringify({ sent: false, detail }), { status: 502 });
    }

    await admin.rpc("mark_welcome_sent", { p_user_id: userId, p_status: "sent", p_detail: null });
    return new Response(JSON.stringify({ sent: true }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    await admin.rpc("mark_welcome_sent", {
      p_user_id: userId, p_status: "failed", p_detail: String(e).slice(0, 400),
    });
    return new Response(JSON.stringify({ sent: false, error: String(e) }), { status: 500 });
  }
});
