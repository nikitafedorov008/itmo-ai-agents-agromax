-- Run only on the new cloud project, after migrations + seed.
insert into public.deployment_settings(id,daily_agent_limit) values(true,50)
on conflict(id) do update set daily_agent_limit=excluded.daily_agent_limit;
-- Notifications run in the database even while the free web server sleeps.
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('agromax-notifications','*/5 * * * *','select public.run_scheduler(now());');
