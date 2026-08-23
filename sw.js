/* GenAITesting — service worker
   Caches the app shell so the site opens instantly and works as an installed app.
   Data (Supabase) always goes to the network. */
/* Bump this version on every deploy — it evicts the old cache so returning
   students (and installed-app users) never get served a stale app shell. */
const CACHE = "qt-academy-v30";
const SHELL = [
  "./", "index.html", "app.html", "viewer.html", "quiz.html",
  "certificate.html", "verify.html", "pricing.html", "reset-password.html",
  "unsubscribe.html", "projects.html",
  "genai-testing-course.html", "python-dsa-course.html", "faq.html",
  "blog/",
  "app.css", "app.js", "config.js",
  "icon-192.png", "icon-512.png", "icon-maskable-512.png",
  "apple-touch-icon.png", "favicon.ico", "favicon.svg", "logo.svg", "social-card.png",
  "manifest.webmanifest"
];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  // only cache same-origin GET shell requests; Supabase/API/CDN always network
  if (e.request.method !== "GET" || url.origin !== location.origin) return;
  e.respondWith(
    fetch(e.request)
      .then(res => {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, copy));
        return res;
      })
      .catch(() => caches.match(e.request).then(r => r || caches.match("index.html")))
  );
});
