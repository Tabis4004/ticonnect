-- =====================================================================
-- 63_accept_application_guard.sql — L'acceptation revient au client
--
-- `applications_update_involved` autorisait la mise à jour à
-- « worker_id = auth.uid() OR owns_job(job_id) ». L'ouvrier pouvait donc
-- passer sa propre candidature à « accepted » : le déclencheur lui
-- attribuait la mission et rejetait toutes les autres candidatures.
-- Vérifié en production, puis remis en état.
-- =====================================================================
revoke update on public.job_applications from authenticated;
grant  update (message, proposed_price, currency)
  on public.job_applications to authenticated;

create or replace function public.accept_application(p_application_id uuid)
returns public.job_requests
language plpgsql security definer set search_path = ''
as $$
declare v_app public.job_applications; v_job public.job_requests; v_nom text;
begin
  select * into v_app from public.job_applications where id = p_application_id;
  if not found then raise exception 'Candidature introuvable'; end if;

  select * into v_job from public.job_requests where id = v_app.job_id for update;

  if v_job.client_id <> auth.uid() then
    raise exception 'Seul l''auteur de la demande peut accepter une candidature'
      using errcode = '42501';
  end if;

  -- Sans ce verrou, deux acceptations rapprochées laisseraient deux
  -- ouvriers persuadés d'avoir le chantier.
  if v_job.status <> 'open' then
    raise exception 'Cette demande n''est plus ouverte (%)', v_job.status;
  end if;
  if v_app.status = 'withdrawn' then
    raise exception 'Cette candidature a été retirée';
  end if;

  update public.job_applications set status = 'accepted' where id = p_application_id;

  update public.job_requests
     set assigned_worker_id = v_app.worker_id, status = 'assigned'
   where id = v_app.job_id
  returning * into v_job;

  update public.job_applications set status = 'rejected'
   where job_id = v_app.job_id and id <> p_application_id and status = 'pending';

  select p.full_name into v_nom from public.profiles p where p.id = v_job.client_id;

  insert into public.notifications (profile_id, kind, title, body, payload)
  values (v_app.worker_id, 'application_accepted', 'Ta candidature est acceptée',
    coalesce(v_nom, 'Le client') || ' t''a choisi pour « ' || v_job.title || ' »',
    jsonb_build_object('job_id', v_job.id, 'application_id', p_application_id,
                       'client_id', v_job.client_id));
  return v_job;
end;
$$;

revoke execute on function public.accept_application(uuid) from public, anon;
grant  execute on function public.accept_application(uuid) to authenticated;

create or replace function public.withdraw_application(p_application_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_app public.job_applications;
begin
  select * into v_app from public.job_applications where id = p_application_id;
  if not found then raise exception 'Candidature introuvable'; end if;
  if v_app.worker_id <> auth.uid() then
    raise exception 'Cette candidature n''est pas la tienne' using errcode = '42501';
  end if;
  if v_app.status = 'accepted' then
    raise exception 'Une candidature acceptée ne se retire pas : préviens le client';
  end if;
  update public.job_applications set status = 'withdrawn' where id = p_application_id;
end;
$$;

revoke execute on function public.withdraw_application(uuid) from public, anon;
grant  execute on function public.withdraw_application(uuid) to authenticated;
