// ============================================================
// send-booking-email — drains public.email_outbox
//
// Deploy: Supabase → Edge Functions → Deploy a new function → Via Editor,
//         name it exactly  send-booking-email  and paste this file.
//         Turn "Verify JWT with legacy secret" OFF — this is called by a
//         schedule, not by a signed-in browser, and is protected by its own
//         shared secret instead.
//
// Secrets required (Edge Functions → Secrets):
//   BOOKING_HOOK_SECRET  a long random string, sent back as x-booking-secret
//   ZEPTOMAIL_TOKEN      the Send Mail token (starts "Zoho-enczapikey ")
//   ZEPTOMAIL_HOST       api.zeptomail.com — or api.zeptomail.in on the India DC
//   MAIL_FROM            no-reply@genaitesting.online  (a verified sender)
//   MAIL_FROM_NAME       GenAITesting
//   SITE_URL             https://genaitesting.online
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected already.
//
// Run it on a schedule (Supabase → Database → Cron, or any external pinger):
//   every 5 minutes, POST with the x-booking-secret header.
//
// Why a queue rather than sending at the moment of booking: a booking must not
// fail because a mail host was briefly down, and the reminder has to be sent a
// day later anyway, so the machinery for "send this at a time" has to exist
// regardless. A queue also means this function can be deployed *after* people
// have started booking and will find everything waiting for it — nothing that
// happened before the token existed is lost.
//
// The calendar attachment is the part that makes this feel like Calendly. An
// .ics with METHOD:REQUEST adds the event to Gmail, Outlook and Apple Calendar;
// a later one with the same UID and a higher SEQUENCE *replaces* it in place,
// and METHOD:CANCEL removes it. That is why reschedule moves the session rather
// than cancelling and re-creating: a new row would mean a new UID, and the
// attendee would be left with the old meeting still sitting in their calendar.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const env = (k: string, d = "") => Deno.env.get(k) ?? d;

const SITE = env("SITE_URL", "https://genaitesting.online").replace(/\/+$/, "");
const ZEPTO_HOST = env("ZEPTOMAIL_HOST", "api.zeptomail.com");
// Defaults to genaitesting.online deliberately. the company's other domain is served
// by Hostinger nameservers, carries two conflicting SPF records, and has no
// DKIM — and it is the company's live Google Workspace domain, so it is not
// ours to change. genaitesting.online is on Netlify DNS with an empty mail
// zone, so SPF and DKIM for it can be added without touching anything that
// already works. A fallback that points at an unverifiable domain would send
// unsigned mail from a brand we were asked not to touch.
const FROM = env("MAIL_FROM", "no-reply@genaitesting.online");
const FROM_NAME = env("MAIL_FROM_NAME", "GenAITesting");
const SECRET = env("BOOKING_HOOK_SECRET");
const BATCH = 25;

const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

/* ---------- dates ---------- */
const PROVIDER: Record<string, string> = {
  google_meet: "Google Meet", zoom: "Zoom", teams: "Microsoft Teams",
  phone: "Phone call", in_person: "In person", other: "Online",
};

// The host's timezone is the one we can state truthfully. The attendee's client
// renders the .ics in their own zone, so the email says IST and the calendar
// entry lands correctly wherever they are — rather than this function guessing
// a timezone it was never told.
const TZ = "Asia/Kolkata";
const TZ_LABEL = "IST";

function human(iso: string) {
  const d = new Date(iso);
  return d.toLocaleString("en-IN", {
    weekday: "long", day: "numeric", month: "long",
    hour: "numeric", minute: "2-digit", timeZone: TZ,
  }) + " " + TZ_LABEL;
}

/* ---------- ICS ---------- */
const icsTime = (iso: string) =>
  new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");

// RFC 5545 wants CRLF, escaped separators, and lines folded at 75 octets. The
// folding matters more than it looks: an unfolded long DESCRIPTION is the usual
// reason an invitation silently fails to import.
const icsEscape = (s: string) =>
  String(s ?? "").replace(/\\/g, "\\\\").replace(/;/g, "\\;")
                 .replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");

