/* ============ GenAITesting — shared app helpers ============
   Loaded on every page AFTER config.js and the Supabase CDN script.  */

(function () {
  const C = window.QT_CONFIG;
  if (!C || C.SUPABASE_URL.includes("YOUR-PROJECT-REF")) {
    document.addEventListener("DOMContentLoaded", () =>
      showToast("⚠️ config.js is not set up yet — add your Supabase URL & anon key.", true, 8000));
  }
  window.sb = window.supabase.createClient(C.SUPABASE_URL, C.SUPABASE_ANON_KEY);
})();

/* ---------- toast ---------- */
function showToast(msg, isError = false, ms = 3200) {
  let t = document.getElementById("toast");
  if (!t) { t = document.createElement("div"); t.id = "toast"; document.body.appendChild(t); }
  t.textContent = msg;
  t.className = "show" + (isError ? " err" : "");
  clearTimeout(t._h);
  t._h = setTimeout(() => (t.className = ""), ms);
}

/* ---------- auth helpers ---------- */
async function getSession() {
  const { data } = await sb.auth.getSession();
  return data.session;
}

async function requireLogin() {
  const session = await getSession();
  if (!session) { location.href = "index.html"; throw new Error("not logged in"); }
  return session;
}

/* ---------- calling an Edge Function without dead-ending ----------
   A Supabase access token lives about an hour, and the SDK only keeps it fresh
   while the tab is awake and visible. A page left open over lunch, or a tab the
   browser suspended and restored, therefore calls an Edge Function with a token
   the gateway has already stopped accepting. Supabase answers 401
   (UNAUTHORIZED_ASYMMETRIC_JWT) before the function body ever runs, and
   functions.invoke reports that to us as the single string

       "Edge Function returned a non-2xx status code"

   which is what a student was being shown. It says nothing about what went wrong
   or what to do, and it is the same sentence whether their sign-in aged out or the
   database is on fire.

   So this does two things the raw call does not. It reads what the server actually
   said, off the Response that FunctionsHttpError carries on `.context`. And when
   the only problem is a stale token, it refreshes and tries once more, so the
   common case heals itself and nobody is shown an error at all.

   One retry, not a loop: if the refresh token is dead too, the answer is to sign
   in again, and retrying cannot discover that any faster. */
async function invokeFn(name, opts = {}) {
  const attempt = async () => {
    const { data, error } = await sb.functions.invoke(name, opts);
    if (!error) return { data, error: null };
    let status = null, body = "";
    const res = error.context;
    if (res && typeof res.status === "number") {
      status = res.status;
      // The SDK has not read the body for a non-2xx, but clone defensively in case
      // a future version does — a consumed body must not turn into a thrown error
      // on the path whose whole job is reporting errors clearly.
      try { body = await (res.clone ? res.clone() : res).text(); } catch (e) { body = ""; }
    }
    return { data: null, error: Object.assign(error, { status, body }) };
  };

  let r = await attempt();

  if (r.error && r.error.status === 401) {
    let refreshed = null;
    try { refreshed = (await sb.auth.refreshSession()).data.session; } catch (e) { refreshed = null; }
    if (refreshed) r = await attempt();
  }

  if (r.error) {
    r.error.needsSignIn = r.error.status === 401;
    r.error.friendly = friendlyFnError(r.error);
  }
  return r;
}

/* The server's own message if it sent one, because "no active access" is worth
   reading and "non-2xx status code" is not. */
function friendlyFnError(e) {
  if (e.needsSignIn) return "Your sign-in has expired.";
  let msg = "";
  // `reason` as well as `error`: a function that answers "no, and here is why"
  // puts the why in `reason`, and dropping it is how a student ends up reading
  // "the server returned HTTP 403" instead of "no project has been assigned to
  // your account". Whatever the function chose to say, say that.
  try { const b = JSON.parse(e.body || "{}"); msg = b.error || b.reason || ""; }
  catch (x) { msg = ""; }
  if (msg) return msg;
  if (e.status >= 500) return "The server had a problem (HTTP " + e.status + ").";
  if (e.status) return "The server returned HTTP " + e.status + ".";
  return e.message || "Something went wrong.";
}

async function getProfile() {
  const session = await requireLogin();
  const { data, error } = await sb.from("profiles").select("*").eq("id", session.user.id).single();
  if (error) { console.error(error); return null; }
  return data;
}

async function requireAdmin() {
  const p = await getProfile();
  if (!p || p.role !== "admin") {
    document.body.innerHTML =
      '<div class="wrap" style="padding:60px 16px;text-align:center">' +
      "<h1>Admins only</h1><p class='muted'>Your account doesn't have admin access.</p>" +
      '<a class="btn btn-navy" href="app.html">Back to dashboard</a></div>';
    throw new Error("not admin");
  }
  return p;
}

