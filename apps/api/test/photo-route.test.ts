import {describe,it,expect,vi} from 'vitest';
import {randomUUID} from 'node:crypto';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';
import type {Repository} from '../src/repository.js';
const bytes=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aQa0AAAAASUVORK5CYII=','base64');
describe('photo multipart operation id',()=>{
 const make=()=>{const upload=vi.fn(async(id:string,file:File)=>({id,name:file.name,mimeType:file.type,url:'/api/photos/'+id}));const app=createApp(config({}),{authenticate:async()=>({upload}) as unknown as Repository});const post=(id?:string)=>{const form=new FormData();form.set('file',new File([bytes],'field.png',{type:'image/png'}));if(id!==undefined)form.set('operationId',id);return app.request('/api/photos',{method:'POST',headers:{Authorization:'Bearer session'},body:form});};return {post,upload};};
 it('uses the supplied UUID as the immutable photo id',async()=>{const f=make(),id=randomUUID();const r=await f.post(id);expect(r.status).toBe(201);expect((await r.json()).id).toBe(id);expect(f.upload.mock.calls[0][0]).toBe(id);});
 it('retains backward compatibility with a server-generated id',async()=>{const f=make();const r=await f.post();expect(r.status).toBe(201);expect((await r.json()).id).toMatch(/^[\da-f-]{36}$/);});
 it('rejects a malformed id before any storage operation',async()=>{const f=make();expect((await f.post('bad-id')).status).toBe(400);expect(f.upload).not.toHaveBeenCalled();});
});
