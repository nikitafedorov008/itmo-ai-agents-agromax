import { z } from 'zod';
export class ApiFailure extends Error { constructor(public status:number, public code:string, message:string,public current?:unknown){super(message)} }
export const uuid=z.string().uuid();
export const point=z.object({lat:z.number().min(-90).max(90),lng:z.number().min(-180).max(180)}).strict();
export const taskProposal=z.object({title:z.string().trim().min(1).max(300),dueAt:z.string().datetime({offset:true})}).strict();
export const fieldInput=z.object({name:z.string().trim().min(1).max(120),crop:z.string().trim().min(1).max(120),areaHa:z.number().positive().max(1000000),center:point,boundary:z.array(point).max(200).refine(b=>b.length===0||b.length>=3),confirmed:z.literal(true)}).strict();
export const observationInput=z.object({id:uuid.optional(),fieldId:uuid,note:z.string().trim().min(1).max(10000),extent:z.string().max(500).optional(),location:point.optional(),photoIds:z.array(uuid).max(20),parentObservationId:uuid.optional(),version:z.number().int().positive().optional()}).strict();
export const approveInput=z.object({id:uuid,version:z.number().int().positive(),confirmed:z.literal(true),task:taskProposal.optional()}).strict();
export const completeInput=z.object({id:uuid,version:z.number().int().positive(),confirmed:z.literal(true),outcome:z.string().trim().min(1).max(5000)}).strict();
export const chatInput=z.object({operationId:uuid,conversationId:uuid.optional(),fieldId:uuid,message:z.string().trim().min(1).max(8000),provider:z.enum(['deepseek','mimo']).default('deepseek'),observationId:uuid.optional()}).strict();
export const artifactAction=z.enum(['reply','review_observation','start_revisit','open_history','open_weather','view_sources']);
const questionSchema=z.object({
 prompt:z.string().trim().min(1).max(500),
 options:z.array(z.string().trim().min(1).max(160)).max(6),
 allowCustom:z.boolean(),
}).strict().superRefine((question,ctx)=>{
 const normalized=question.options.map(option=>option.toLocaleLowerCase('ru-RU'));
 if(new Set(normalized).size!==normalized.length)ctx.addIssue({code:z.ZodIssueCode.custom,path:['options'],message:'Options must be distinct'});
 if(question.options.length===1||(!question.allowCustom&&question.options.length<2))ctx.addIssue({code:z.ZodIssueCode.custom,path:['options'],message:'Provide 2-6 options or an empty list with allowCustom:true'});
});
export const artifactSchema=z.object({
 kind:z.enum(['clarification','observation','summary']),title:z.string().trim().min(1).max(300),body:z.string().trim().min(1).max(10000),
 observationId:uuid.nullish().transform(v=>v??undefined),observationVersion:z.number().int().positive().nullish().transform(v=>v??undefined),proposedTask:taskProposal.nullish().transform(v=>v??undefined),
 stage:z.enum(['signs','context','decision']).nullish().transform(v=>v??undefined),
 question:questionSchema.nullish().transform(v=>v??undefined),
 evidence:z.array(z.object({kind:z.enum(['observation','history','weather','source']),summary:z.string().trim().min(1).max(500)}).strict()).max(4).nullish().transform(v=>v??undefined),
 actions:z.array(artifactAction).max(6).nullish().transform(v=>v??undefined),
}).strict().superRefine((artifact,ctx)=>{
 if(artifact.kind==='clarification'&&!artifact.question)ctx.addIssue({code:z.ZodIssueCode.custom,path:['question'],message:'Clarification requires a structured question'});
 if(artifact.actions&&new Set(artifact.actions).size!==artifact.actions.length)ctx.addIssue({code:z.ZodIssueCode.custom,path:['actions'],message:'Actions must be distinct'});
 if(artifact.evidence&&new Set(artifact.evidence.map(item=>item.kind)).size!==artifact.evidence.length)ctx.addIssue({code:z.ZodIssueCode.custom,path:['evidence'],message:'Evidence kinds must be distinct'});
});
export const modelReply=z.object({text:z.string().trim().min(1).max(16000),sourceIds:z.array(z.string()).max(10),artifact:artifactSchema.nullish().transform(v=>v??undefined)}).strict();
export function operationPayload(type:string,payload:unknown){const schemas:Record<string,z.ZodTypeAny>={'field.create':fieldInput,'observation.upsert':observationInput,'observation.approve':approveInput,'task.complete':completeInput};const schema=schemas[type];if(!schema)throw new ApiFailure(400,'INVALID','Неизвестный тип операции');return schema.parse(payload)}
export function unwrap<T>(data:any):T {if(data?.error)throw new ApiFailure(data.status||500,data.code||'DATABASE_ERROR',data.error,data.current);return data as T}

export function parseModelReply(content:string){const trimmed=content.trim();const fenced=/^```(?:json)?\s*([\s\S]*?)\s*```$/i.exec(trimmed);return modelReply.parse(JSON.parse(fenced?fenced[1]:trimmed));}
