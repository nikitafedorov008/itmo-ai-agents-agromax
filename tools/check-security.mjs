import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {randomUUID as uuid} from 'node:crypto';
process.loadEnvFile('apps/api/.env');
const {session,fieldId}=JSON.parse(readFileSync('.data/smoke-session.json','utf8'));
const supabase=process.env.SUPABASE_URL, anon=process.env.SUPABASE_ANON_KEY, service=process.env.SUPABASE_SERVICE_ROLE_KEY;
const h={apikey:anon,Authorization:`Bearer ${session.accessToken}`,'Content-Type':'application/json'};
const admin={apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'};
async function rpc(name,body,headers=h){const r=await fetch(`${supabase}/rest/v1/rpc/${name}`,{method:'POST',headers,body:JSON.stringify(body)});return {status:r.status,data:await r.json()};}
const checks=[];
let r=await rpc('apply_operation',{p_operation_id:uuid(),p_type:'observation.upsert',p_payload:{id:uuid(),fieldId,note:{text:'x'},photoIds:[]}});assert.ok(r.status>=400||r.data.error,JSON.stringify(r));checks.push('Direct RPC rejects object-valued note');
r=await rpc('apply_operation',{p_operation_id:uuid(),p_type:'field.create',p_payload:{confirmed:true,name:{x:'bad'},crop:'wheat',areaHa:1,center:{lat:55,lng:37},boundary:[]}});assert.ok(r.status>=400||r.data.error);checks.push('Direct RPC rejects malformed field');
r=await rpc('apply_operation',{p_operation_id:uuid(),p_type:'observation.upsert',p_payload:{id:uuid(),fieldId,note:'x',photoIds:[],status:'approved'}});assert.ok(r.status>=400||r.data.error);checks.push('Direct RPC rejects injected approval state');
r=await rpc('finish_agent',{p_actor:session.user.id,p_operation_id:uuid(),p_conversation:{},p_result:{}});assert.ok(r.status>=400);checks.push('Authenticated callers cannot forge agent completion');
r=await rpc('register_photo',{p_id:uuid(),p_name:'fake.png',p_mime:'image/png'});assert.ok(r.status>=400||r.data.error);checks.push('Cannot register nonexistent photo evidence');
r=await rpc('run_scheduler',{});assert.ok(r.status>=400);checks.push('Scheduler denied to ordinary users');
const now=new Date(Date.now()+86400000).toISOString();const first=await rpc('run_scheduler',{p_now:now},admin);assert.equal(first.status,200);const second=await rpc('run_scheduler',{p_now:now},admin);assert.equal(second.data,0);checks.push('Scheduler durable deduplication');
const ba=await fetch('http://localhost:8787/api/bootstrap',{headers:h});const before=await ba.json();const photoId=before.observations.find(o=>o.photoIds.length).photoIds[0];
const removed=await fetch(`${supabase}/storage/v1/object/field-photos`,{method:'DELETE',headers:h,body:JSON.stringify({prefixes:[`${session.farm.id}/${photoId}`]})});
const checkPhoto=await fetch(`http://localhost:8787/api/photos/${photoId}`,{headers:h});assert.equal(checkPhoto.status,200);checks.push('Attached photo evidence survives direct delete attempt');
await fetch(`${supabase}/rest/v1/members?user_id=eq.${session.user.id}`,{method:'PATCH',headers:admin,body:JSON.stringify({role:'agronomist'})});
try{const response=await fetch('http://localhost:8787/api/fields',{method:'POST',headers:h,body:JSON.stringify({operationId:uuid(),confirmed:true,name:'Denied',crop:'wheat',areaHa:1,center:{lat:55,lng:37},boundary:[]})});assert.equal(response.status,403);checks.push('Agronomist cannot perform chief-only operation');}finally{await fetch(`${supabase}/rest/v1/members?user_id=eq.${session.user.id}`,{method:'PATCH',headers:admin,body:JSON.stringify({role:'chief'})});}
writeFileSync('.data/security-result.json',JSON.stringify({at:new Date().toISOString(),checks},null,2));console.log(JSON.stringify({passed:checks.length,checks},null,2));
