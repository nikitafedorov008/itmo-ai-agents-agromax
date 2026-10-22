import {randomUUID as uuid} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import assert from 'node:assert/strict';
const base=process.env.API_BASE_URL || 'http://localhost:8787';
mkdirSync('.data',{recursive:true});
async function request(path,body,token){const r=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{...(body instanceof FormData?{}:{'Content-Type':'application/json'}),...(token?{Authorization:`Bearer ${token}`}:{})},body:body===undefined?undefined:body instanceof FormData?body:JSON.stringify(body)});const d=await r.json();if(!r.ok)throw new Error(`${r.status} ${JSON.stringify(d)}`);return d;}
const stamp=Date.now(),email=`design-${stamp}@example.test`,password='AgromaxDesign-2026-test';
const session=await request('/api/auth/signup',{email,password,name:'AGROMAX · учебный пример'});
const field=await request('/api/fields',{operationId:uuid(),confirmed:true,name:'Поле 1 · учебный пример',crop:'Озимая пшеница',areaHa:54,center:{lat:55.75,lng:36.95},boundary:[]},session.accessToken);
const form=new FormData();form.set('operationId',uuid());form.set('file',new File([readFileSync('docs/design/wheat-leaf.png')],'wheat-demo.png',{type:'image/png'}));
const photo=await request('/api/photos',form,session.accessToken);
const observation=await request('/api/observations',{operationId:uuid(),id:uuid(),fieldId:field.id,note:'Учебный осмотр. На нижних листьях озимой пшеницы заметно пожелтение по краю участка. Внутри поля явных изменений не вижу.',extent:'Около 5% участка',photoIds:[photo.id]},session.accessToken);
writeFileSync('.data/workbench-session.json',JSON.stringify({email,password,session,field,observation}),{mode:0o600});
const results=[];
for(const provider of ['deepseek','mimo']){
 const start=Date.now();
 try{
 const first=await request('/api/agent/chat',{operationId:uuid(),fieldId:field.id,observationId:observation.id,provider,message:'Разбери это наблюдение с учётом истории поля и прогноза погоды. Если данных недостаточно, задай один конкретный уточняющий вопрос с вариантами ответа в artifact.question. Покажи источники и доступные действия. Не подтверждай запись.'},session.accessToken);
 assert.ok(first.reply.artifact?.question?.prompt,'Expected actual model clarification question');
 const artifact=first.reply.artifact;assert.ok(artifact.question.options.length>=2||artifact.question.allowCustom);assert.ok(first.reply.tools.includes('field_history'));
 const answer=artifact.question.options[0]||'Сегодня утром; осмотр учебный, дополнительных измерений пока нет.';
 const second=await request('/api/agent/chat',{operationId:uuid(),conversationId:first.conversation.id,fieldId:field.id,observationId:observation.id,provider,message:`Ответ на уточнение «${artifact.question.prompt}»: ${answer}. Продолжи разбор и предложи следующий шаг, ничего не подтверждай.`},session.accessToken);
 assert.equal(second.conversation.id,first.conversation.id);assert.equal(second.conversation.messages.length,4);
 const state=await request('/api/bootstrap',undefined,session.accessToken);assert.equal(state.observations.find(o=>o.id===observation.id).status,'draft');assert.equal(state.tasks.length,0);
 results.push({provider,ok:true,model:first.reply.model,elapsedMs:Date.now()-start,question:artifact.question,actions:artifact.actions,evidence:artifact.evidence,tools:first.reply.tools,secondArtifact:second.reply.artifact?.kind,conversationId:first.conversation.id});
 }catch(e){results.push({provider,ok:false,error:e.message,elapsedMs:Date.now()-start});}
}
writeFileSync('.data/workbench-result.json',JSON.stringify(results,null,2));console.log(JSON.stringify(results,null,2));if(results.some(r=>!r.ok))process.exitCode=1;
