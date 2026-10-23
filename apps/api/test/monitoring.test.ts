import {it,expect,vi} from 'vitest';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';
import {ApiFailure} from '../src/domain.js';
it('serves only the dedicated snapshot without creating a farm session',async()=>{
 const authenticate=vi.fn(),snapshot={schemaVersion:1,scope:'synthetic-demo-only',summary:{runs:3},events:[]};
 const app=createApp(config({}),{authenticate,monitoring:async()=>snapshot});
 const r=await app.request('/api/metrics/demo');expect(r.status).toBe(200);expect(await r.json()).toEqual(snapshot);expect(r.headers.get('cache-control')).toBe('no-store');expect(authenticate).not.toHaveBeenCalled();
 expect((await app.request('/api/bootstrap')).status).toBe(401);
 expect((await app.request('/api/metrics/other-farm')).status).toBe(401);
});
it('fails closed when monitoring storage is unavailable',async()=>{
 const app=createApp(config({}),{monitoring:async()=>{throw new ApiFailure(503,'MONITORING_UNAVAILABLE','Мониторинг временно недоступен');}});
 const r=await app.request('/api/metrics/demo');expect(r.status).toBe(503);expect((await r.json()).code).toBe('MONITORING_UNAVAILABLE');
});
