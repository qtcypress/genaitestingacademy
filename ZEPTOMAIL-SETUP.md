# ZeptoMail setup

Email is the last thing standing between a booking and a student actually
knowing about it. Nothing here is urgent in the sense that anything breaks
without it — bookings are taken and held, invitations queue in
`public.email_outbox`, and the send function drains whatever it finds the moment
a token exists. But until this is done, a student who books a call gets no
confirmation, no reminder and no calendar entry.

## Send from `genaitesting.online`, not the company's other domain

This is a decision, not a default, and the reasoning is worth keeping because
the obvious choice is the wrong one.

The company's other domain is its live mail domain — the MX records point at
Google Workspace, so real business email flows through it. Three things make it
a bad place to bolt on a transactional sender:

1. **It is not administered where you'd expect.** The domain was bought from
   GoDaddy, but its nameservers are `ns1.dns-parking.com` and
   `ns2.dns-parking.com` — Hostinger's. Records added in GoDaddy's DNS panel go
   into a zone no resolver ever queries. (The zone also carries a
   `Hostinger-domain-verification-1` TXT record, which is the giveaway.)
2. **It already has two conflicting SPF records**, which is a fault on its own:

   ```
   v=spf1 include:_spf.google.com ~all
   v=spf1 include:spf.ipzmarketing.com include:_spf.mail.hostinger.com ~all
   ```

   RFC 7208 allows exactly one. Receivers treat two as a permanent error, so SPF
   currently fails for everything that domain sends, Google Workspace included.
   It also has no DKIM at all and no DMARC.
3. **Fixing that is someone else's call.** Merging SPF records on a domain
   carrying live business mail is a change with real blast radius, and it is not
   ours to make.

`genaitesting.online` has none of these problems. It is on Netlify DNS
(`dns1–4.p02.nsone.net`), its zone has no MX and no TXT records at all, so
nothing we add can collide with anything that already works — and the From
address then matches the brand students actually recognise, which helps both
deliverability and the person reading it.

Both edge functions now default `MAIL_FROM` to
`no-reply@genaitesting.online`, so even a missing secret cannot fall back to a
domain we were asked not to touch.

## 1. In ZeptoMail

Sign up, then add `genaitesting.online` as a sending domain and create a Mail
Agent for it. ZeptoMail generates a DKIM key **per domain** — nobody can tell
you the value in advance, it only exists once the domain is added. It will show
you three things:

- a DKIM record: a selector (something like `zmail._domainkey`) and a long
  `v=DKIM1; k=rsa; p=…` value
- an SPF include to add
- sometimes a verification TXT record

Then take the **Send Mail token** from the Mail Agent. It begins
`Zoho-enczapikey ` — that prefix is part of the value and must be kept.

Note which data centre you signed up in. India is `api.zeptomail.in`; everywhere
else is `api.zeptomail.com`. The wrong one fails authentication in a way that
looks like a bad token.

## 2. In Netlify DNS

Netlify → Domains → `genaitesting.online` → DNS records. Add exactly what
ZeptoMail showed.

Two things that waste the most time here:

- **The name field is relative.** Enter `zmail._domainkey`, not
  `zmail._domainkey.genaitesting.online`. Appending the domain yourself produces
  `zmail._domainkey.genaitesting.online.genaitesting.online`, which looks right
  in the panel and resolves nowhere.
- **The DKIM value is one string**, however long. Do not add line breaks or
  split it across records.

Since the zone has no SPF today, the SPF record is a fresh one at the root (`@`)
rather than an edit:

```
v=spf1 include:<whatever ZeptoMail gives you> ~all
```

Propagation is usually minutes on this zone. Then press Verify in ZeptoMail.

## 3. In Supabase → Edge Functions → Secrets

Not Netlify, and not in this repository — a token in a public repo is a token
that has been given away.

| Secret | Value |
|---|---|
| `ZEPTOMAIL_TOKEN` | the Send Mail token, including the `Zoho-enczapikey ` prefix |
| `ZEPTOMAIL_HOST` | `api.zeptomail.in` or `api.zeptomail.com` — match your DC |
| `MAIL_FROM` | `no-reply@genaitesting.online` (must be the verified domain) |
| `MAIL_FROM_NAME` | `GenAITesting` |
| `SITE_URL` | `https://genaitesting.online` |
| `BOOKING_HOOK_SECRET` | a long random string, for the booking sender |
| `WELCOME_HOOK_SECRET` | the existing one, for the welcome email |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically — do
not add them.

Both functions read the same ZeptoMail three, so setting them once switches on
the welcome email and all five booking emails together.

## 4. Deploy and schedule the sender

Supabase → Edge Functions → Deploy a new function → Via Editor, named exactly
`send-booking-email`, pasting `edge-functions/send-booking-email/index.ts`.

**Turn "Verify JWT with legacy secret" OFF.** It is called by a schedule, not by
a signed-in browser; `BOOKING_HOOK_SECRET` in the `x-booking-secret` header is
what protects it.

Then schedule a POST to it every five minutes — Supabase → Database → Cron, or
any external pinger — with that header set.

## Checking it worked

Book a session as a student and watch `public.email_outbox`. A row appears with
`status = 'queued'` immediately; within five minutes it should read `'sent'`. If
it reads `'failed'`, `last_error` holds ZeptoMail's own response, which is
usually specific enough to act on.

Before the token exists the function answers **200 with `skipped: true`**, not an
error. That is deliberate: "is there a mail token?" is a question it answered
successfully, and a 5xx would make the scheduler retry forever and read in the
logs like an outage.

After five failed attempts a row is marked `failed` and left alone, so one
permanently bad address cannot bury the real failures.
