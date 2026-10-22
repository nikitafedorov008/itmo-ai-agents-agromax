create extension if not exists postgis with schema extensions;
create table public.farms(id uuid primary key default gen_random_uuid(), name text not null, demo boolean not null default false);
create table public.members(user_id uuid primary key references auth.users on delete cascade, farm_id uuid not null references public.farms on delete cascade, role text not null check(role in ('chief','agronomist')));
create table public.fields(id uuid primary key default gen_random_uuid(), farm_id uuid not null references public.farms on delete cascade, data jsonb not null, boundary extensions.geometry(Polygon,4326));
create table public.observations(id uuid primary key, farm_id uuid not null references public.farms on delete cascade, data jsonb not null);
create table public.tasks(id uuid primary key, farm_id uuid not null references public.farms on delete cascade, data jsonb not null);
create table public.photos(id uuid primary key, farm_id uuid not null references public.farms on delete cascade, path text not null unique, data jsonb not null);
create table public.conversations(id uuid primary key, farm_id uuid not null references public.farms on delete cascade, data jsonb not null);
create table public.notifications(id uuid primary key default gen_random_uuid(), farm_id uuid not null references public.farms on delete cascade, dedupe_key text not null, data jsonb not null, unique(farm_id,dedupe_key));
create function public.notification_identity() returns trigger language plpgsql set search_path=public as $$begin new.data:=new.data||jsonb_build_object('id',new.id);return new;end $$;
create trigger notification_identity before insert on public.notifications for each row execute function public.notification_identity();
create table public.operations(farm_id uuid not null references public.farms on delete cascade, id uuid not null, fingerprint jsonb not null, result jsonb not null, primary key(farm_id,id));
create table public.agent_runs(id uuid primary key default gen_random_uuid(), farm_id uuid not null references public.farms on delete cascade, operation_id uuid not null, fingerprint jsonb not null, status text not null check(status in ('running','completed','failed')), result jsonb, error_code text, created_at timestamptz not null default now(), unique(farm_id,operation_id));
create index agent_runs_farm_created on public.agent_runs(farm_id,created_at);
create table public.sources(id text primary key,title text not null,url text not null,excerpt text not null,version text not null);

