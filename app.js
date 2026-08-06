/* ============ QT GenAI Testing Academy — shared app helpers ============
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

function loginWithGitHub(redirectPage = "app.html") {
  const redirectTo = location.origin + location.pathname.replace(/[^/]*$/, "") + redirectPage;
  sb.auth.signInWithOAuth({ provider: "github", options: { redirectTo } });
}

async function logout() {
  await sb.auth.signOut();
  location.href = "index.html";
}

/* ---------- top bar ---------- */
async function renderTopbar(active) {
  const el = document.getElementById("topbar");
  if (!el) return;
  const session = await getSession();
  let userHtml = "", adminLink = "";
  if (session) {
    const m = session.user.user_metadata || {};
    const name = m.full_name || m.name || m.user_name || session.user.email;
    const avatar = m.avatar_url ? `<img src="${m.avatar_url}" alt="">` : "";
    userHtml = `<div class="user">${avatar}<span class="uname">${escapeHtml(name)}</span>
      <button class="btn btn-sm btn-ghost" style="color:#fff;border-color:rgba(255,255,255,.35)" onclick="logout()">Logout</button></div>`;
    try {
      const { data: p } = await sb.from("profiles").select("role").eq("id", session.user.id).single();
      if (p && p.role === "admin")
        adminLink = `<a class="navlink ${active === "admin" ? "active" : ""}" href="admin.html">Admin</a>`;
    } catch (e) { /* ignore */ }
  }
  el.innerHTML = `<div class="topbar-inner">
    <a class="logo" href="${session ? "app.html" : "index.html"}"><span class="logo-dot"></span>${window.QT_CONFIG.SITE_NAME}</a>
    <span class="spacer"></span>
    ${session ? `<a class="navlink ${active === "app" ? "active" : ""}" href="app.html">Materials</a>
    <a class="navlink ${active === "cert" ? "active" : ""}" href="certificate.html">My Certificate</a>` : ""}
    <a class="navlink ${active === "verify" ? "active" : ""}" href="verify.html">Verify</a>
    ${adminLink} ${userHtml}</div>`;
}

/* ---------- misc ---------- */
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
