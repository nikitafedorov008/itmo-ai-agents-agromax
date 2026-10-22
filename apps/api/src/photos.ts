import { createHash } from 'node:crypto';
import type { Photo } from '@agromax/contracts';
import { ApiFailure } from './domain.js';
export class PhotoIdCollision extends Error {}
export interface PhotoStore {
 get(id:string):Promise<Photo|undefined>;
 put(path:string,file:File,metadata:{originalName:string;sha256:string}):Promise<void>;
 info(path:string):Promise<{originalName?:string;mimeType?:string}>;
 download(path:string):Promise<Blob>;
 register(id:string,file:File):Promise<Photo>;
 remove(path:string):Promise<void>;
}
const digest=async(blob:Blob)=>createHash('sha256').update(new Uint8Array(await blob.arrayBuffer())).digest('hex');
// Storage paths are immutable (upsert:false). Custom metadata allows a retry to
// finish registration after a crash between object upload and the SQL RPC.
export async function uploadImmutablePhoto(store:PhotoStore,farmId:string,id:string,file:File):Promise<Photo>{
 const path=`${farmId}/${id}`;const hash=await digest(file);
 const mismatch=()=>new ApiFailure(409,'IDEMPOTENCY_MISMATCH','Этот operationId уже использован для другого фото');
 const compare=async(photo:Photo)=>{if(photo.name!==file.name||photo.mimeType!==file.type||await digest(await store.download(path))!==hash)throw mismatch();return photo;};
 const previous=await store.get(id);if(previous)return compare(previous);
 await store.put(path,file,{originalName:file.name,sha256:hash});
 // Always verify downloaded bytes on an existing object; metadata hashes alone
 // are client-controlled and are not sufficient evidence of equal content.
 const info=await store.info(path);
 if(info.originalName!==file.name||info.mimeType!==file.type||await digest(await store.download(path))!==hash)throw mismatch();
 try{return await store.register(id,file);}catch(error){
  if(error instanceof PhotoIdCollision){
   const winner=await store.get(id);if(winner)return compare(winner);
   // A global UUID collision outside this tenant must never reveal its row.
   // This tenant's unregistered object has no references and can be removed.
   await store.remove(path);
   throw new ApiFailure(404,'NOT_FOUND','Фото не найдено');
  }
  // Do not delete here: another identical request may already be registering
  // the object. Retrying the same id safely resumes this exact object instead.
  throw error;
 }
}
