export type Provider = 'deepseek' | 'mimo';
export type Role = 'agronomist' | 'chief';
export type Point = {lat: number; lng: number};
export interface Field {id:string; name:string; crop:string; areaHa:number; center:Point; boundary:Point[]; demo:boolean}
export interface Photo {id:string; url:string; name:string; mimeType:string}
export interface Observation {id:string; fieldId:string; note:string; extent?:string; location?:Point; photoIds:string[]; status:'draft'|'approved'; version:number; createdAt:string; approvedAt?:string; parentObservationId?:string}
export interface Task {id:string; fieldId:string; observationId:string; title:string; dueAt:string; status:'open'|'done'; outcome?:string; version:number; createdAt:string}
export interface Source {id:string; title:string; url:string; excerpt:string; version:string}
export interface AgentArtifact {kind:'clarification'|'observation'|'summary'; title:string; body:string; observationId?:string; observationVersion?:number; proposedTask?:{title:string; dueAt:string}}
export interface AgentReply {id:string; text:string; provider:Provider; model:string; sources:Source[]; tools:string[]; artifact?:AgentArtifact; requiresConfirmation:boolean; createdAt:string}
export interface Message {id:string; role:'user'|'assistant'; text:string; createdAt:string; reply?:AgentReply}
export interface Conversation {id:string; fieldId:string; messages:Message[]}
export interface Notification {id:string; title:string; body:string; createdAt:string; read:boolean; fieldId?:string}
export interface Weather {fetchedAt:string; location:Point; days:{date:string; minC:number; maxC:number; rainMm:number}[]; source:string}
export interface Session {accessToken:string; user:{id:string; email?:string; role:Role}; farm:{id:string; name:string}; demo:boolean}
export interface Bootstrap {fields:Field[]; observations:Observation[]; tasks:Task[]; conversations:Conversation[]; notifications:Notification[]; providers:{id:Provider; configured:boolean; model:string}[]; demo:boolean}
export interface ObservationInput {id?:string; fieldId:string; note:string; extent?:string; location?:Point; photoIds:string[]; parentObservationId?:string; version?:number}
export interface SyncOperation {operationId:string; type:'observation.upsert'|'observation.approve'|'task.complete'; payload:Record<string,unknown>}
export interface SyncResult {operationId:string; status:'applied'|'conflict'|'error'; data?:unknown; error?:string}
export interface ApiError {error:string; code:string; current?:unknown}
export class ApiClient {
 constructor(public baseUrl:string, public token:string=''){}
 async request<T>(path:string, init:RequestInit={}):Promise<T>{const r=await fetch(this.baseUrl+path,{...init,headers:{...(init.body instanceof FormData?{}:{'Content-Type':'application/json'}),...(this.token?{Authorization:`Bearer ${this.token}`} :{}),...init.headers}});const data=await r.json();if(!r.ok)throw Object.assign(new Error(data.error||'Ошибка API'),{status:r.status,data});return data as T}
}
