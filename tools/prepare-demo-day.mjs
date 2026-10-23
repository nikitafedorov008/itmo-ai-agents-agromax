// Creates an isolated synthetic presentation farm; never resets existing farms.
import {readFileSync,writeFileSync,mkdirSync,existsSync} from 'node:fs';
import {randomUUID,randomBytes} from 'node:crypto';
const base=process.env.API_BASE_URL||'https://agromax-itmo.onrender.com';
const dir='.data/demo-day',file=`${dir}/fixture.json`;
mkdirSync(dir,{recursive:true});
const state=existsSync(file)?JSON.parse(readFileSync(file,'utf8')):{base,email:`demo-day-${Date.now()}@example.test`,password:randomBytes(24).toString('base64url'),ids:{}};
if(state.base!==base)throw Error('Fixture origin mismatch');
function save(){writeFileSync(file,JSON.stringify(state,null,2),{mode:0o600});}
save();
async function api(path,body,auth=true){const r=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{...(body instanceof FormData?{}:{'Content-Type':'application/json'}),...(auth?{Authorization:`Bearer ${state.session.accessToken}`}:{})},body:body===undefined?undefined:body instanceof FormData?body:JSON.stringify(body)});const data=await r.json();if(!r.ok)throw Error(`${path}: ${r.status} ${data.code||data.error||'request failed'}`);return data;}
try{state.session=await api('/api/auth/login',{email:state.email,password:state.password},false);}catch(e){if(state.registered)throw e;state.session=await api('/api/auth/signup',{email:state.email,password:state.password,name:'АГРОМАКС · ДЕМО-ДЕНЬ · учебное хозяйство'},false);if(!state.session.accessToken)throw Error('Signup requires email confirmation');state.registered=true;save();}
state.registered=true;save();
async function once(key,fn){if(!state.ids[key]){state.ids[key]=await fn();save();}return state.ids[key];}
const field=await once('field',()=>api('/api/fields',{operationId:randomUUID(),confirmed:true,name:'Поле №7 · Северное · учебное',crop:'Озимая пшеница',areaHa:54,center:{lat:55.75,lng:36.95},boundary:[{lat:55.748,lng:36.946},{lat:55.752,lng:36.946},{lat:55.752,lng:36.954},{lat:55.748,lng:36.954}]}));
await once('secondField',()=>api('/api/fields',{operationId:randomUUID(),confirmed:true,name:'Поле №12 · контрольное · учебное',crop:'Ячмень',areaHa:32,center:{lat:55.76,lng:36.97},boundary:[]}));
const earlier=await once('earlier',()=>api('/api/observations',{operationId:randomUUID(),id:randomUUID(),fieldId:field.id,note:'Синтетическая история для демо. Первичный осмотр: листья внутри поля без заметного пожелтения, у северного края небольшой участок изменённой окраски. Причина не установлена; измерений почвы нет.',extent:'Около 2% площади · учебная оценка',photoIds:[]}));
const priorApproval=await once('earlierApproval',()=>api(`/api/observations/${earlier.id}/approve`,{operationId:randomUUID(),version:earlier.version,confirmed:true,task:{title:'Сравнить северный край и центр · учебная задача',dueAt:new Date(Date.now()+86400000).toISOString()}}));
const photo=await once('photo',()=>{const form=new FormData();form.set('operationId',randomUUID());form.set('file',new File([readFileSync('apps/web/public/wheat-leaf.png')],'botanical-illustration-demo.png',{type:'image/png'}));return api('/api/photos',form);});
const current=await once('current',()=>api('/api/observations',{operationId:randomUUID(),id:randomUUID(),fieldId:field.id,note:'Учебный сценарий, не настоящий осмотр. На нижних листьях у северного края озимой пшеницы заметно пожелтение, в центре явных изменений не вижу. Ранее в истории отмечали около 2%, сейчас оцениваю примерно 5%. Вложение — ботаническая ИИ-иллюстрация для демонстрации загрузки, не фото реального поля. Причина не определена; нужны уточнения и план повторного осмотра.',extent:'Около 5% · учебная оценка',photoIds:[photo.id],parentObservationId:earlier.id}));
const snapshot=await api('/api/bootstrap');
if(!snapshot.observations.some(o=>o.id===current.id&&o.status==='draft'))throw Error('Current demo is already approved; preserve history and prepare a new fixture manually.');
if(!snapshot.tasks.some(t=>t.id===priorApproval.task.id))throw Error('Context task missing');
writeFileSync(`${dir}/mobile-config.json`,JSON.stringify({API_BASE_URL:base,TEST_EMAIL:state.email,TEST_PASSWORD:state.password}),{mode:0o600});
console.log(JSON.stringify({ready:true,fields:snapshot.fields.length,observations:snapshot.observations.length,tasks:snapshot.tasks.length,currentStatus:'draft',credentials:'Saved only in .data/demo-day/fixture.json; not printed'},null,2));
