import {readFileSync,writeFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
const {session,fieldId,observationId}=JSON.parse(readFileSync('.data/smoke-session.json','utf8'));
const output=[];
for(const provider of ['deepseek','mimo']){
 const start=Date.now();
 const r=await fetch('http://localhost:8787/api/agent/chat',{method:'POST',headers:{Authorization:`Bearer ${session.accessToken}`,'Content-Type':'application/json'},body:JSON.stringify({operationId:randomUUID(),fieldId,observationId,provider,message:'Посмотри историю этого поля и проверенные источники о наблюдении изменений листьев. Что уточнить при повторном осмотре? Используй инструменты. Ничего не подтверждай.'})});
 const d=await r.json();output.push({provider,status:r.status,elapsedMs:Date.now()-start,...(r.ok?{model:d.reply.model,tools:d.reply.tools,sources:d.reply.sources.map(s=>s.id),reply:d.reply.text}:{error:d.error,code:d.code})});
}
writeFileSync('.data/models-result.json',JSON.stringify(output,null,2));console.log(JSON.stringify(output,null,2));

if(output.some(r=>r.status!==200)) process.exitCode=1;
