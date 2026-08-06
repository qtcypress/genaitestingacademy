# QT GenAI Testing Academy — Setup & Deployment Guide

A lightweight training portal for Quality Thought's GenAI Application Testing program.
Static HTML/JS frontend (no build step) + Supabase (free tier) for GitHub login, database, and file storage.
Installable as a mobile app (PWA) — no Play Store needed.

**Total setup time: ~20 minutes. Everything below is free.**

---

## What's in this folder

| File | Purpose |
|---|---|
| `index.html` | Landing page + "Sign in with GitHub" |
| `app.html` | Student dashboard — materials by module, progress bar, assessments |
| `viewer.html` | Opens any material: HTML lessons, images/GIFs, PDFs, PPT/Word (online preview), Excel → interactive tables |
| `quiz.html` | Timed assessment page (graded server-side — answers never reach the browser) |
| `certificate.html` | Student's printable certificate (Print → Save as PDF) |
| `verify.html` | **Public** — anyone can verify a certificate by number or email, no login |
| `admin.html` | Admin panel — upload files, build quizzes, track every student, export CSV |
| `config.js` | ← the ONLY file you must edit |
| `supabase/schema.sql` | One-shot database setup script |
| `manifest.webmanifest`, `sw.js`, `assets/` | PWA install + styles + icons |
| `seed-materials/` | Your sample files, ready to upload through the admin panel |

---

## Step 1 — Create the Supabase project (5 min)

1. Go to <https://supabase.com> → sign in (GitHub works) → **New project**.
   Pick any name (e.g. `qt-academy`), a strong DB password, region **Mumbai (ap-south-1)**.
2. When it finishes provisioning, open **SQL Editor → New query**.
3. Copy the ENTIRE contents of `supabase/schema.sql`, paste, **Run**.
   You should see "Success. No rows returned". This creates all tables, security rules,
   the grading function, certificate verification, and the private `materials` storage bucket.
4. **Check one thing**: if the run output shows a *NOTICE about storage policies*, your project
   requires storage policies to be created in the dashboard instead. Go to
   **Storage → Policies → materials bucket → New policy** and add these 4 policies on `objects`:
   - *SELECT* → policy expression: `bucket_id = 'materials' AND auth.role() = 'authenticated'`
   - *INSERT* → `bucket_id = 'materials' AND public.is_admin()`
   - *UPDATE* → `bucket_id = 'materials' AND public.is_admin()`
   - *DELETE* → `bucket_id = 'materials' AND public.is_admin()`
   (If there was no notice, the script already created them — skip this.)

## Step 2 — GitHub login (5 min)

1. On GitHub: **Settings → Developer settings → OAuth Apps → New OAuth App**
   - Application name: `QT GenAI Testing Academy`
   - Homepage URL: your site URL (you can start with `http://localhost` and change later)
   - **Authorization callback URL**: `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback`
     (find YOUR-PROJECT-REF in Supabase → Project Settings → API → Project URL)
2. Copy the **Client ID**, generate a **Client Secret**.
3. In Supabase: **Authentication → Sign In / Up → Providers→ GitHub** → enable, paste Client ID + Secret, **Save**.
4. In Supabase: **Authentication → URL Configuration**
   - **Site URL**: your final site address (e.g. `https://qt-academy.netlify.app`)
   - **Redirect URLs**: add the same address with `/**` (e.g. `https://qt-academy.netlify.app/**`).
     While testing locally also add `http://localhost:8000/**`.

## Step 3 — Point the frontend at your project (1 min)

Edit `config.js`:

```js
SUPABASE_URL:      "https://YOUR-PROJECT-REF.supabase.co",
SUPABASE_ANON_KEY: "eyJ...your anon public key...",
```

Both values are in **Supabase → Project Settings → API**.
(The anon key is designed to be public — all real security is enforced by Row Level Security in the database.)

## Step 4 — Deploy the site (5 min)

Any static host works. Easiest two:

**Netlify (recommended)**
1. <https://app.netlify.com/drop> — drag this whole folder onto the page. Done.
2. Note your URL (e.g. `https://qt-academy.netlify.app`), then go back and update
   the GitHub OAuth app Homepage URL and Supabase Site URL / Redirect URLs to match.

**GitHub Pages**
1. Push this folder to a repo → Settings → Pages → Deploy from branch → `main` / root.
2. Your URL is `https://USERNAME.github.io/REPO/` — update OAuth + Supabase URLs to match.

**Local testing:** `python3 -m http.server 8000` in this folder → <http://localhost:8000>
(don't open files with `file://` — OAuth needs a real origin).

## Step 5 — Make yourself admin (1 min)

1. Open your deployed site → **Sign in with GitHub** (this creates your profile row).
2. Supabase → **SQL Editor**:
   ```sql
   update public.profiles set role='admin' where email='ramprasad@qualitythought.in';
   ```
   (use whatever email your GitHub account exposes — check `select * from public.profiles;`)
3. Refresh the site — an **Admin** link appears in the top bar.

## Step 6 — Load your content (5 min)

1. **Admin → Materials**: upload each file from `seed-materials/` —
   suggested modules: *GenAI Basics* (what_is_ai.html, both infographic PNGs,
   LLMs_FineTuning_RAG_Agents_AgenticAI.html, aitestinglab.html),
   *Manual Testing* (Manual_Test_Cases.docx, Drugs_com_AI_Search_RedTeam_TestCases.docx),
   *RAGAS / Evaluation* (QualityThought_RAGAS_Metrics_Demo.pptx).
2. **Admin → Assessments**: create the **🎓 FINAL (grants certificate)** exam, add questions
   (one per line options, mark the correct number), then **▶ Publish**.
   Practice quizzes work the same but don't grant certificates.

That's it. Students sign in with GitHub, learn, take the final, and get a certificate
numbered like `QT-2026-A1B2C3D4`, verifiable by anyone at `verify.html`.

---

## How the pieces work

- **Security**: files live in a *private* bucket — only logged-in students get short-lived
  signed URLs. Quiz answers are stored in a column the browser can never read; grading
  happens inside Postgres (`grade_quiz`). Certificates are issued by the same function,
  so students can't forge them. Public verification exposes only the cert number, name,
  masked email, course, score, and date.
- **Excel → tables**: spreadsheets are parsed in the student's browser (SheetJS) and shown
  as clean tables with one tab per sheet.
- **PPT / Word preview**: shown via Microsoft's Office online viewer (uses a temporary
  signed URL); students can always download the original.
- **PWA**: on Android Chrome students get an "Install app" banner (or ⋮ → *Add to Home screen*);
  on iPhone Safari it's *Share → Add to Home Screen*. The app shell loads offline;
  materials need a connection.
- **Scale**: Supabase free tier handles thousands of users; if you cross
  ~50k monthly active users or 1 GB file storage, the Pro plan ($25/mo) removes those limits.
  Netlify free serves 100 GB bandwidth/month.

## FAQs

- **Add another admin** → same as Step 5 with their email.
- **Student's GitHub email is private/missing** → they should enable a public email on GitHub, or you can find them by GitHub username in the Students tab.
- **Change the course name on certificates** → edit `COURSE_NAME` in `config.js` *and* the `course` default in `supabase/schema.sql` (certificates table) before students take the final.
- **Re-issue / revoke a certificate** → Supabase → Table Editor → `certificates` (delete the row to revoke).
- **Larger uploads failing** → Supabase free tier caps files at 50 MB each (raise in Storage settings on Pro).
