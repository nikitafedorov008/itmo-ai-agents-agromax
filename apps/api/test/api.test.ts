import { describe,it,expect,vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createApp } from '../src/app.js';
import { config } from '../src/config.js';
import { ApiFailure,parseModelReply } from '../src/domain.js';
import { startScheduler } from '../src/scheduler.js';
import type { Repository } from '../src/repository.js';
const fieldId=randomUUID(),obsId=randomUUID();
const field={id:fieldId,name:'Тест',crop:'Пшеница',areaHa:1,center:{lat:55,lng:37},boundary:[],demo:true};
const cfg=config({SUPABASE_SERVICE_ROLE_KEY:'test-service-key',DEEPSEEK_API_KEY:'test-key',AGENT_TIMEOUT_MS:'1000'});
function fixture(){
 const record={id:obsId,fieldId,note:'Лист желтеет',photoIds:[],version:1,status:'draft',createdAt:new Date().toISOString()};
 const conversations=new Map<string,any>();const runs=new Map<string,any>();const operations=new Map<string,any>();let observations=[record];
 const repo={context:async()=>({farm:{id:randomUUID(),name:'Тест'},role:'chief',demo:true}),field:async(id:string)=>{if(id!==fieldId)throw new ApiFailure(404,'NOT_FOUND','Нет поля');return field;},observation:async(id:string)=>{if(id!==obsId)throw new ApiFailure(404,'NOT_FOUND','Нет наблюдения');return observations[0];},conversation:async(id:string)=>{const conversation=conversations.get(id);if(!conversation)throw new ApiFailure(404,'NOT_FOUND','Нет диалога');return conversation;},bootstrap:async()=>({fields:[field],observations,tasks:[],conversations:[],notifications:[],demo:true}),sources:async()=>[{id:'fao',title:'FAO',url:'https://www.fao.org/',excerpt:'IPM',version:'2026'}],apply:vi.fn(async(id,type,payload)=>{const fp=JSON.stringify({type,payload});if(operations.has(id)){const op=operations.get(id);if(op.fp!==fp)throw new ApiFailure(409,'IDEMPOTENCY_MISMATCH','Повтор id');return op.result;}if(payload.version!==observations[0].version)throw new ApiFailure(409,'CONFLICT','Версия',observations[0]);observations=[{...observations[0],status:'approved',version:2}];const result={observation:observations[0]};operations.set(id,{fp,result});return result;}),beginAgent:async(id:string,fp:any)=>{const run=runs.get(id);if(run){if(JSON.stringify(run.fp)!==JSON.stringify(fp))throw new ApiFailure(409,'IDEMPOTENCY_MISMATCH','Повтор id');if(run.result)return {cached:run.result};throw new ApiFailure(409,'IN_PROGRESS','Выполняется');}runs.set(id,{fp});return {started:true};},finishAgent:vi.fn(async(id,conversation,result,error)=>{if(conversation){const previous=conversations.get(conversation.id);const saved={...conversation,messages:[...(previous?.messages||[]),...conversation.messages]};conversations.set(saved.id,saved);result={...result,conversation:saved};}runs.set(id,{...runs.get(id),result,error});}),agentResult:async(id:string)=>runs.get(id).result,photo:async()=>{throw new ApiFailure(404,'NOT_FOUND','Нет фото')},upload:vi.fn(),download:vi.fn(),readNotification:vi.fn()} as unknown as Repository;
 const fetcher=vi.fn();const app=createApp(cfg,{authenticate:async()=>repo,fetch:fetcher as any});
 const request=(path:string,body?:unknown,token=true)=>app.request('/api'+path,{method:body?'POST':'GET',headers:{...(token?{Authorization:'Bearer session'}:{}),'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
 return {app,repo,request,fetcher,runs};
}
const completion=(content:any,tool_calls?:any[])=>new Response(JSON.stringify({choices:[{message:{role:'assistant',content:typeof content==='string'?content:JSON.stringify(content),...(tool_calls?{tool_calls}:{})}}]}),{headers:{'Content-Type':'application/json'}});
describe('API trust boundary',()=>{
 it('requires auth and never exposes public scheduler',async()=>{const f=fixture();expect((await f.request('/bootstrap',undefined,false)).status).toBe(401);expect((await f.request('/jobs/run',{})).status).toBe(404);});
 it('rejects confirmation omission and false before persistence',async()=>{const f=fixture();for(const confirmed of [undefined,false])expect((await f.request(`/observations/${obsId}/approve`,{operationId:randomUUID(),version:1,confirmed})).status).toBe(400);expect(f.repo.apply).not.toHaveBeenCalled();});
 it('keeps idempotency and returns current on conflict',async()=>{const f=fixture();const op={operationId:randomUUID(),version:1,confirmed:true};const first=await f.request(`/observations/${obsId}/approve`,op);const second=await f.request(`/observations/${obsId}/approve`,op);expect(await second.json()).toEqual(await first.json());const conflict=await f.request(`/observations/${obsId}/approve`,{...op,operationId:randomUUID()});expect(conflict.status).toBe(409);expect((await conflict.json()).current.version).toBe(2);const mismatch=await f.request(`/observations/${obsId}/approve`,{...op,version:2});expect(mismatch.status).toBe(409);});
 it('unknown or cross-tenant fields and photos are hidden',async()=>{const f=fixture();expect((await f.request(`/fields/${randomUUID()}/weather`)).status).toBe(404);expect((await f.request(`/photos/${randomUUID()}`)).status).toBe(404);});
 it('requires field confirmation and rejects incomplete contours',async()=>{const f=fixture();const input={operationId:randomUUID(),name:'A',crop:'B',areaHa:10,center:{lat:55,lng:37},boundary:[]};expect((await f.request('/fields',input)).status).toBe(400);expect((await f.request('/fields',{...input,confirmed:true,boundary:[{lat:55,lng:37}]})).status).toBe(400);expect(f.repo.apply).not.toHaveBeenCalled();});
 it('rejects invalid coordinates, operation shapes and files',async()=>{const f=fixture();expect((await f.request('/observations',{operationId:randomUUID(),fieldId,note:'a',photoIds:[],location:{lat:200,lng:0}})).status).toBe(400);expect((await f.request('/sync',{operations:[{operationId:randomUUID(),type:'task.complete',payload:{}}]})).status).toBe(200);expect(f.repo.apply).not.toHaveBeenCalled();});
});
describe('bounded model agent',()=>{
 it('accepts fenced JSON and nullable optional fields without accepting loose text',()=>{expect(parseModelReply('```json\n{"text":"Уточните симптомы","sourceIds":[],"artifact":null}\n```').artifact).toBeUndefined();expect(()=>parseModelReply('prefix {"text":"a","sourceIds":[]}')).toThrow();expect(()=>parseModelReply('{"text":"a","sourceIds":["fake"],"artifact":{"kind":"summary","title":"A","body":"B","proposedTask":{"title":null,"dueAt":null}}}')).toThrow();});
 it('returns explicit unconfigured state with no fake fallback',async()=>{const f=fixture();const app=createApp(config({}),{authenticate:async()=>f.repo});const r=await app.request('/api/agent/chat',{method:'POST',headers:{Authorization:'Bearer session','Content-Type':'application/json'},body:JSON.stringify({operationId:randomUUID(),fieldId,message:'Осмотри поле',provider:'deepseek'})});expect(r.status).toBe(503);expect((await r.json()).code).toBe('MODEL_UNCONFIGURED');});
 it('uses read-only tool, attaches only retrieved sources and persists turn',async()=>{const f=fixture();f.fetcher.mockResolvedValueOnce(completion(null,[{id:'call1',type:'function',function:{name:'source_search',arguments:'{"query":"IPM"}'}}])).mockResolvedValueOnce(completion({text:'Нужно осмотреть листья.',sourceIds:['fao'],artifact:{kind:'observation',title:'Осмотр',body:'Проверить листья',observationId:obsId,observationVersion:1,proposedTask:{title:'Осмотр',dueAt:'2026-10-25T09:00:00Z'}}}));const body={operationId:randomUUID(),fieldId,message:'Что делать?',provider:'deepseek',observationId:obsId};const r=await f.request('/agent/chat',body);expect(r.status).toBe(200);const result=await r.json();expect(result.reply.sources[0].id).toBe('fao');expect(result.reply.requiresConfirmation).toBe(true);expect(f.repo.apply).not.toHaveBeenCalled();expect(f.repo.finishAgent).toHaveBeenCalled();const again=await f.request('/agent/chat',body);expect(again.status).toBe(200);expect(f.fetcher).toHaveBeenCalledTimes(2);});
 it.each([{text:'ответ',sourceIds:['fabricated']},{text:'ответ',sourceIds:[],artifact:{kind:'observation',title:'a',body:'b',observationId:randomUUID(),observationVersion:1}}])('rejects fabricated citations or observation binding',async output=>{const f=fixture();f.fetcher.mockImplementation(async()=>completion(output));const r=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,observationId:obsId,message:'test',provider:'deepseek'});expect(r.status).toBe(502);expect((await r.json()).code).toBe('INVALID_MODEL_OUTPUT');expect(f.repo.apply).not.toHaveBeenCalled();});
 it('asks the model to repair invalid final citations once and validates the actual corrected response',async()=>{const f=fixture();f.fetcher.mockResolvedValueOnce(completion({text:'Первый ответ',sourceIds:['invented']})).mockResolvedValueOnce(completion({text:'Уточните распространение симптомов.',sourceIds:['fao'],artifact:null}));const r=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,message:'test',provider:'deepseek'});expect(r.status).toBe(200);expect((await r.json()).reply.sources.map((s:any)=>s.id)).toEqual(['fao']);expect(f.fetcher).toHaveBeenCalledTimes(2);const repair=JSON.parse(f.fetcher.mock.calls[1][1].body);expect(repair.tools).toBeUndefined();expect(repair.messages.at(-1).content).toContain('fao');expect(f.repo.apply).not.toHaveBeenCalled();});
 it('rejects arbitrary write tool calls',async()=>{const f=fixture();f.fetcher.mockResolvedValueOnce(completion(null,[{id:'call',type:'function',function:{name:'approve_observation',arguments:'{}'}}]));const r=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,message:'Подтверждаю',provider:'deepseek'});expect(r.status).toBe(502);expect(f.repo.apply).not.toHaveBeenCalled();});
 it('uses the documented MiMo token limit parameter',async()=>{const f=fixture();const app=createApp({...cfg,providers:[...cfg.providers.filter(p=>p.id!=='mimo'),{id:'mimo',key:'mimo-test-key',model:'mimo-v2.6-pro',baseUrl:'https://api.xiaomimimo.com/v1'}]},{authenticate:async()=>f.repo,fetch:f.fetcher as any});f.fetcher.mockResolvedValueOnce(completion({text:'Уточните симптомы',sourceIds:[]}));const response=await app.request('/api/agent/chat',{method:'POST',headers:{Authorization:'Bearer session','Content-Type':'application/json'},body:JSON.stringify({operationId:randomUUID(),fieldId,message:'test',provider:'mimo'})});expect(response.status).toBe(200);const sent=JSON.parse(f.fetcher.mock.calls[0][1].body);expect(sent.max_completion_tokens).toBe(2000);expect(sent.max_tokens).toBeUndefined();});
 it('rejects malformed arguments',async()=>{const f=fixture();f.fetcher.mockResolvedValueOnce(completion(null,[{id:'call',type:'function',function:{name:'weather',arguments:'{"fieldId":"other"}'}}]));expect((await f.request('/agent/chat',{operationId:randomUUID(),fieldId,message:'test',provider:'deepseek'})).status).toBe(502);});
 it('propagates provider errors and records failed run',async()=>{const f=fixture();f.fetcher.mockResolvedValueOnce(new Response('provider secret details',{status:500}));const id=randomUUID();const r=await f.request('/agent/chat',{operationId:id,fieldId,message:'test',provider:'deepseek'});expect(r.status).toBe(502);expect(f.runs.get(id).error).toBe('PROVIDER_ERROR');expect(await r.text()).not.toContain('secret');});
 it('bounds tool rounds',async()=>{const f=fixture();f.fetcher.mockImplementation(async()=>completion(null,[{id:'call',type:'function',function:{name:'open_tasks',arguments:'{}'}}]));const r=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,message:'test',provider:'deepseek'});expect(r.status).toBe(502);expect((await r.json()).code).toBe('AGENT_LIMIT');expect(f.fetcher).toHaveBeenCalledTimes(4);});
 it('returns explicit timeout',async()=>{const f=fixture();f.fetcher.mockImplementation((_url,init)=>new Promise((_resolve,reject)=>init.signal.addEventListener('abort',()=>reject(new Error('aborted')))));const r=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,message:'test',provider:'deepseek'});expect(r.status).toBe(504);expect((await r.json()).code).toBe('AGENT_TIMEOUT');});
});
describe('background runner',()=>{
 it('prevents overlapping ticks and stops cleanly',async()=>{vi.useFakeTimers();let release:()=>void=()=>{};const tick=vi.fn(()=>new Promise<void>(r=>{release=r}));const stop=startScheduler({...cfg,schedulerInterval:10000},tick as any);await vi.advanceTimersByTimeAsync(30000);expect(tick).toHaveBeenCalledTimes(1);release();await Promise.resolve();await vi.advanceTimersByTimeAsync(10000);expect(tick).toHaveBeenCalledTimes(2);stop();release();await vi.advanceTimersByTimeAsync(30000);expect(tick).toHaveBeenCalledTimes(2);vi.useRealTimers();});
});

