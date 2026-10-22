import { serve } from '@hono/node-server';
import { config } from './config.js';
import { createApp } from './app.js';
import { startScheduler } from './scheduler.js';
const cfg=config();const app=createApp(cfg);const server=serve({fetch:app.fetch,port:cfg.port,hostname:'0.0.0.0'});console.log(`AGROMAX API listening on http://localhost:${cfg.port}`);
const stop=cfg.serviceKey?startScheduler(cfg):()=>{};if(!cfg.serviceKey)console.warn('Scheduler disabled: SUPABASE_SERVICE_ROLE_KEY missing');
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>{stop();server.close(()=>process.exit(0));});
