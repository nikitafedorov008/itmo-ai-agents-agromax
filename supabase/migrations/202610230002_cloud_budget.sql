-- No local behavior change until the cloud operator configures a limit.
create table public.deployment_settings(id boolean primary key default true check(id), daily_agent_limit integer check(daily_agent_limit between 1 and 10000));
alter table public.deployment_settings enable row level security;
revoke all on public.deployment_settings from anon,authenticated;
grant all on public.deployment_settings to service_role;
create index agent_runs_created on public.agent_runs(created_at);
create or replace function public.begin_agent(p_operation_id uuid,p_fingerprint jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare f uuid:=current_farm(); r agent_runs; is_demo boolean; daily_limit integer;
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
-- Global quota is configured only by the service role for public hosting.
select daily_agent_limit into daily_limit from public.deployment_settings where id=true;
if daily_limit is not null then
perform pg_advisory_xact_lock(hashtextextended('agromax-global-budget',6));
if (select count(*) from agent_runs where created_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')) >= daily_limit then
return jsonb_build_object('error','Дневной лимит облачного ИИ исчерпан. Данные и задачи остаются доступны.','code','RATE_LIMIT','status',429);
end if;
end if;
select demo into is_demo from farms where id=f;
if (select count(*) from agent_runs where farm_id=f and created_at>now()-interval '1 hour')>=(case when is_demo then 12 else 120 end) then return jsonb_build_object('error','Лимит запросов в час','code','RATE_LIMIT','status',429); end if;
insert into agent_runs(farm_id,operation_id,fingerprint,status) values(f,p_operation_id,p_fingerprint,'running');
return jsonb_build_object('started',true);
end $$;
revoke all on function public.begin_agent(uuid,jsonb) from public,anon;
grant execute on function public.begin_agent(uuid,jsonb) to authenticated;
