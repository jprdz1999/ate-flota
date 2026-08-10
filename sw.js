// Service worker de ATE Flota. Estrategia network-first para todo lo del propio
// origen (así online siempre sirve la versión fresca tras cada deploy, y offline
// sirve lo cacheado). Las llamadas a Supabase / CDN (otro origen) se dejan pasar
// sin tocar. La sincronización de datos capturados offline la maneja la app
// (cola en localStorage), no el SW.
const CACHE = 'ate-flota-v1';
const ASSETS = ['/', '/index.html', '/chequeo.html', '/orden-compra.html', '/shared.css', '/manifest.json', '/icon.svg'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (url.origin !== location.origin) return;            // Supabase/CDN: red directa
  if (e.request.method !== 'GET') return;
  e.respondWith(
    fetch(e.request)
      .then(resp => { const cp = resp.clone(); caches.open(CACHE).then(c => c.put(e.request, cp)); return resp; })
      .catch(() => caches.match(e.request).then(r =>
        r || (e.request.mode === 'navigate'
          ? caches.match(url.pathname.includes('chequeo') ? '/chequeo.html'
            : url.pathname.includes('orden-compra') ? '/orden-compra.html' : '/index.html')
          : undefined)))
  );
});
