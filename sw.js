/* Transfer PWA service worker — Build 75
 * Network-first for app code/config so published fixes are not trapped in cache.
 * Navigation pages remain cached under their own URL.
 */
const CACHE_NAME = 'transfer-pwa-v114';
const APP_SHELL = [
  '/', '/index.html', '/manifest.json', '/style.css',
  '/app.js', '/config.js', '/icon-180.png',
  '/icon-192.png', '/icon-512.png'
];
const UPDATE_FIRST = new Set(['/app.js', '/config.js', '/style.css', '/manifest.json']);

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key => key.startsWith('transfer-pwa-') && key !== CACHE_NAME)
          .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      try {
        const response = await fetch(request, { cache: 'no-store' });
        if (response && response.ok) await cache.put(request, response.clone());
        return response;
      } catch (error) {
        return (await cache.match(request)) || (await cache.match(url.pathname)) ||
          (await cache.match('/index.html')) ||
          new Response('Transfer is offline. Please reconnect and try again.', {
            status: 503, headers: { 'Content-Type': 'text/plain; charset=utf-8' }
          });
      }
    })());
    return;
  }

  const path = url.pathname;
  if (UPDATE_FIRST.has(path)) {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      try {
        const response = await fetch(request, { cache: 'no-store' });
        if (response && response.ok) await cache.put(request, response.clone());
        return response;
      } catch (error) {
        return (await cache.match(request)) || new Response('', { status: 504, statusText: 'Offline' });
      }
    })());
    return;
  }

  // Cache-first for stable images/icons; update the cache when missing.
  event.respondWith((async () => {
    const cached = await caches.match(request);
    if (cached) return cached;
    try {
      const response = await fetch(request);
      if (response && response.ok) {
        const cache = await caches.open(CACHE_NAME);
        await cache.put(request, response.clone());
      }
      return response;
    } catch (error) {
      return new Response('', { status: 504, statusText: 'Offline' });
    }
  })());
});