function fold(line: string) {
  const bytes = new TextEncoder().encode(line);
  if (bytes.length <= 75) return line;
  const out: string[] = [];
  let cur = "";
  let len = 0;
  for (const ch of line) {
    const n = new TextEncoder().encode(ch).length;
    // 74 leaves room for the leading space continuation lines carry.
    if (len + n > (out.length === 0 ? 75 : 74)) { out.push(cur); cur = ""; len = 0; }
    cur += ch; len += n;
  }
  if (cur) out.push(cur);
  return out[0] + out.slice(1).map((l) => "\r\n " + l).join("");
}

function buildIcs(row: any, cancel: boolean) {
  const p = row.payload ?? {};
  const where = p.meeting_url || p.location_note || PROVIDER[p.provider] || "Online";
  const lines = [
    "BEGIN:VCALENDAR",
    "PRODID:-//GenAITesting//Booking//EN",
    "VERSION:2.0",
    "CALSCALE:GREGORIAN",
    `METHOD:${cancel ? "CANCEL" : "REQUEST"}`,
    "BEGIN:VEVENT",
    `UID:${row.ics_uid}`,
    `SEQUENCE:${row.ics_sequence ?? 0}`,
    `DTSTAMP:${icsTime(new Date().toISOString())}`,
    `DTSTART:${icsTime(p.starts_at)}`,
    `DTEND:${icsTime(p.ends_at)}`,
    `SUMMARY:${icsEscape(p.title || "GenAITesting session")}`,
    `DESCRIPTION:${icsEscape(
      [p.description, p.agenda ? `You asked about: ${p.agenda}` : "",
       p.meeting_url ? `Join: ${p.meeting_url}` : ""]
        .filter(Boolean).join("\n\n"))}`,
    `LOCATION:${icsEscape(where)}`,
    `STATUS:${cancel ? "CANCELLED" : "CONFIRMED"}`,
    p.host_email
      ? `ORGANIZER;CN=${icsEscape(p.host_name || "GenAITesting")}:mailto:${p.host_email}`
      : `ORGANIZER;CN=${icsEscape(FROM_NAME)}:mailto:${FROM}`,
    `ATTENDEE;CN=${icsEscape(row.to_name || "")};RSVP=${cancel ? "FALSE" : "TRUE"}:mailto:${row.to_email}`,
    "END:VEVENT",
    "END:VCALENDAR",
  ];
  return lines.map(fold).join("\r\n") + "\r\n";
}

/* ---------- the emails ---------- */
const SHELL = (title: string, body: string) => `
<div style="margin:0;padding:24px;background:#F3F4F6;font:15px/1.6 Arial,Helvetica,sans-serif;color:#111827">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:14px;padding:28px">
    <div style="font:700 18px/1.2 Arial,sans-serif;color:#1F3864;margin-bottom:18px">${esc(FROM_NAME)}</div>
    <h1 style="font:700 20px/1.3 Arial,sans-serif;color:#111827;margin:0 0 14px">${esc(title)}</h1>
    ${body}
    <p style="margin:24px 0 0;font-size:12.5px;color:#6B7280">
      Manage your sessions at <a href="${SITE}/book.html" style="color:#1F3864">${SITE.replace(/^https?:\/\//, "")}/book.html</a>
    </p>
  </div>
</div>`;