describe('grounded workbench artifacts',()=>{
 const question={prompt:'Где заметно пожелтение?',options:['На нижних листьях','На всех листьях'],allowCustom:true};
 const clarification={kind:'clarification',title:'Уточнить признаки',body:'Нужно уточнить распространение.',stage:'signs',question,evidence:[{kind:'observation',summary:'Записано пожелтение листа.'},{kind:'history',summary:'Получена история поля.'}],actions:['reply','open_history']};
 it.each([
  {...clarification,question:undefined},
  {...clarification,question:{...question,options:['Да',' да ']}},
  {...clarification,question:{...question,options:[' ']}},
  {...clarification,question:{...question,options:[],allowCustom:false}},
  {...clarification,question:{...question,options:Array.from({length:7},(_,i)=>String(i))}},
  {...clarification,question:{...question,url:'https://example.com'}},
  {...clarification,actions:['approve_observation']},
  {...clarification,actions:['reply','reply']},
  {...clarification,stage:'confirmed'},
  {...clarification,body:undefined,startRevisit:{observationId:obsId,observationVersion:1}},
  {...clarification,evidence:[{kind:'satellite',summary:'Unsupported'}]},
  {...clarification,evidence:[{kind:'history',summary:' '}]},
 ])('rejects invalid workbench shape without executing writes',async artifact=>{
  const f=fixture();f.fetcher.mockImplementation(async()=>completion({text:'Уточнение',sourceIds:[],artifact}));
  const r=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,observationId:obsId,message:'Что видно?',provider:'deepseek'});
  expect(r.status).toBe(502);expect((await r.json()).code).toBe('INVALID_MODEL_OUTPUT');expect(f.fetcher).toHaveBeenCalledTimes(2);expect(f.repo.apply).not.toHaveBeenCalled();
 });
 it.each([
  {evidence:[{kind:'weather',summary:'Прогноз получен.'}]},
  {evidence:[{kind:'source',summary:'По источнику.'}]},
  {actions:['open_weather']},
  {actions:['view_sources']},
  {actions:['start_revisit'],observationId:obsId,observationVersion:1},
  {actions:['review_observation']},
  {actions:['review_observation'],observationId:obsId,observationVersion:99},
 ])('rejects unsupported evidence and action prerequisites',async extra=>{
  const f=fixture();f.fetcher.mockImplementation(async()=>completion({text:'Ответ',sourceIds:[],artifact:{kind:'summary',title:'Итог',body:'Данные',...extra}}));
  const r=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,observationId:obsId,message:'Осмотр',provider:'deepseek'});
  expect(r.status).toBe(502);expect(f.repo.apply).not.toHaveBeenCalled();
 });
 it('rejects observation evidence without a selected observation',async()=>{
  const f=fixture();f.fetcher.mockImplementation(async()=>completion({text:'Ответ',sourceIds:[],artifact:clarification}));
  const response=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,message:'Осмотр',provider:'deepseek'});expect(response.status).toBe(502);
 });
 it.each([
  {actions:['review_observation']},
  {proposedTask:{title:'Осмотр',dueAt:'2026-10-25T09:00:00Z'}},
 ])('rejects review and task proposals on an approved observation',async extra=>{
  const f=fixture();await f.repo.apply(randomUUID(),'observation.approve',{id:obsId,version:1,confirmed:true});vi.mocked(f.repo.apply).mockClear();
  f.fetcher.mockImplementation(async()=>completion({text:'Ответ',sourceIds:[],artifact:{kind:'summary',title:'Итог',body:'Осмотр',observationId:obsId,observationVersion:2,...extra}}));
  const response=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,observationId:obsId,message:'Осмотр',provider:'deepseek'});expect(response.status).toBe(502);expect(f.repo.apply).not.toHaveBeenCalled();
 });
 it('repairs a missing structured question with actual model output',async()=>{
  const f=fixture();f.fetcher.mockResolvedValueOnce(completion({text:'Где признаки?',sourceIds:[],artifact:{kind:'clarification',title:'Уточнение',body:'Где признаки?'}})).mockResolvedValueOnce(completion({text:'Опишите признаки',sourceIds:[],artifact:{...clarification,question:{prompt:'Опишите признаки',options:[],allowCustom:true}}}));
  const response=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,observationId:obsId,message:'Осмотр',provider:'deepseek'});expect(response.status).toBe(200);expect((await response.json()).reply.artifact.question).toEqual({prompt:'Опишите признаки',options:[],allowCustom:true});expect(f.fetcher).toHaveBeenCalledTimes(2);
 });
 it('persists model question and selected answer in the same conversation and observation',async()=>{
  const f=fixture();f.fetcher.mockResolvedValueOnce(completion({text:question.prompt,sourceIds:[],artifact:clarification}));
  const first=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,observationId:obsId,message:'Лист желтеет',provider:'deepseek'});expect(first.status).toBe(200);const result=await first.json();
  expect(result.reply.artifact).toEqual(clarification);expect(result.reply.requiresConfirmation).toBe(false);
  f.fetcher.mockResolvedValueOnce(completion({text:'Проверьте распространение на нижних листьях.',sourceIds:['fao'],artifact:{kind:'observation',title:'Осмотр',body:'Проверить распространение',stage:'decision',observationId:obsId,observationVersion:1,actions:['review_observation','view_sources'],evidence:[{kind:'source',summary:'Доступен источник FAO.'}]}}));
  const answer={operationId:randomUUID(),conversationId:result.conversation.id,fieldId,observationId:obsId,message:question.options[0],provider:'deepseek'};
  const second=await f.request('/agent/chat',answer);expect(second.status).toBe(200);const saved=await second.json();
  expect(saved.conversation.id).toBe(result.conversation.id);expect(saved.conversation.messages).toHaveLength(4);expect(saved.reply.artifact.observationId).toBe(obsId);expect(saved.reply.requiresConfirmation).toBe(true);
  const messages=JSON.parse(f.fetcher.mock.calls[1][1].body).messages;expect(messages.at(-1).content).toBe(question.options[0]);expect(messages.some((m:any)=>m.content.includes(question.prompt))).toBe(true);expect(f.repo.apply).not.toHaveBeenCalled();
  await f.request('/agent/chat',answer);expect(f.fetcher).toHaveBeenCalledTimes(2);
 });
 it('accepts actual weather evidence only after a successful scoped tool read',async()=>{
  const f=fixture();f.fetcher.mockResolvedValueOnce(completion(null,[{id:'weather1',type:'function',function:{name:'weather',arguments:'{}'}}])).mockResolvedValueOnce(new Response(JSON.stringify({daily:{time:['2026-10-24'],temperature_2m_min:[1],temperature_2m_max:[5],precipitation_sum:[2]}}))).mockResolvedValueOnce(completion({text:'По прогнозу ожидаются осадки.',sourceIds:[],artifact:{kind:'summary',title:'Погода',body:'Прогноз получен',evidence:[{kind:'weather',summary:'Ожидается 2 мм осадков.'}],actions:['open_weather']}}));
  const response=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,message:'Контекст',provider:'deepseek'});expect(response.status).toBe(200);expect((await response.json()).reply.tools).toContain('weather');
  expect(String(f.fetcher.mock.calls[1][0])).toContain('latitude=55');
 });
 it('refreshes actual weather grounding when continuing a weather-backed question',async()=>{
  const f=fixture();const forecast=()=>new Response(JSON.stringify({daily:{time:['2026-10-24'],temperature_2m_min:[1],temperature_2m_max:[5],precipitation_sum:[2]}}));
  f.fetcher.mockResolvedValueOnce(forecast()).mockResolvedValueOnce(completion({text:'Где симптомы?',sourceIds:[],artifact:{...clarification,evidence:[{kind:'weather',summary:'Прогноз получен.'}]}}));
  const first=await (await f.request('/agent/chat',{operationId:randomUUID(),fieldId,observationId:obsId,message:'Учти прогноз',provider:'deepseek'})).json();
  f.fetcher.mockResolvedValueOnce(forecast()).mockResolvedValueOnce(completion({text:'Проверьте участок после осадков.',sourceIds:[],artifact:{kind:'summary',title:'Контекст',body:'Уточните распространение.',evidence:[{kind:'weather',summary:'В актуальном прогнозе 2 мм.'}],actions:['open_weather']}}));
  const response=await f.request('/agent/chat',{operationId:randomUUID(),conversationId:first.conversation.id,fieldId,observationId:obsId,message:question.options[0],provider:'deepseek'});expect(response.status).toBe(200);expect(f.fetcher.mock.calls.filter(([url])=>String(url).includes('open-meteo.com'))).toHaveLength(2);expect(f.repo.apply).not.toHaveBeenCalled();
 });
 it('allows revisit only for the exact approved observation and never approves from chat',async()=>{
  const f=fixture();await f.repo.apply(randomUUID(),'observation.approve',{id:obsId,version:1,confirmed:true});vi.mocked(f.repo.apply).mockClear();
  f.fetcher.mockResolvedValueOnce(completion({text:'Можно записать повторный осмотр.',sourceIds:[],artifact:{kind:'summary',title:'Повторный осмотр',body:'Сохраните новое наблюдение после осмотра.',observationId:obsId,observationVersion:2,actions:['start_revisit']}}));
  const response=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,observationId:obsId,message:'Подтверждаю',provider:'deepseek'});expect(response.status).toBe(200);expect(f.repo.apply).not.toHaveBeenCalled();
 });
 it('rejects a version that changes during model execution',async()=>{
  const f=fixture();let changed=false;f.fetcher.mockImplementation(async()=>{if(!changed){changed=true;await f.repo.apply(randomUUID(),'observation.approve',{id:obsId,version:1,confirmed:true});}return completion({text:'Предложение',sourceIds:[],artifact:{kind:'observation',title:'Осмотр',body:'Проверить',observationId:obsId,observationVersion:1,actions:['review_observation']}})});
  const response=await f.request('/agent/chat',{operationId:randomUUID(),fieldId,observationId:obsId,message:'Осмотр',provider:'deepseek'});expect(response.status).toBe(502);
 });
 it('keeps legacy stored artifacts readable when answering a conversation',async()=>{
  const f=fixture();const id=randomUUID();const reply={id:randomUUID(),text:'Старый ответ',provider:'deepseek',model:'old',sources:[],tools:[],artifact:{kind:'clarification',title:'Старое уточнение',body:'Какие листья?'},requiresConfirmation:false,createdAt:new Date().toISOString()};
  await f.repo.finishAgent(id,{id,fieldId,messages:[{id:reply.id,role:'assistant',text:reply.text,reply,createdAt:reply.createdAt}]} as any,{reply});
  f.fetcher.mockResolvedValueOnce(completion({text:'Спасибо за уточнение.',sourceIds:[]}));expect((await f.request('/agent/chat',{operationId:randomUUID(),conversationId:id,fieldId,observationId:obsId,message:'Нижние',provider:'deepseek'})).status).toBe(200);
 });
});
