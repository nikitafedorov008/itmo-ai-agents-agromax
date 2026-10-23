import { afterAll, describe, expect, it } from 'vitest';
import { Hono } from 'hono';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { mountWeb } from '../src/hosting.js';
import { config } from '../src/config.js';

const root=mkdtempSync(join(tmpdir(),'agromax-hosting-'));
mkdirSync(join(root,'assets'));
writeFileSync(join(root,'index.html'),'<html>AGROMAX web</html>');
writeFileSync(join(root,'assets/app.js'),'export const ready=true;');
afterAll(()=>rmSync(root,{recursive:true,force:true}));
describe('same-origin production host',()=>{
  it('serves the SPA and real assets, while retaining API responses and missing-resource errors',async()=>{
    const app=mountWeb(new Hono().get('/api/ping',c=>c.json({ok:true})),root);
    expect(await (await app.request('/api/ping')).json()).toEqual({ok:true});
    const absent=await app.request('/api/unknown');
    expect(absent.status).toBe(404);expect(await absent.json()).toMatchObject({code:'NOT_FOUND'});
    expect(await (await app.request('/fields/example')).text()).toContain('AGROMAX web');
    const asset=await app.request('/assets/app.js');
    expect(await asset.text()).toContain('ready=true');expect(asset.headers.get('cache-control')).toContain('immutable');
    expect((await app.request('/assets/missing.js')).status).toBe(404);
  });
  it('uses the actual Render public origin for CORS, with explicit overrides',()=>{
    expect(config({RENDER_EXTERNAL_URL:'https://example.onrender.com'}).origins).toEqual(['https://example.onrender.com']);
    expect(config({CORS_ORIGINS:'https://web.example, https://other.example',RENDER_EXTERNAL_URL:'https://ignored.example'}).origins).toEqual(['https://web.example','https://other.example']);
  });
});