const detailRow = (p: any) => `
  <table role="presentation" style="width:100%;border-collapse:collapse;margin:18px 0">
    <tr><td style="padding:10px 14px;background:#F8FAFC;border-radius:10px">
      <div style="font:700 15px/1.3 Arial,sans-serif;color:#1F3864">${esc(p.title)}</div>
      <div style="margin-top:6px;color:#374151">${esc(human(p.starts_at))}</div>
      <div style="margin-top:2px;color:#6B7280;font-size:13.5px">
        ${esc(p.duration_min)} minutes · ${esc(PROVIDER[p.provider] || "Online")}
        ${p.host_name ? ` · with ${esc(p.host_name)}` : ""}
      </div>
      ${p.meeting_url
        ? `<div style="margin-top:12px"><a href="${esc(p.meeting_url)}"
             style="display:inline-block;padding:9px 16px;background:#1F3864;color:#fff;
                    border-radius:8px;text-decoration:none;font-weight:700">Join the call</a></div>`
        : `<div style="margin-top:10px;color:#6B7280;font-size:13px">
             The joining link will be in your calendar entry closer to the time.</div>`}
    </td></tr>
  </table>`;

function render(row: any): { subject: string; html: string; text: string } {
  const p = row.payload ?? {};
  const name = (p.student_name || row.to_name || "there").split(/\s+/)[0];
  const when = human(p.starts_at);

  switch (row.kind) {
    case "booking_confirmed":
      return {
        subject: `Confirmed: ${p.title} — ${when}`,
        html: SHELL("Your session is booked",
          `<p>Hello ${esc(name)}, that is in the diary.</p>${detailRow(p)}
           ${p.agenda ? `<p style="color:#374151"><strong>You asked about:</strong> ${esc(p.agenda)}</p>` : ""}
           <p style="color:#6B7280;font-size:13.5px">The attached calendar file adds this to
           your calendar. If you need to move or cancel it, do that from your sessions page
           and your calendar will update itself.</p>`),
        text: `Your session is booked.\n\n${p.title}\n${when}\n${p.duration_min} minutes\n`
            + (p.meeting_url ? `Join: ${p.meeting_url}\n` : "")
            + `\nManage it at ${SITE}/book.html\n`,
      };

    case "booking_rescheduled":
      return {
        subject: `Moved: ${p.title} — now ${when}`,
        html: SHELL("Your session has moved",
          `<p>Hello ${esc(name)}, this session has a new time.</p>
           ${p.previous_start
             ? `<p style="color:#6B7280"><s>${esc(human(p.previous_start))}</s></p>` : ""}
           ${detailRow(p)}
           <p style="color:#6B7280;font-size:13.5px">Your calendar entry updates itself —
           there is nothing to delete.</p>`),
        text: `Your session has moved.\n\n${p.title}\nNow: ${when}\n`
            + (p.previous_start ? `Was: ${human(p.previous_start)}\n` : "")
            + `\n${SITE}/book.html\n`,
      };

    case "booking_cancelled":
      return {
        subject: `Cancelled: ${p.title} — ${when}`,
        html: SHELL("That session is cancelled",
          `<p>Hello ${esc(name)}, this one is off the calendar.</p>
           <p style="color:#374151"><strong>${esc(p.title)}</strong><br>${esc(when)}</p>
           ${p.cancel_reason ? `<p style="color:#6B7280">Reason given: ${esc(p.cancel_reason)}</p>` : ""}
           <p>You can book another time whenever suits you.</p>
           <p><a href="${SITE}/book.html" style="display:inline-block;padding:9px 16px;
             background:#1F3864;color:#fff;border-radius:8px;text-decoration:none;
             font-weight:700">Find another time</a></p>`),
        text: `Cancelled: ${p.title}, ${when}.\n`
            + (p.cancel_reason ? `Reason: ${p.cancel_reason}\n` : "")
            + `\nBook another at ${SITE}/book.html\n`,
      };

    case "session_cancelled":
      return {
        subject: `Cancelled by your trainer: ${p.title} — ${when}`,
        html: SHELL("Your trainer has had to cancel",
          `<p>Hello ${esc(name)}, sorry about this — this session is not going ahead.</p>
           <p style="color:#374151"><strong>${esc(p.title)}</strong><br>${esc(when)}</p>
           ${p.cancel_reason ? `<p style="color:#6B7280">${esc(p.cancel_reason)}</p>` : ""}
           <p>Your seat has been released and nothing has been charged. Please pick
           another time that works for you.</p>
           <p><a href="${SITE}/book.html" style="display:inline-block;padding:9px 16px;
             background:#1F3864;color:#fff;border-radius:8px;text-decoration:none;
             font-weight:700">Find another time</a></p>`),
        text: `Your trainer cancelled: ${p.title}, ${when}.\n`
            + (p.cancel_reason ? `${p.cancel_reason}\n` : "")
            + `\nBook another at ${SITE}/book.html\n`,
      };

    case "booking_reminder":
    default:
      return {
        subject: `Tomorrow: ${p.title} — ${when}`,
        html: SHELL("See you tomorrow",
          `<p>Hello ${esc(name)}, a reminder about this one.</p>${detailRow(p)}
           ${p.agenda ? `<p style="color:#374151"><strong>You wanted to cover:</strong>
             ${esc(p.agenda)}</p>` : ""}
           <p style="color:#6B7280;font-size:13.5px">If you cannot make it, cancelling from
           your sessions page frees the slot for someone else.</p>`),
        text: `Reminder: ${p.title}\n${when}\n`
            + (p.meeting_url ? `Join: ${p.meeting_url}\n` : "")
            + `\n${SITE}/book.html\n`,
      };
  }
}

