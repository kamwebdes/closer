// Closer offline support. Bump VERSION whenever you upload changed files so phones pick them up.
const VERSION = 'closer-v1';
const SHELL = ['./', 'index.html', 'approve.html', 'manifest.webmanifest',
  'icons/icon-192.png', 'icons/icon-512.png', 'icons/apple-touch-icon.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Never cache account or database traffic.
  if (url.hostname.endsWith('.supabase.co')) return;
  // Pages: network first so updates show up, saved copy when offline.
  if (req.mode === 'navigate') {
    e.respondWith(fetch(req).then(r => {
      const copy = r.clone();
      caches.open(VERSION).then(c => c.put(url.pathname.endsWith('approve.html') ? 'approve.html' : 'index.html', copy));
      return r;
    }).catch(() => caches.match(url.pathname.endsWith('approve.html') ? 'approve.html' : 'index.html')));
    return;
  }
  // Icons and fonts: saved copy first, fetched and saved the first time.
  e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(r => {
    if (r.ok || r.type === 'opaque') { const copy = r.clone(); caches.open(VERSION).then(c => c.put(req, copy)); }
    return r;
  })));
});
