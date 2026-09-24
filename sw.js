// Bump CACHE whenever you change index.html so phones pick up the new version.
const CACHE = 'cinco-v32';
const ASSETS = ['./', './index.html', './manifest.webmanifest', './icons/icon-180.png', './icons/icon-192.png', './icons/icon-512.png', './fonts/lilita-one.woff2', './fonts/nunito.woff2', './fonts/nunito-italic.woff2'];

const ENGINE = [
  'https://cdn.jsdelivr.net/npm/@mintplex-labs/piper-tts-web@1.0.5/',
  'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.18.0/',
  'https://cdn.jsdelivr.net/npm/@diffusionstudio/piper-wasm@1.0.0/',
  'https://cdnjs.cloudflare.com/ajax/libs/onnxruntime-web/1.18.0/',
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  // Only old app versions. "cinco-words" (generated Piper words) and "cinco-engine" survive updates.
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('cinco-v') && k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
// Network first so updates arrive; cached copy keeps the app working offline.
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  // The Piper engine files are pinned to exact versions and never change, so keep them for offline use.
  // (The voice model itself lives in the phone's private file storage, not here.)
  if (ENGINE.some(p => e.request.url.startsWith(p))) {
    e.respondWith(caches.open('cinco-engine').then(c => c.match(e.request).then(hit => hit || fetch(e.request).then(res => {
      if (res.ok) c.put(e.request, res.clone());
      return res;
    }))));
    return;
  }
  // Otherwise only Cinco's own files.
  if (new URL(e.request.url).origin !== self.location.origin) return;
  // Recordings never change for a given file name, so serve them from the cache once they've been fetched.
  if (/\/audio\/.+\.m4a$/.test(new URL(e.request.url).pathname)) {
    e.respondWith(caches.open(CACHE).then(c => c.match(e.request).then(hit => hit || fetch(e.request).then(res => {
      if (res.ok) c.put(e.request, res.clone());
      return res;
    }))));
    return;
  }
  e.respondWith(
    fetch(e.request).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put(e.request, copy));
      return res;
    }).catch(() => caches.match(e.request).then(r => r || caches.match('./index.html')))
  );
});
