import { z } from 'zod';
export class ApiFailure extends Error { constructor(public status:number, public code:string, message:string,public current?:unknown){super(message)} }
export const uuid=z.string().uuid();
export const point=z.object({lat:z.number().min(-90).max(90),lng:z.number().min(-180).max(180)}).strict();
export const taskProposal=z.object({title:z.string().trim().min(1).max(300),dueAt:z.string().datetime({offset:true})}).strict();
export const observationInput=z.object({id:uuid.optional(),fieldId:uuid,note:z.string().trim().min(1).max(10000),extent:z.string().max(500).optional(),location:point.optional(),photoIds:z.array(uuid).max(20),parentObservationId:uuid.optional(),version:z.number().int().positive().optional()}).strict();
export const approveInput=z.object({id:uuid,version:z.number().int().positive(),confirmed:z.literal(true),task:taskProposal.optional()}).strict();
export const completeInput=z.object({id:uuid,version:z.number().int().positive(),confirmed:z.literal(true),outcome:z.string().trim().min(1).max(5000)}).strict();
export const chatInput=z.object({operationId:uuid,conversationId:uuid.optional(),fieldId:uuid,message:z.string().trim().min(1).max(8000),provider:z.enum(['deepseek','mimo']).default('deepseek'),observationId:uuid.optional()}).strict();
export const artifactSchema=z.object({kind:z.enum(['clarification','observation','summary']),title:z.string().min(1).max(300),body:z.string().min(1).max(10000),observationId:uuid.optional(),observationVersion:z.number().int().positive().optional(),proposedTask:taskProposal.optional()}).strict();
export const modelReply=z.object({text:z.string().trim().min(1).max(16000),sourceIds:z.array(z.string()).max(10),artifact:artifactSchema.optional()}).strict();
export function operationPayload(type:string,payload:unknown){const schemas:Record<string,z.ZodTypeAny>={'observation.upsert':observationInput,'observation.approve':approveInput,'task.complete':completeInput};const schema=schemas[type];if(!schema)throw new ApiFailure(400,'INVALID','Неизвестный тип операции');return schema.parse(payload)}
export function unwrap<T>(data:any):T {if(data?.error)throw new ApiFailure(data.status||500,data.code||'DATABASE_ERROR',data.error,data.current);return data as T}
