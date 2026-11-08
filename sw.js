/* Transfer PWA service worker — Build 74
 * Navigation pages are cached by their own URL. In particular, install.html
 * can no longer overwrite the app's /index.html cache entry.
 */
const CACHE_NAME = 'transfer-pwa-v75';
const APP_SHELL = [
  '/', '/index.html', '/install.html', '/manifest.json', '/style.css',
  '/app.js', '/config.js', '/transfer-icon.svg', '/icon-180.png',
  '/icon-192.png', '/icon-512.png'
];

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
        const response = await fetch(request);
        if (response && response.ok) {
          // Keep each page at its own URL; never store install.html as index.html.
          await cache.put(request, response.clone());
        }
        return response;
      } catch (error) {
        return (await cache.match(request)) ||
          (await cache.match(url.pathname)) ||
          (await cache.match('/index.html')) ||
          new Response('Transfer is offline. Please reconnect and try again.', {
            status: 503,
            headers: { 'Content-Type': 'text/plain; charset=utf-8' }
          });
      }
    })());
    return;
  }

  // App-shell assets use cache-first, then refresh the cache from the network.
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
