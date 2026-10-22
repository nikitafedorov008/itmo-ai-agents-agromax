-- DESTRUCTIVE developer rollback. Back up first; never invoked by app.
-- Removes AGROMAX tenant records and photos; keeps auth.users so they can reinitialize.
drop policy if exists private_photo_read on storage.objects;
drop policy if exists private_photo_insert on storage.objects;
drop policy if exists private_photo_delete on storage.objects;
drop function if exists public.run_scheduler(timestamptz);
drop function if exists public.finish_agent(uuid,jsonb,jsonb,text);
drop function if exists public.begin_agent(uuid,jsonb);
drop function if exists public.read_notification(uuid);
drop function if exists public.register_photo(uuid,text,text);
drop function if exists public.apply_operation(uuid,text,jsonb);
drop function if exists public.initialize_farm(text);
drop table if exists public.agent_runs,public.operations,public.notifications,public.conversations,public.photos,public.tasks,public.observations,public.fields,public.sources cascade;
drop table if exists public.members cascade;
drop table if exists public.farms cascade;
drop function if exists public.current_farm();
-- Remove bucket objects using Storage API before deleting the bucket itself.
