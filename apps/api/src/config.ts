export type ProviderConfig={id:'deepseek'|'mimo';key:string;model:string;baseUrl:string};
export type Config={supabaseUrl:string;anonKey:string;serviceKey:string;port:number;origins:string[];timeoutMs:number;providers:ProviderConfig[];schedulerInterval:number};
export function config(env:NodeJS.ProcessEnv=process.env):Config{return {
 supabaseUrl:env.SUPABASE_URL||'http://127.0.0.1:54321',anonKey:env.SUPABASE_ANON_KEY||'',serviceKey:env.SUPABASE_SERVICE_ROLE_KEY||'',port:Number(env.PORT||8787),origins:(env.CORS_ORIGINS||'http://localhost:5173,http://localhost:4173').split(','),timeoutMs:Math.min(60000,Math.max(1000,Number(env.AGENT_TIMEOUT_MS||25000))),schedulerInterval:Math.max(10000,Number(env.SCHEDULER_INTERVAL_MS||60000)),
 providers:[{id:'deepseek',key:env.DEEPSEEK_API_KEY||'',model:env.DEEPSEEK_MODEL||'deepseek-flash',baseUrl:env.DEEPSEEK_BASE_URL||'https://api.deepseek.com'},{id:'mimo',key:env.MIMO_API_KEY||'',model:env.MIMO_MODEL||'mimo-v2.6-pro',baseUrl:env.MIMO_BASE_URL||'https://api.xiaomimimo.com/v1'}]
};}
