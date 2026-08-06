# Razorpay setup — what only you can do

The paywall, pricing page, admin controls and database are all deployed. Payments stay
**switched off** until the three secrets below exist, because I don't handle API secrets.
Until then the pricing page shows plans but checkout will report a configuration error.

Prices currently live: **₹499 / 30 days · ₹1,299 / 90 days · ₹3,999 / 365 days**.
Change them any time in **Admin → Pricing & Payments** — the checkout reads the amount
from the database, never from the page.

---

## Step 1 — Get your Razorpay keys (5 min)

1. Sign up / sign in at <https://dashboard.razorpay.com>.
2. Complete KYC if you haven't — you can use **Test Mode** keys before KYC to try the whole flow safely.
3. Go to **Account & Settings → API Keys → Generate Key**.
4. You get a **Key ID** (`rzp_test_…` or `rzp_live_…`) and a **Key Secret**.
   The secret is shown **once** — copy it now.

> Start in **Test Mode**. Test cards: `4111 1111 1111 1111`, any future expiry, any CVV.
> Nothing is charged. Switch to Live keys only after you've seen the flow work end to end.

## Step 2 — Create a webhook secret (2 min)

1. Razorpay Dashboard → **Account & Settings → Webhooks → Add New Webhook**.
2. **Webhook URL:**
   `https://kfjxoklfodddewqtgiia.supabase.co/functions/v1/razorpay-webhook`
3. **Secret:** invent a long random string and paste it here — you'll reuse it in Step 3.
4. **Active events:** tick `payment.captured` and `payment.failed`.
5. Save.

The webhook is the safety net: if a student pays and their browser closes before the
confirmation call, Razorpay tells the server directly and access is still granted.

## Step 3 — Put the three secrets into Supabase (3 min)

Supabase Dashboard → **Edge Functions → Secrets** (or Project Settings → Edge Functions),
then add:

| Name | Value |
|---|---|
| `RAZORPAY_KEY_ID` | your Key ID (`rzp_test_…` / `rzp_live_…`) |
| `RAZORPAY_KEY_SECRET` | your Key Secret |
| `RAZORPAY_WEBHOOK_SECRET` | the random string from Step 2 |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically — don't add them.

## Step 4 — Deploy the three Edge Functions

The code is in this repo under `edge-functions/`. Deploy each one, either in the
dashboard (**Edge Functions → Deploy a new function**, paste the file contents) or with the CLI:

```bash
supabase functions deploy razorpay-create-order
supabase functions deploy razorpay-verify-payment
supabase functions deploy razorpay-webhook --no-verify-jwt
```

| Function | File | JWT verification |
|---|---|---|
| `razorpay-create-order` | `edge-functions/razorpay-create-order.ts` | **on** (default) |
| `razorpay-verify-payment` | `edge-functions/razorpay-verify-payment.ts` | **on** (default) |
| `razorpay-webhook` | `edge-functions/razorpay-webhook.ts` | **OFF** — Razorpay can't send a Supabase JWT; its own signature is the auth |

Getting that last row wrong is the most common mistake: with JWT verification left on,
Razorpay's webhooks are rejected and paid students don't get access automatically.

## Step 5 — Test before going live

1. Open the site in a browser where you are **not** an admin (admins bypass the paywall),
   or create a second GitHub account. Sign in.
2. You should see Module 1 open and modules 2–16 locked with 🔒, and the three exams locked.
3. Buy the **1 Month** plan with the test card. After payment you should land back on the
   course with everything unlocked and "30d left" in the top bar.
4. Check **Admin → Pricing & Payments**: the payment shows ✅ paid and the student appears
   with days remaining.
5. Confirm in Razorpay Dashboard → Webhooks that the delivery succeeded (HTTP 200).

Only then swap the two keys for **Live** keys and repeat step 3.

---

## How the money path is protected

- The browser never sends an amount. `razorpay-create-order` reads the price from
  `public.plans`, so a tampered request cannot buy a year for ₹1.
- `razorpay-verify-payment` checks `HMAC_SHA256(order_id|payment_id, key_secret)` before
  granting anything, and refuses an order that belongs to another user.
- Only the service role can call `grant_subscription()`. It is revoked from `PUBLIC`,
  `anon` and `authenticated` — a signed-in student calling it directly gets
  *permission denied*. (This was a real hole during the build; it is now closed and tested.)
- `subscriptions`, `payments` and `plans` are read-only to clients. Students cannot insert
  a fake "paid" row or edit a price.
- `grade_quiz()` re-checks access server-side, so bypassing the UI to sit an exam fails.
- Buying again while time remains **adds** days rather than overwriting them.

## If a payment succeeds but access isn't granted

It's recoverable and nothing is lost:

1. **Admin → Pricing & Payments → Recent payment attempts** shows the order with status `paid`.
2. Enter the student's email in **Grant access manually**, pick the plan they paid for, add
   the Razorpay order id as the note, and grant.

Refunds are issued from the Razorpay dashboard; then use **Revoke access** for that student.

## Not included (say the word and I'll add it)

- Auto-renewing subscriptions with e-mandate/UPI autopay (you chose one-time payments).
- GST invoices / receipts by email.
- Coupon or referral codes.
- A "your access expires in 3 days" reminder email.
