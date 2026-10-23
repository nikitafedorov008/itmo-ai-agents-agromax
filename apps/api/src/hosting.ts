import { serveStatic } from '@hono/node-server/serve-static';
import type { Hono } from 'hono';

/** Same HTTPS origin for the web app and native API; never turn API errors into HTML. */
export function mountWeb(app: Hono<any>, root: string) {
  const assets = serveStatic({ root });
  const index = serveStatic({ path: `${root}/index.html` });
  app.get('*', async (c, next) => {
    if (c.req.path === '/api' || c.req.path.startsWith('/api/'))
      return c.json({ error: 'Маршрут не найден', code: 'NOT_FOUND' }, 404);
    c.header('X-Content-Type-Options', 'nosniff');
    c.header('Referrer-Policy', 'strict-origin-when-cross-origin');
    c.header('Cache-Control', c.req.path.startsWith('/assets/') ? 'public, max-age=31536000, immutable' : 'no-cache');
    return assets(c, next);
  });
  app.get('*', async (c, next) => {
    if (c.req.path.startsWith('/assets/') || /\.(?:js|css|map|png|svg|ico|webp|woff2?)$/.test(c.req.path))
      return c.notFound();
    const response = await index(c, next);
    return response || c.res;
  });
  return app;
}
