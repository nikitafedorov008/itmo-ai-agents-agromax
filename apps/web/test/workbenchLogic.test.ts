import test from 'node:test';
import assert from 'node:assert/strict';
import type { Conversation, Observation, AgentReply } from '@agromax/contracts';
import { latestReply, evidenceReads, chatPayload, reviewArtifact } from '../src/workbenchLogic.ts';
const reply = (tools: string[] = [], observationId?: string): AgentReply => ({id:'reply',text:'Ответ',provider:'mimo',model:'model',sources:[],tools,requiresConfirmation:false,createdAt:'2026-10-23',artifact:observationId ? {kind:'clarification',title:'Уточнение',body:'Детали',observationId}:undefined});
test('completed evidence comes only from actual supported reply tools, once per tool',()=>{
 assert.deepEqual(evidenceReads(),[]);
 assert.deepEqual(evidenceReads(reply(['weather','weather','invented','source_search'])).map(r=>r.tool),['weather','source_search']);
});
test('does not display a decision tied to a different observation',()=>{
 const c: Conversation = {id:'c',fieldId:'f',messages:[{id:'m',role:'assistant',text:'Ответ',createdAt:'date',reply:reply([], 'other')}]};
 assert.equal(latestReply(c,{id:'current'} as Observation),undefined);
 assert.equal(latestReply(c,{id:'other'} as Observation)?.id,'reply');
});
test('clarification answers preserve field, conversation, provider and observation request identity',()=>{
 assert.deepEqual(chatPayload('f','c','  Сегодня  ','mimo','o'),{fieldId:'f',conversationId:'c',message:'Сегодня',provider:'mimo',observationId:'o'});
 assert.equal(JSON.stringify(chatPayload('f','c','Сегодня','mimo','o')),JSON.stringify(chatPayload('f','c','Сегодня','mimo','o')));
});

test('version changes keep the historical reply and evidence but remove stale questions and mutation proposals',()=>{
 const original: AgentReply = {...reply(['weather'], 'current'), artifact:{kind:'clarification', title:'Уточнение', body:'Предыдущие выводы', observationId:'current', observationVersion:1, question:{prompt:'Когда?',options:['Сегодня'],allowCustom:true}, proposedTask:{title:'Осмотр',dueAt:'2026-10-24'}, actions:['reply','review_observation','start_revisit','open_weather','view_sources']}};
 const c: Conversation={id:'c',fieldId:'f',messages:[{id:'m',role:'assistant',text:original.text,createdAt:'date',reply:original}]};
 const current=latestReply(c,{id:'current',version:2,status:'approved'} as Observation)!;
 assert.equal(current.text,original.text);
 assert.deepEqual(current.tools,['weather']);
 assert.equal(current.artifact?.body,'Предыдущие выводы');
 assert.equal(current.artifact?.question,undefined);
 assert.equal(current.artifact?.proposedTask,undefined);
 assert.deepEqual(current.artifact?.actions,['reply','open_weather','view_sources']);
 assert.equal(original.artifact?.question?.prompt,'Когда?');
 assert.equal(latestReply(c,{id:'current',version:1} as Observation),original);
});


test('a persisted conversation restores the exact validated task proposal into review after reload',()=>{
 const observation = {id:'current',version:4,status:'draft'} as Observation;
 const proposedTask = {title:'Повторно осмотреть участок у дороги',dueAt:'2026-10-27T08:00:00Z'};
 const persisted: Conversation = JSON.parse(JSON.stringify({id:'history',fieldId:'f',messages:[{id:'m',role:'assistant',text:'Рекомендация',createdAt:'date',reply:{...reply([], 'current'),artifact:{kind:'observation',title:'Осмотр',body:'Проверить признаки',observationId:'current',observationVersion:4,proposedTask}}}]}));
 const selectedArtifact = latestReply(persisted,observation)?.artifact;
 assert.deepEqual(reviewArtifact(selectedArtifact,observation)?.proposedTask,proposedTask);
 assert.equal(reviewArtifact(selectedArtifact,{...observation,version:5}),undefined);
 assert.equal(reviewArtifact(selectedArtifact,{...observation,id:'different'}),undefined);
 assert.equal(reviewArtifact(selectedArtifact,{...observation,status:'approved'}),undefined);
 assert.equal(reviewArtifact({...selectedArtifact!,observationVersion:undefined},observation),undefined);
});
