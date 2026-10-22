import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Bootstrap, Conversation, Field, Notification, Observation, Photo, Session, Source, Task } from '@agromax/contracts';
import type { Config } from './config.js';
import { PhotoIdCollision,uploadImmutablePhoto } from './photos.js';
import { ApiFailure, unwrap } from './domain.js';
export type FarmContext={farm:{id:string;name:string};demo:boolean;role:'chief'|'agronomist'};
export interface Repository {
 context():Promise<FarmContext>; bootstrap():Promise<Omit<Bootstrap,'providers'>>;
 field(id:string):Promise<Field>; observation(id:string):Promise<Observation>; conversation(id:string):Promise<Conversation>;
 sources(query:string):Promise<Source[]>; apply(operationId:string,type:string,payload:unknown):Promise<any>;
 photo(id:string):Promise<{path:string;data:Photo}>; upload(id:string,file:File):Promise<Photo>; download(path:string):Promise<Blob>;
 readNotification(id:string):Promise<Notification>; beginAgent(id:string,fingerprint:unknown):Promise<any>;
 finishAgent(id:string,conversation:Conversation|null,result:unknown,error?:string):Promise<void>; agentResult(id:string):Promise<any>;
}
function check<T>({data,error}:{data:T;error:any}):T {if(error)throw new ApiFailure(503,'DATABASE_UNAVAILABLE','Хранилище временно недоступно');return data;}
export function client(cfg:Config,token?:string,key=cfg.anonKey){if(!key)throw new ApiFailure(503,'STORAGE_UNCONFIGURED','Supabase не настроен');return createClient(cfg.supabaseUrl,key,{auth:{persistSession:false,autoRefreshToken:false},global:token?{headers:{Authorization:`Bearer ${token}`}}:undefined});}
export class SupabaseRepository implements Repository {
 constructor(public db:SupabaseClient,private admin?:SupabaseClient,private actor?:string){}
 async context(){const membership=check(await this.db.from('members').select('role,farm_id').single());if(!membership)throw new ApiFailure(401,'UNAUTHORIZED','Войдите в систему');const f=check(await this.db.from('farms').select('id,name,demo').eq('id',membership.farm_id).single());if(!f)throw new ApiFailure(401,'UNAUTHORIZED','Хозяйство не найдено');return {farm:{id:f.id,name:f.name},demo:f.demo,role:membership.role} as FarmContext;}
 async all<T>(table:string):Promise<T[]> {const result:T[]=[];for(let offset=0;;offset+=500){const rows=check(await this.db.from(table).select('data').order('id').range(offset,offset+499))||[];result.push(...rows.map(r=>r.data as T));if(rows.length<500)break;}return result;}
 async entity<T>(table:string,id:string):Promise<T>{const row=check(await this.db.from(table).select('data').eq('id',id).maybeSingle());if(!row)throw new ApiFailure(404,'NOT_FOUND','Запись не найдена');return row.data as T;}
 field(id:string){return this.entity<Field>('fields',id)}
 observation(id:string){return this.entity<Observation>('observations',id)}
 conversation(id:string){return this.entity<Conversation>('conversations',id)}
 async bootstrap(){const [ctx,fields,observations,tasks,conversations,notifications]=await Promise.all([this.context(),this.all<Field>('fields'),this.all<Observation>('observations'),this.all<Task>('tasks'),this.all<Conversation>('conversations'),this.all<Notification>('notifications')]);return {fields,observations,tasks,conversations,notifications:notifications.sort((a,b)=>b.createdAt.localeCompare(a.createdAt)),demo:ctx.demo};}
 async sources(query:string){const rows=check(await this.db.from('sources').select('*'));const terms=query.toLowerCase().split(/\s+/).filter(s=>s.length>2);return (rows||[]).map(r=>({r,score:terms.filter(t=>(r.title+' '+r.excerpt).toLowerCase().includes(t)).length})).sort((a,b)=>b.score-a.score).slice(0,3).map(v=>v.r as Source);}
 async apply(id:string,type:string,payload:unknown){return unwrap(check(await this.db.rpc('apply_operation',{p_operation_id:id,p_type:type,p_payload:payload})));}
 async photo(id:string){const row=check(await this.db.from('photos').select('path,data').eq('id',id).maybeSingle());if(!row)throw new ApiFailure(404,'NOT_FOUND','Фото не найдено');return row as {path:string;data:Photo};}
 async upload(id:string,file:File){
  const ctx=await this.context();const bucket=this.db.storage.from('field-photos');
  return uploadImmutablePhoto({
   get:async photoId=>{const row=check(await this.db.from('photos').select('data').eq('id',photoId).maybeSingle());return row?.data as Photo|undefined;},
   put:async(path,body,metadata)=>{const {error}=await bucket.upload(path,body,{contentType:body.type,metadata,upsert:false});if(error&&String((error as any).statusCode)!=='409'&&(error as any).error!=='Duplicate'&&(error as any).code!=='Duplicate')check({data:null,error});},
   info:async path=>{const metadata=check(await bucket.info(path));if(!metadata)throw new ApiFailure(503,'STORAGE_UNAVAILABLE','Не удалось проверить фото');return {originalName:metadata.metadata?.originalName,mimeType:metadata.contentType};},
   download:path=>this.download(path),
   register:async(photoId,body)=>{const result=await this.db.rpc('register_photo',{p_id:photoId,p_name:body.name,p_mime:body.type});if(result.error?.code==='23505')throw new PhotoIdCollision();return check(result) as Photo;},
   remove:async path=>{check(await bucket.remove([path]));}
  },ctx.farm.id,id,file);
 }
 async download(path:string){const blob=check(await this.db.storage.from('field-photos').download(path));if(!blob)throw new ApiFailure(404,'NOT_FOUND','Фото не найдено');return blob;}
 async readNotification(id:string){const result=check(await this.db.rpc('read_notification',{p_id:id}));if(!result)throw new ApiFailure(404,'NOT_FOUND','Уведомление не найдено');return result as Notification;}
 async beginAgent(id:string,fingerprint:unknown){return unwrap<any>(check(await this.db.rpc('begin_agent',{p_operation_id:id,p_fingerprint:fingerprint})));}
 async finishAgent(id:string,conversation:Conversation|null,result:unknown,error?:string){if(!this.admin||!this.actor)throw new ApiFailure(503,'STORAGE_UNCONFIGURED','Не настроено сохранение агента');check(await this.admin.rpc('finish_agent',{p_actor:this.actor,p_operation_id:id,p_conversation:conversation,p_result:result,p_error:error||null}));}
 async agentResult(id:string){const row=check(await this.db.from('agent_runs').select('result').eq('operation_id',id).single());if(!row)throw new ApiFailure(404,'NOT_FOUND','Запрос не найден');return row.result;}
}
export async function authenticated(cfg:Config,token:string){const db=client(cfg,token);const {data,error}=await db.auth.getUser(token);if(error||!data.user)throw new ApiFailure(401,'UNAUTHORIZED','Сессия недействительна');return new SupabaseRepository(db,cfg.serviceKey?client(cfg,undefined,cfg.serviceKey):undefined,data.user.id);}
export async function auth(cfg:Config,kind:'login'|'signup'|'demo',input:any):Promise<Session|{confirmationRequired:true;email:string}>{
 const db=client(cfg);const response=kind==='demo'?await db.auth.signInAnonymously():kind==='login'?await db.auth.signInWithPassword(input):await db.auth.signUp({email:input.email,password:input.password,options:{data:{name:input.name}}});
 if(response.error)throw new ApiFailure(400,'AUTH_FAILED',response.error.message);
 if(!response.data.session){if(kind==='signup')return {confirmationRequired:true,email:input.email};throw new ApiFailure(401,'AUTH_FAILED','Не удалось открыть сессию');}
 const userDb=client(cfg,response.data.session.access_token);const ctx=check(await userDb.rpc('initialize_farm',{p_name:kind==='demo'?'Демо хозяйство':input.name?`${input.name} — хозяйство`:'Моё хозяйство'})) as FarmContext;
 return {accessToken:response.data.session.access_token,user:{id:response.data.user!.id,email:response.data.user!.email,role:ctx.role},farm:ctx.farm,demo:ctx.demo};
}