/* ---------- sending ---------- */
async function sendOne(row: any) {
  const { subject, html, text } = render(row);
  const cancel = row.kind === "booking_cancelled" || row.kind === "session_cancelled";
  const ics = buildIcs(row, cancel);

  const res = await fetch(`https://${ZEPTO_HOST}/v1.1/email`, {
    method: "POST",
    headers: {
      "Authorization": env("ZEPTOMAIL_TOKEN"),
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
    body: JSON.stringify({
      from: { address: FROM, name: FROM_NAME },
      to: [{ email_address: { address: row.to_email, name: row.to_name ?? "" } }],
      subject,
      htmlbody: html,
      textbody: text,
      attachments: [{
        name: "invite.ics",
        mime_type: "text/calendar",
        content: btoa(unescape(encodeURIComponent(ics))),
      }],
    }),
  });

  return { ok: res.ok, detail: (await res.text()).slice(0, 400) };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method not allowed" }), { status: 405 });
  }
  // A shared secret rather than a JWT: the caller is a cron job, not a person.
  if (!SECRET || req.headers.get("x-booking-secret") !== SECRET) {
    return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });
  }
  if (!env("ZEPTOMAIL_TOKEN")) {
    // Answered 200 deliberately. "Is there a mail token?" is a question this
    // function answered successfully; the answer is no. A 5xx here would make a
    // scheduler retry forever and would read, in the logs, like an outage.
    return new Response(JSON.stringify({
      sent: 0, skipped: true,
      note: "ZEPTOMAIL_TOKEN is not set — invitations stay queued, nothing is lost",
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // Claimed, not read. Selecting queued rows and marking them sent afterwards
  // is a double-send whenever two runs overlap — a slow batch against a
  // stalling mail host, and the next tick of the schedule arriving while it is
  // still working. Both would read the same rows and both would send them, and
  // the student would get two invitations and two calendar entries.
  //
  // claim_outbox_batch (schema-14) flips the rows to 'sending' under
  // FOR UPDATE SKIP LOCKED, so concurrent callers take disjoint sets. It also
  // counts the attempt, which is why nothing below increments it again.
  const { data: rows, error } = await admin.rpc("claim_outbox_batch", { p_limit: BATCH });

  if (error) {
    // PGRST202 means schema-14-booking-cron.sql has not been run. Say so,
    // rather than returning a bare "function not found" that reads like a bug
    // in this function.
    const missing = error.code === "PGRST202";
    return new Response(JSON.stringify({
      error: missing
        ? "claim_outbox_batch is missing — run schema-14-booking-cron.sql"
        : error.message,
    }), { status: missing ? 503 : 500, headers: { "Content-Type": "application/json" } });
  }

  // The claim already counted this attempt, so `row.attempts` is the count
  // including this one. Adding one again here would retire a message after
  // two and a half real failures rather than five.
  const giveUp = async (row: Record<string, unknown>, detail: string) => {
    const attempts = Number(row.attempts ?? 1);
    await admin.from("email_outbox").update({
      // Five attempts, then stop. A permanently bad address would otherwise be
      // retried for as long as the schedule runs, and the real failures would
      // be lost in the noise.
      status: attempts >= 5 ? "failed" : "queued",
      last_error: detail.slice(0, 400),
      send_after: new Date(Date.now() + attempts * 15 * 60_000).toISOString(),
    }).eq("id", row.id as number);
  };

  let sent = 0, failed = 0;
  for (const row of rows ?? []) {
    try {
      const r = await sendOne(row);
      if (r.ok) {
        sent++;
        await admin.from("email_outbox").update({
          status: "sent", sent_at: new Date().toISOString(), last_error: null,
        }).eq("id", row.id);
      } else {
        failed++;
        await giveUp(row, r.detail ?? "send failed");
      }
    } catch (e) {
      failed++;
      await giveUp(row, String(e));
    }
  }

  return new Response(JSON.stringify({ sent, failed, considered: rows?.length ?? 0 }), {
    status: 200, headers: { "Content-Type": "application/json" },
  });
});