create function public.current_farm() returns uuid language sql stable security definer set search_path=public as $$select farm_id from members where user_id=auth.uid()$$;
revoke all on function public.current_farm() from public;
grant execute on function public.current_farm() to authenticated;
alter table public.members enable row level security;
create policy own_membership on public.members for select to authenticated using(user_id=auth.uid());
alter table public.farms enable row level security;
create policy own_farm on public.farms for select to authenticated using(id=public.current_farm());
alter table public.sources enable row level security;
create policy source_read on public.sources for select to authenticated using(true);
do $$declare t text; begin foreach t in array array['fields','observations','tasks','photos','conversations','notifications','operations','agent_runs'] loop
execute format('alter table public.%I enable row level security',t);
execute format('create policy tenant_read on public.%I for select to authenticated using(farm_id=public.current_farm())',t);
end loop; end $$;
-- No client table write policies. All domain writes go through checked RPC transactions.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('field-photos','field-photos',false,10485760,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy private_photo_read on storage.objects for select to authenticated using(bucket_id='field-photos' and (storage.foldername(name))[1]=public.current_farm()::text);
create policy private_photo_insert on storage.objects for insert to authenticated with check(bucket_id='field-photos' and (storage.foldername(name))[1]=public.current_farm()::text);
create policy private_photo_delete on storage.objects for delete to authenticated using(bucket_id='field-photos' and (storage.foldername(name))[1]=public.current_farm()::text);

create function public.initialize_farm(p_name text default 'Моё хозяйство') returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare f farms; u auth.users; fid uuid; loc jsonb; b jsonb; i integer;
begin
if auth.uid() is null then raise exception 'unauthorized'; end if;
perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
select * into f from farms where id=current_farm();
if not found then
select * into u from auth.users where id=auth.uid();
insert into farms(name,demo) values(left(coalesce(nullif(p_name,''),'Моё хозяйство'),120),coalesce(u.is_anonymous,false)) returning * into f;
insert into members(user_id,farm_id,role) values(auth.uid(),f.id,'chief');
if f.demo then
for i in 1..3 loop
fid:=gen_random_uuid(); loc:=jsonb_build_object('lat',55.70+i*0.02,'lng',37.40+i*0.03);
b:=jsonb_build_array(jsonb_build_object('lat',55.695+i*0.02,'lng',37.39+i*0.03),jsonb_build_object('lat',55.705+i*0.02,'lng',37.39+i*0.03),jsonb_build_object('lat',55.705+i*0.02,'lng',37.41+i*0.03),jsonb_build_object('lat',55.695+i*0.02,'lng',37.41+i*0.03));
insert into fields(id,farm_id,data,boundary) values(fid,f.id,jsonb_build_object('id',fid,'name','Демо поле '||i,'crop',case i when 1 then 'Пшеница' when 2 then 'Ячмень' else 'Рапс' end,'areaHa',42+i*12,'center',loc,'boundary',b,'demo',true),ST_SetSRID(ST_MakePolygon(ST_MakeLine(array[ST_MakePoint(37.39+i*.03,55.695+i*.02),ST_MakePoint(37.39+i*.03,55.705+i*.02),ST_MakePoint(37.41+i*.03,55.705+i*.02),ST_MakePoint(37.41+i*.03,55.695+i*.02),ST_MakePoint(37.39+i*.03,55.695+i*.02)])),4326));
end loop;
end if;
end if;
return jsonb_build_object('farm',jsonb_build_object('id',f.id,'name',f.name),'demo',f.demo,'role',(select role from members where user_id=auth.uid()));
end $$;

create function public.apply_operation(p_operation_id uuid,p_type text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare f uuid:=current_farm(); old jsonb; result jsonb; fp jsonb:=jsonb_build_object('type',p_type,'payload',p_payload); rid uuid; v integer; field uuid; task jsonb; role_name text; photo text; geom extensions.geometry; coords jsonb; tstamp text:=to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
if f is null then return jsonb_build_object('error','Нет доступа','code','UNAUTHORIZED','status',401); end if;
perform pg_advisory_xact_lock(hashtextextended(f::text||p_operation_id::text,0));
select o.result,o.fingerprint into result,old from operations o where farm_id=f and id=p_operation_id;
if found then
if old<>fp then return jsonb_build_object('error','operationId уже использован для другого запроса','code','IDEMPOTENCY_MISMATCH','status',409); end if;
return result;
end if;
-- Validate inside the trust boundary too: authenticated callers can invoke RPC directly.
if jsonb_typeof(p_payload)<>'object' or p_operation_id is null then return jsonb_build_object('error','Неверная операция','code','INVALID','status',400); end if;
if p_type='observation.upsert' then
if coalesce(length(trim(p_payload->>'note')),0) not between 1 and 10000 or jsonb_typeof(p_payload->'photoIds') is distinct from 'array' or jsonb_array_length(p_payload->'photoIds')>20 or p_payload->>'fieldId' is null then return jsonb_build_object('error','Неверное наблюдение','code','INVALID','status',400); end if;
if p_payload ? 'location' and (jsonb_typeof(p_payload->'location'->'lat') is distinct from 'number' or jsonb_typeof(p_payload->'location'->'lng') is distinct from 'number' or (p_payload->'location'->>'lat')::numeric not between -90 and 90 or (p_payload->'location'->>'lng')::numeric not between -180 and 180) then return jsonb_build_object('error','Неверная геопозиция','code','INVALID','status',400); end if;
elsif p_type<>'field.create' then
if p_payload->>'id' is null or coalesce((p_payload->>'version')::integer,0)<1 then return jsonb_build_object('error','Нужны id и версия','code','INVALID','status',400); end if;
end if;
if p_type='observation.approve' and p_payload ? 'task' then
if coalesce(length(trim(p_payload->'task'->>'title')),0) not between 1 and 300 or p_payload->'task'->>'dueAt' is null then return jsonb_build_object('error','Неверная задача','code','INVALID','status',400); end if;
perform (p_payload->'task'->>'dueAt')::timestamptz;
end if;
if p_type='task.complete' and coalesce(length(trim(p_payload->>'outcome')),0) not between 1 and 5000 then return jsonb_build_object('error','Нужен результат выполнения','code','INVALID','status',400); end if;
select role into role_name from members where user_id=auth.uid();
rid:=(p_payload->>'id')::uuid;
if p_type='field.create' then
if role_name<>'chief' then return jsonb_build_object('error','Добавление поля доступно руководителю','code','FORBIDDEN','status',403); end if;
if p_payload->'confirmed' is distinct from 'true'::jsonb then return jsonb_build_object('error','Нужно явное подтверждение','code','CONFIRMATION_REQUIRED','status',400); end if;
if coalesce(length(trim(p_payload->>'name')),0) not between 1 and 120 or coalesce(length(trim(p_payload->>'crop')),0) not between 1 and 120 or coalesce((p_payload->>'areaHa')::numeric,0) not between 0.000001 and 1000000 or jsonb_typeof(p_payload->'boundary') is distinct from 'array' then return jsonb_build_object('error','Неверное поле','code','INVALID','status',400); end if;
if jsonb_array_length(p_payload->'boundary')<>0 and jsonb_array_length(p_payload->'boundary') not between 3 and 200 then return jsonb_build_object('error','Нужен контур от 3 до 200 точек','code','INVALID','status',400); end if;
if exists(select 1 from jsonb_array_elements(p_payload->'boundary') p where jsonb_typeof(p->'lat') is distinct from 'number' or jsonb_typeof(p->'lng') is distinct from 'number' or (p->>'lat')::numeric not between -90 and 90 or (p->>'lng')::numeric not between -180 and 180) or jsonb_typeof(p_payload->'center'->'lat') is distinct from 'number' or jsonb_typeof(p_payload->'center'->'lng') is distinct from 'number' or (p_payload->'center'->>'lat')::numeric not between -90 and 90 or (p_payload->'center'->>'lng')::numeric not between -180 and 180 then return jsonb_build_object('error','Неверные координаты','code','INVALID','status',400); end if;
if jsonb_array_length(p_payload->'boundary')>0 then
select jsonb_agg(jsonb_build_array((p->>'lng')::numeric,(p->>'lat')::numeric)) into coords from jsonb_array_elements(p_payload->'boundary') p;
if coords->0<>coords->(jsonb_array_length(coords)-1) then coords:=coords||jsonb_build_array(coords->0); end if;
geom:=extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON(jsonb_build_object('type','Polygon','coordinates',jsonb_build_array(coords))::text),4326);
if not extensions.ST_IsValid(geom) or extensions.ST_IsEmpty(geom) or extensions.ST_Area(geom)<=0 or not extensions.ST_Covers(geom,extensions.ST_SetSRID(extensions.ST_MakePoint((p_payload->'center'->>'lng')::numeric,(p_payload->'center'->>'lat')::numeric),4326)) then return jsonb_build_object('error','Контур должен быть простым и содержать центр','code','INVALID','status',400); end if;
end if;
rid:=gen_random_uuid();
result:=(p_payload-'confirmed')||jsonb_build_object('id',rid,'demo',(select demo from farms where id=f));
insert into fields(id,farm_id,data,boundary) values(rid,f,result,geom);
elsif p_type='observation.upsert' then
field:=(p_payload->>'fieldId')::uuid;
if not exists(select 1 from fields where id=field and farm_id=f) then return jsonb_build_object('error','Поле не найдено','code','NOT_FOUND','status',404); end if;
if rid is null then rid:=gen_random_uuid(); end if;
-- Serialize concurrent creation/update of the same client-generated id.
perform pg_advisory_xact_lock(hashtextextended(rid::text,1));
select data into old from observations where id=rid and farm_id=f for update;
if old is not null then
if old->>'status'='approved' or (p_payload->>'version')::integer is distinct from (old->>'version')::integer then return jsonb_build_object('error','Наблюдение изменилось','code','CONFLICT','status',409,'current',old); end if;
if old->>'fieldId'<>field::text then return jsonb_build_object('error','Нельзя перенести наблюдение','code','INVALID','status',400); end if;
v:=(old->>'version')::integer+1;
else
if exists(select 1 from observations where id=rid) then return jsonb_build_object('error','Наблюдение не найдено','code','NOT_FOUND','status',404); end if;
if p_payload ? 'version' then return jsonb_build_object('error','Наблюдение не найдено','code','NOT_FOUND','status',404); end if;
v:=1;
end if;
if p_payload ? 'parentObservationId' and not exists(select 1 from observations where id=(p_payload->>'parentObservationId')::uuid and farm_id=f and data->>'fieldId'=field::text and data->>'status'='approved') then return jsonb_build_object('error','Исходное наблюдение не найдено','code','NOT_FOUND','status',404); end if;
for photo in select jsonb_array_elements_text(p_payload->'photoIds') loop
if not exists(select 1 from photos where id=photo::uuid and farm_id=f) then return jsonb_build_object('error','Фото не найдено','code','NOT_FOUND','status',404); end if;
end loop;
result:=(p_payload-'version'-'operationId')||jsonb_build_object('id',rid,'version',v,'status','draft','createdAt',coalesce(old->>'createdAt',tstamp));
insert into observations(id,farm_id,data) values(rid,f,result) on conflict(id) do update set data=excluded.data;
-- New observation notification is in the same transaction, never duplicated on retries.
insert into notifications(farm_id,dedupe_key,data) values(f,'observation:'||rid,jsonb_build_object('id',gen_random_uuid(),'title','Новое наблюдение','body',left(result->>'note',180),'fieldId',field,'createdAt',tstamp,'read',false)) on conflict do nothing;
elsif p_type='observation.approve' then
if p_payload->'confirmed' is distinct from 'true'::jsonb then return jsonb_build_object('error','Нужно явное подтверждение','code','CONFIRMATION_REQUIRED','status',400); end if;
if role_name<>'chief' then return jsonb_build_object('error','Утверждение доступно руководителю','code','FORBIDDEN','status',403); end if;
select data into old from observations where id=rid and farm_id=f for update;
if old is null then return jsonb_build_object('error','Наблюдение не найдено','code','NOT_FOUND','status',404); end if;
if (p_payload->>'version')::integer is distinct from (old->>'version')::integer or old->>'status'<>'draft' then return jsonb_build_object('error','Наблюдение изменилось','code','CONFLICT','status',409,'current',old); end if;
old:=old||jsonb_build_object('status','approved','version',(old->>'version')::integer+1,'approvedAt',tstamp);
update observations set data=old where id=rid;
result:=jsonb_build_object('observation',old);
if p_payload ? 'task' then
rid:=gen_random_uuid();
task:=jsonb_build_object('id',rid,'fieldId',old->>'fieldId','observationId',old->>'id','title',p_payload->'task'->>'title','dueAt',p_payload->'task'->>'dueAt','status','open','version',1,'createdAt',tstamp);
insert into tasks(id,farm_id,data) values(rid,f,task);
result:=result||jsonb_build_object('task',task);
end if;
elsif p_type='task.complete' then
if p_payload->'confirmed' is distinct from 'true'::jsonb then return jsonb_build_object('error','Нужно явное подтверждение','code','CONFIRMATION_REQUIRED','status',400); end if;
select data into old from tasks where id=rid and farm_id=f for update;
if old is null then return jsonb_build_object('error','Задача не найдена','code','NOT_FOUND','status',404); end if;
if (p_payload->>'version')::integer is distinct from (old->>'version')::integer or old->>'status'<>'open' then return jsonb_build_object('error','Задача изменилась','code','CONFLICT','status',409,'current',old); end if;
result:=old||jsonb_build_object('status','done','version',(old->>'version')::integer+1,'outcome',p_payload->>'outcome');
update tasks set data=result where id=rid;
else return jsonb_build_object('error','Неизвестная операция','code','INVALID','status',400);
end if;
insert into operations(farm_id,id,fingerprint,result) values(f,p_operation_id,fp,result);
return result;
end $$;

create function public.register_photo(p_id uuid,p_name text,p_mime text) returns jsonb language plpgsql security definer set search_path=public as $$
declare f uuid:=current_farm(); result jsonb;
begin
if f is null then raise exception 'unauthorized'; end if;
if p_mime not in ('image/jpeg','image/png','image/webp') then raise exception 'invalid image type'; end if;
result:=jsonb_build_object('id',p_id,'name',left(p_name,180),'mimeType',p_mime,'url','/api/photos/'||p_id);
insert into photos(id,farm_id,path,data) values(p_id,f,f::text||'/'||p_id,result);
return result;
end $$;
create function public.read_notification(p_id uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin update notifications set data=data||'{"read":true}'::jsonb where id=p_id and farm_id=current_farm() returning data into result; return result; end $$;

create function public.begin_agent(p_operation_id uuid,p_fingerprint jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare f uuid:=current_farm(); r agent_runs; is_demo boolean;
begin
if f is null then raise exception 'unauthorized'; end if;
-- Tenant-wide lock makes rate limit and idempotency checks atomic across workers.
perform pg_advisory_xact_lock(hashtextextended(f::text,2));
select * into r from agent_runs where farm_id=f and operation_id=p_operation_id for update;
if found then
if r.fingerprint<>p_fingerprint then return jsonb_build_object('error','operationId уже использован','code','IDEMPOTENCY_MISMATCH','status',409); end if;
if r.status='completed' then return jsonb_build_object('cached',r.result); end if;
-- A timed out/crashed run is never silently replayed against the provider (billing may have happened).
return jsonb_build_object('error',case r.status when 'failed' then 'Предыдущая попытка завершилась ошибкой. Повторите новым запросом.' else 'Запрос уже выполняется' end,'code',case r.status when 'failed' then coalesce(r.error_code,'AGENT_FAILED') else 'IN_PROGRESS' end,'status',409);
end if;
select demo into is_demo from farms where id=f;
if (select count(*) from agent_runs where farm_id=f and created_at>now()-interval '1 hour')>=(case when is_demo then 12 else 120 end) then return jsonb_build_object('error','Лимит запросов в час','code','RATE_LIMIT','status',429); end if;
insert into agent_runs(farm_id,operation_id,fingerprint,status) values(f,p_operation_id,p_fingerprint,'running');
return jsonb_build_object('started',true);
end $$;
create function public.finish_agent(p_operation_id uuid,p_conversation jsonb,p_result jsonb,p_error text default null) returns void language plpgsql security definer set search_path=public as $$
declare f uuid:=current_farm(); r agent_runs; old jsonb;
begin
select * into r from agent_runs where farm_id=f and operation_id=p_operation_id for update;
if not found or r.status<>'running' then raise exception 'run not running'; end if;
if p_error is not null then update agent_runs set status='failed',error_code=left(p_error,80) where id=r.id; return; end if;
if not exists(select 1 from fields where id=(p_conversation->>'fieldId')::uuid and farm_id=f) then raise exception 'field not found'; end if;
perform pg_advisory_xact_lock(hashtextextended(p_conversation->>'id',3));
select data into old from conversations where id=(p_conversation->>'id')::uuid and farm_id=f for update;
if exists(select 1 from conversations where id=(p_conversation->>'id')::uuid and farm_id<>f) then raise exception 'conversation not found'; end if;
if old is not null and old->>'fieldId'<>p_conversation->>'fieldId' then raise exception 'field mismatch'; end if;
-- Append only this turn to the most recent history, preserving concurrent turns.
p_conversation:=p_conversation||jsonb_build_object('messages',coalesce(old->'messages','[]'::jsonb)||(p_conversation->'messages'));
insert into conversations(id,farm_id,data) values((p_conversation->>'id')::uuid,f,p_conversation) on conflict(id) do update set data=excluded.data;
p_result:=p_result||jsonb_build_object('conversation',p_conversation);
update agent_runs set status='completed',result=p_result where id=r.id;
end $$;

-- Called only by service role inside the server, never exposed by a public HTTP route.
create function public.run_scheduler(p_now timestamptz default now()) returns integer language plpgsql security definer set search_path=public as $$
declare n integer:=0; c integer; stamp text:=to_char(p_now at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'); day text:=to_char(p_now at time zone 'Europe/Moscow','YYYY-MM-DD');
begin
insert into notifications(farm_id,dedupe_key,data)
select farm_id,'overdue:'||id,jsonb_build_object('id',gen_random_uuid(),'title','Просрочена задача','body',data->>'title','fieldId',data->>'fieldId','read',false,'createdAt',stamp) from tasks where data->>'status'='open' and (data->>'dueAt')::timestamptz<p_now on conflict do nothing;
get diagnostics c=row_count; n:=n+c;
-- Daily digest after 08:00 Moscow; a unique tenant/day key survives restarts and multiple runners.
if extract(hour from p_now at time zone 'Europe/Moscow')>=8 then
insert into notifications(farm_id,dedupe_key,data) select f.id,'daily:'||day,jsonb_build_object('id',gen_random_uuid(),'title','Утренний обзор','body','Открытых задач: '||(select count(*) from tasks t where t.farm_id=f.id and t.data->>'status'='open'),'read',false,'createdAt',stamp) from farms f on conflict do nothing;
get diagnostics c=row_count; n:=n+c;
end if;
update agent_runs set status='failed',error_code='RUN_INTERRUPTED' where status='running' and created_at<p_now-interval '5 minutes';
return n;
end $$;

-- Domain RPCs are invoker-authenticated and bypass table writes only after farm checks.
revoke all on all functions in schema public from public,anon;
grant execute on function public.current_farm() to authenticated;
grant execute on function public.initialize_farm(text),public.apply_operation(uuid,text,jsonb),public.register_photo(uuid,text,text),public.read_notification(uuid),public.begin_agent(uuid,jsonb),public.finish_agent(uuid,jsonb,jsonb,text) to authenticated;
revoke all on function public.run_scheduler(timestamptz) from authenticated;
grant execute on function public.run_scheduler(timestamptz) to service_role;
