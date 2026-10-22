import type { Config } from './config.js';
import { client } from './repository.js';
export async function schedulerTick(cfg:Config){if(!cfg.serviceKey)throw new Error('SUPABASE_SERVICE_ROLE_KEY required for scheduler');const {data,error}=await client(cfg,undefined,cfg.serviceKey).rpc('run_scheduler',{p_now:new Date().toISOString()});if(error)throw new Error('Scheduler database operation failed');return Number(data);}
export function startScheduler(cfg:Config,tick=()=>schedulerTick(cfg)){
 let running=false;let stopped=false;
 const run=async()=>{if(running||stopped)return;running=true;try{await tick();}catch{console.error('Scheduler failed; will retry next interval');}finally{running=false;}};
 const timer=setInterval(()=>void run(),cfg.schedulerInterval);timer.unref();void run();return ()=>{stopped=true;clearInterval(timer);};
}
