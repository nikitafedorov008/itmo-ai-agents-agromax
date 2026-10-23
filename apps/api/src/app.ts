import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { bodyLimit } from 'hono/body-limit';
import { z } from 'zod';
import { randomUUID } from 'node:crypto';
import type { Config } from './config.js';
import { ApiFailure,chatInput,operationPayload,uuid } from './domain.js';
import { auth,authenticated,client,type Repository } from './repository.js';
import { runAgent } from './agent.js';
import { weather } from './weather.js';
import { monitoringSnapshot } from './monitoring.js';
export type Dependencies={authenticate?:(token:string)=>Promise<Repository>;auth?:typeof auth;fetch?:typeof fetch;monitoring?:typeof monitoringSnapshot};
export function createApp(cfg:Config,deps:Dependencies={}){
 const app=new Hono<{Variables:{repo:Repository}}>();
 app.use('/api/*',cors({origin:cfg.origins,allowHeaders:['Content-Type','Authorization'],allowMethods:['GET','POST','OPTIONS']}));
 app.use('/api/*',bodyLimit({maxSize:11*1024*1024,onError:c=>c.json({error:'Слишком большой запрос',code:'TOO_LARGE'},413)}));
 app.onError((err,c)=>{if(err instanceof ApiFailure)return c.json({error:err.message,code:err.code,...(err.current?{current:err.current}:{})},err.status as any);if(err instanceof z.ZodError)return c.json({error:'Проверьте данные запроса',code:'INVALID',details:err.issues.map(i=>({path:i.path,message:i.message}))},400);if(err instanceof SyntaxError)return c.json({error:'Неверный JSON',code:'INVALID'},400);console.error('API failure',err.name);return c.json({error:'Внутренняя ошибка сервера',code:'INTERNAL'},500);});
 app.get('/api/health',async c=>{try{const db=client(cfg,undefined,cfg.serviceKey||cfg.anonKey);const {error}=await db.from('sources').select('id').limit(1);return c.json({ok:!error,storage:error?'unavailable':'supabase'},error?503:200);}catch{return c.json({ok:false,storage:'unconfigured'},503);}});
 app.get('/api/metrics/demo',async c=>{c.header('Cache-Control','no-store');return c.json(await (deps.monitoring||monitoringSnapshot)(cfg));});
 app.post('/api/auth/demo',async c=>c.json(await (deps.auth||auth)(cfg,'demo',{})));
 app.post('/api/auth/login',async c=>{const body=z.object({email:z.string().email(),password:z.string().min(1).max(200)}).strict().parse(await c.req.json());return c.json(await (deps.auth||auth)(cfg,'login',body));});
 app.post('/api/auth/signup',async c=>{const body=z.object({email:z.string().email(),password:z.string().min(8).max(200),name:z.string().trim().min(1).max(100)}).strict().parse(await c.req.json());return c.json(await (deps.auth||auth)(cfg,'signup',body));});
 app.use('/api/*',async(c,next)=>{const header=c.req.header('Authorization')||'';if(!header.startsWith('Bearer ')||header.length<8)throw new ApiFailure(401,'UNAUTHORIZED','Войдите в систему');c.set('repo',await (deps.authenticate||((token)=>authenticated(cfg,token)))(header.slice(7)));await next();});
 app.get('/api/bootstrap',async c=>c.json({...await c.get('repo').bootstrap(),providers:cfg.providers.map(p=>({id:p.id,configured:Boolean(p.key),model:p.model}))}));
 app.get('/api/fields/:id/weather',async c=>{const field=await c.get('repo').field(uuid.parse(c.req.param('id')));return c.json(await weather(field,deps.fetch));});
 app.post('/api/photos',async c=>{const form=await c.req.formData();const file=form.get('file');if(!(file instanceof File)||!file.size||file.size>10*1024*1024)throw new ApiFailure(400,'INVALID_PHOTO','Нужен файл до 10 МБ');if(!['image/jpeg','image/png','image/webp'].includes(file.type))throw new ApiFailure(400,'INVALID_PHOTO','Поддерживаются JPEG, PNG и WebP');const bytes=new Uint8Array(await file.slice(0,16).arrayBuffer());const signatures:Record<string,boolean>={'image/jpeg':bytes[0]===255&&bytes[1]===216&&bytes[2]===255,'image/png':bytes.slice(0,8).join(',')==='137,80,78,71,13,10,26,10','image/webp':new TextDecoder().decode(bytes.slice(0,4))==='RIFF'&&new TextDecoder().decode(bytes.slice(8,12))==='WEBP'};if(!signatures[file.type])throw new ApiFailure(400,'INVALID_PHOTO','Содержимое файла не соответствует формату');if(!file.name.trim()||file.name.length>180)throw new ApiFailure(400,'INVALID_PHOTO','Имя фото должно содержать от 1 до 180 символов');const operationId=form.get('operationId');const id=operationId===null?randomUUID():uuid.parse(operationId);return c.json(await c.get('repo').upload(id,file),201);});
 app.get('/api/photos/:id',async c=>{const repo=c.get('repo');const photo=await repo.photo(uuid.parse(c.req.param('id')));const data=await repo.download(photo.path);return new Response(data,{headers:{'Content-Type':photo.data.mimeType,'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'}});});
 async function apply(repo:Repository,id:unknown,type:string,payload:unknown){return repo.apply(uuid.parse(id),type,operationPayload(type,payload));}
 app.post('/api/fields',async c=>{const {operationId,...body}=z.record(z.unknown()).parse(await c.req.json());return c.json(await apply(c.get('repo'),operationId,'field.create',body),201);});
 app.post('/api/observations',async c=>{const {operationId,...body}=z.record(z.unknown()).parse(await c.req.json());return c.json(await apply(c.get('repo'),operationId,'observation.upsert',body));});
 app.post('/api/observations/:id/approve',async c=>{const {operationId,...body}=z.record(z.unknown()).parse(await c.req.json());return c.json(await apply(c.get('repo'),operationId,'observation.approve',{...body,id:c.req.param('id')}));});
 app.post('/api/tasks/:id/complete',async c=>{const {operationId,...body}=z.record(z.unknown()).parse(await c.req.json());return c.json(await apply(c.get('repo'),operationId,'task.complete',{...body,id:c.req.param('id')}));});
 app.post('/api/agent/chat',async c=>c.json(await runAgent(c.get('repo'),cfg,chatInput.parse(await c.req.json()),deps.fetch)));
 app.post('/api/sync',async c=>{const {operations}=z.object({operations:z.array(z.object({operationId:uuid,type:z.enum(['field.create','observation.upsert','observation.approve','task.complete']),payload:z.record(z.unknown())}).strict()).max(100)}).strict().parse(await c.req.json());const results=[];for(const op of operations){try{results.push({operationId:op.operationId,status:'applied',data:await apply(c.get('repo'),op.operationId,op.type,op.payload)});}catch(e){results.push({operationId:op.operationId,status:e instanceof ApiFailure&&e.status===409?'conflict':'error',error:e instanceof ApiFailure?e.message:'Неверная операция',...(e instanceof ApiFailure&&e.current?{data:e.current}:{})});}}return c.json({results});});
 app.post('/api/notifications/:id/read',async c=>c.json(await c.get('repo').readNotification(uuid.parse(c.req.param('id')))));
 app.notFound(c=>c.json({error:'Маршрут не найден',code:'NOT_FOUND'},404));return app;
}