/* absolute URL of a page in this site, whatever folder we're served from */
function pageUrl(page) {
  return location.origin + location.pathname.replace(/[^/]*$/, "") + page;
}

/* ---------- social sign-in ---------- */
function loginWithGitHub(redirectPage = "app.html") {
  sb.auth.signInWithOAuth({ provider: "github", options: { redirectTo: pageUrl(redirectPage) } });
}

function loginWithGoogle(redirectPage = "app.html") {
  sb.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: pageUrl(redirectPage), queryParams: { prompt: "select_account" } }
  });
}

/* ---------- email + password ----------
   Signing up returns one of three outcomes:
     "confirm"   – account created, confirmation email sent (the normal path)
     "exists"    – that email already has an account
     "signed-in" – only happens if email confirmation is switched OFF in Supabase
   Supabase deliberately does NOT error on a duplicate email (that would let anyone
   test which addresses are registered). It returns a decoy user with an empty
   identities array instead, which is what we check for.                       */
async function signUpWithEmail(fullName, email, password, redirectPage = "app.html") {
  const { data, error } = await sb.auth.signUp({
    email: email.trim(),
    password,
    options: { data: { full_name: fullName.trim() }, emailRedirectTo: pageUrl(redirectPage) }
  });
  if (error) throw error;
  if (data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0)
    return "exists";
  return data.session ? "signed-in" : "confirm";
}

async function signInWithEmail(email, password) {
  const { data, error } = await sb.auth.signInWithPassword({ email: email.trim(), password });
  if (error) throw error;
  return data;
}

async function sendPasswordReset(email) {
  const { error } = await sb.auth.resetPasswordForEmail(email.trim(), {
    redirectTo: pageUrl("reset-password.html")
  });
  if (error) throw error;
}

async function resendConfirmation(email, redirectPage = "app.html") {
  const { error } = await sb.auth.resend({
    type: "signup",
    email: email.trim(),
    options: { emailRedirectTo: pageUrl(redirectPage) }
  });
  if (error) throw error;
}

/* Turn Supabase's terse auth errors into something a student can act on. */
function authErrorMessage(e) {
  const m = String((e && e.message) || e || "").toLowerCase();
  if (m.includes("invalid login credentials"))
    return "That email and password don't match an account. Check the password, or use “Forgot password”.";
  if (m.includes("email not confirmed"))
    return "Please confirm your email first — check your inbox for the link we sent.";
  if (m.includes("password should be at least"))
    return "Your password needs to be at least 8 characters.";
  if (m.includes("unable to validate email") || m.includes("invalid format"))
    return "That doesn't look like a valid email address.";
  if (m.includes("rate limit") || m.includes("too many") || m.includes("for security purposes"))
    return "Too many attempts just now. Please wait a minute and try again.";
  if (m.includes("user already registered"))
    return "An account already exists for that email. Try signing in instead.";
  if (m.includes("same as the old password"))
    return "Please choose a password you haven't used on this account before.";
  if (m.includes("failed to fetch") || m.includes("networkerror") || m.includes("load failed"))
    return "We couldn't reach the server. Check your internet connection and try again.";
  return (e && e.message) || "Something went wrong. Please try again.";
}

async function logout() {
  await sb.auth.signOut();
  location.href = "index.html";
}

/* ---------- top bar ---------- */
/* `rel` prefixes every link and the logo. Pages one directory down — the blog —
   pass "../". Without it the topbar on a post points at /blog/app.html and the
   logo at /blog/logo.svg, so every link 404s and the mark renders as a broken
   image. Root-absolute paths would also fix it, but this repo is still published
   to GitHub Pages under a subpath, where those would break instead. */
