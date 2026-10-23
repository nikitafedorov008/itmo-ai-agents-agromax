-- Only explicitly opted-in synthetic farms enter the public demo dashboard.
-- The monitoring schema is not exposed by PostgREST; RPC is service-role only.
create schema if not exists monitoring;
revoke all on schema monitoring from public,anon,authenticated;
create table if not exists monitoring.demo_farms(farm_id uuid primary key references public.farms on delete cascade);
alter table monitoring.demo_farms enable row level security;
revoke all on monitoring.demo_farms from public,anon,authenticated;
alter table public.agent_runs add column if not exists finished_at timestamptz;
create or replace function monitoring.stamp_agent_finish() returns trigger language plpgsql set search_path=pg_catalog as $$
begin
 if new.status in ('completed','failed') and old.status='running' then new.finished_at:=clock_timestamp(); end if;
 return new;
end $$;
revoke all on function monitoring.stamp_agent_finish() from public,anon,authenticated;
create trigger agent_run_finished before update of status on public.agent_runs for each row execute function monitoring.stamp_agent_finish();
create or replace function public.demo_monitoring_snapshot() returns jsonb language sql stable security definer set search_path=pg_catalog as $$
with runs as (
 select r.*,case when r.finished_at is not null then extract(epoch from (r.finished_at-r.created_at))*1000
   when r.status='completed' and r.result#>>'{reply,createdAt}' is not null then extract(epoch from ((r.result#>>'{reply,createdAt}')::timestamptz-r.created_at))*1000 end as duration_ms,
   case when r.finished_at is not null then 'database' when r.status='completed' then 'legacy_reply_timestamp' else 'unknown' end as timing_basis
 from public.agent_runs r join monitoring.demo_farms d on d.farm_id=r.farm_id
 where r.created_at>=now()-interval '30 days'
), obs as (select o.* from public.observations o join monitoring.demo_farms d on d.farm_id=o.farm_id),
 tasks as (select t.* from public.tasks t join monitoring.demo_farms d on d.farm_id=t.farm_id),
 events as (select jsonb_build_object('ref','run-'||substr(md5(r.id::text),1,10),'startedAt',r.created_at,'finishedAt',r.finished_at,'status',r.status,
 'provider',case when r.fingerprint->>'provider' in ('deepseek','mimo') then r.fingerprint->>'provider' else 'unknown' end,
 'model',r.result#>>'{reply,model}','durationMs',round(r.duration_ms::numeric),'timingBasis',r.timing_basis,
 'errorCode',r.error_code,'tools',coalesce(r.result#>'{reply,tools}','[]'::jsonb),
 'sourceCount',jsonb_array_length(coalesce(r.result#>'{reply,sources}','[]'::jsonb)),
 'clarification',coalesce(r.result#>>'{reply,artifact,kind}'='clarification',false)) as event
 from runs r order by r.created_at desc limit 200),
 hours as (select date_trunc('hour',created_at) as hour,count(*) as total,count(*) filter(where status='completed') as completed,count(*) filter(where status='failed') as failed from runs group by 1 order by 1)
select jsonb_build_object('schemaVersion',1,'scope','synthetic-demo-only','snapshotAt',now(),'periodDays',30,
 'summary',jsonb_build_object('runs',(select count(*) from runs),'completed',(select count(*) from runs where status='completed'),
 'failed',(select count(*) from runs where status='failed'),'running',(select count(*) from runs where status='running'),
 'meanMs',(select round(avg(duration_ms)::numeric) from runs where status='completed' and duration_ms>=0),
 'p95Ms',(select round((percentile_cont(.95) within group(order by duration_ms))::numeric) from runs where status='completed' and duration_ms>=0),
 'timedCompleted',(select count(*) from runs where status='completed' and duration_ms>=0),
 'legacyTimed',(select count(*) from runs where status='completed' and timing_basis='legacy_reply_timestamp'),
 'withSources',(select count(*) from runs where status='completed' and jsonb_array_length(coalesce(result#>'{reply,sources}','[]'::jsonb))>0),
 'clarifications',(select count(*) from runs where status='completed' and result#>>'{reply,artifact,kind}'='clarification'),
 'observations',(select count(*) from obs),'approved',(select count(*) from obs where data->>'status'='approved'),
 'openTasks',(select count(*) from tasks where data->>'status'='open'),
 'overdueTasks',(select count(*) from tasks where data->>'status'='open' and (data->>'dueAt')::timestamptz<now()),
 'lastRunAt',(select max(created_at) from runs)),
 'events',coalesce((select jsonb_agg(event) from events),'[]'::jsonb),
 'hourly',coalesce((select jsonb_agg(jsonb_build_object('hour',hour,'runs',total,'completed',completed,'failed',failed)) from hours),'[]'::jsonb));
$$;
revoke all on function public.demo_monitoring_snapshot() from public,anon,authenticated;
grant execute on function public.demo_monitoring_snapshot() to service_role;