async function renderTopbar(active, rel = "") {
  const el = document.getElementById("topbar");
  if (!el) return;
  const session = await getSession();
  let userHtml = "", adminLink = "";
  if (session) {
    const m = session.user.user_metadata || {};
    const name = m.full_name || m.name || m.user_name || session.user.email;
    /* GitHub and Google give us a picture; email signups don't — fall back to initials */
    const avatar = m.avatar_url
      ? `<img src="${escapeHtml(m.avatar_url)}" alt="">`
      : `<span class="avatar-initials">${escapeHtml(initialsOf(name))}</span>`;
    userHtml = `<div class="user">${avatar}<span class="uname">${escapeHtml(name)}</span>
      <button class="btn btn-sm btn-ghost" style="color:#fff;border-color:rgba(255,255,255,.35)" onclick="logout()">Logout</button></div>`;
    try {
      const { data: p } = await sb.from("profiles").select("role").eq("id", session.user.id).single();
      if (p && p.role === "admin")
        adminLink = `<a class="navlink ${active === "admin" ? "active" : ""}" href="${rel}admin.html">Admin</a>`;
    } catch (e) { /* ignore */ }
  }
  /* access badge: days left, or a prompt to subscribe */
  let accessHtml = "";
  if (session) {
    try {
      const { data } = await sb.rpc("my_access");
      const a = (data || [])[0];
      if (a && a.is_admin) accessHtml = `<span class="pill pill-done" style="margin-right:6px">Admin</span>`;
      else if (a && a.has_access) accessHtml =
        `<a class="navlink" href="${rel}pricing.html" title="Extend your access">\u2713 ${a.days_left}d left</a>`;
      else accessHtml = `<a class="btn btn-primary btn-sm" style="margin-right:8px" href="${rel}pricing.html">Unlock full access</a>`;
    } catch (e) { /* non-fatal */ }
  }

  el.innerHTML = `<div class="topbar-inner">
    <a class="logo" href="${rel}${session ? "app.html" : "index.html"}"><img class="logo-mark" src="${rel}logo.svg" alt="" width="26" height="26">${window.QT_CONFIG.SITE_NAME}</a>
    <span class="spacer"></span>
    ${session ? `<a class="navlink ${active === "app" ? "active" : ""}" href="${rel}app.html">My Course</a>
    ${window.QT_CONFIG.RAG_CONSOLE_URL ? `<a class="navlink ${active === "projects" ? "active" : ""}" href="${rel}projects.html">Projects</a>` : ""}
    <a class="navlink ${active === "cert" ? "active" : ""}" href="${rel}certificate.html">Certificates</a>`
    /* Signed out means either a visitor deciding whether to sign up, or a crawler.
       Both need the course pages to be reachable by a link — a page nobody links to
       is a page search engines treat as unimportant, however good it is. Signed-in
       students get their own course nav instead and do not need the sales pages. */
    : `<a class="navlink ${active === "genai" ? "active" : ""}" href="${rel}genai-testing-course.html">GenAI Testing</a>
    <a class="navlink ${active === "python" ? "active" : ""}" href="${rel}python-dsa-course.html">Python &amp; DSA</a>
    <a class="navlink ${active === "faq" ? "active" : ""}" href="${rel}faq.html">FAQ</a>`}
    <a class="navlink ${active === "pricing" ? "active" : ""}" href="${rel}pricing.html">Pricing</a>
    <a class="navlink ${active === "verify" ? "active" : ""}" href="${rel}verify.html">Verify</a>
    ${adminLink} ${accessHtml} ${userHtml}</div>`;
}

/* ---------- misc ---------- */
function initialsOf(name) {
  const parts = String(name || "").trim().split(/[\s@._-]+/).filter(Boolean);
  if (!parts.length) return "?";
  return (parts[0][0] + (parts.length > 1 ? parts[parts.length - 1][0] : "")).toUpperCase();
}

function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
function fmtBytes(n) {
  if (!n) return "";
  const u = ["B", "KB", "MB", "GB"]; let i = 0;
  while (n >= 1024 && i < 3) { n /= 1024; i++; }
  return n.toFixed(n >= 10 || i === 0 ? 0 : 1) + " " + u[i];
}
function fmtDate(d) { return new Date(d).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" }); }

function kindFromFile(name) {
  const ext = name.split(".").pop().toLowerCase();
  if (["html", "htm"].includes(ext)) return "html";
  if (ext === "gif") return "gif";
  if (["png", "jpg", "jpeg", "webp", "svg", "avif"].includes(ext)) return "image";
  if (ext === "pdf") return "pdf";
  if (["ppt", "pptx"].includes(ext)) return "pptx";
  if (["doc", "docx"].includes(ext)) return "docx";
  if (["xls", "xlsx", "csv"].includes(ext)) return "xlsx";
  return "other";
}
const KIND_LABEL = { html: "HTML Lesson", image: "Image", gif: "Animation", pdf: "PDF", pptx: "Slides", docx: "Document", xlsx: "Spreadsheet", other: "File" };

/* signed URL for a private material (1 hour) */
async function signedUrl(path, seconds = 3600) {
  const { data, error } = await sb.storage.from("materials").createSignedUrl(path, seconds);
  if (error) throw error;
  return data.signedUrl;
}

/* mark progress */
async function markProgress(materialId, status) {
  const session = await getSession();
  if (!session) return;
  await sb.from("progress").upsert(
    { user_id: session.user.id, material_id: materialId, status, updated_at: new Date().toISOString() },
    { onConflict: "user_id,material_id" });
}

/* ---------- PWA registration ---------- */
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => navigator.serviceWorker.register("sw.js").catch(() => {}));
}
