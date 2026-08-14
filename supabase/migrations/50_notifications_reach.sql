-- =====================================================================
-- 50_notifications_reach.sql — Portée des notifications
--
-- Une seule notification en base pour huit missions publiées.
-- `notify_matching_workers()` exigeait simultanément le métier exactement
-- déclaré ET `lower(ville ouvrier) = lower(ville mission)`.
--
-- La ville est du texte libre saisi des deux côtés : « Lomé » et « Lome »,
-- « Porto Novo » et « Porto novo » ne s'appariaient pas — `lower()` gère la
-- casse, pas les accents. Et le pays n'était pas vérifié du tout.
--
-- On élargit sans rendre absurde : le métier reste obligatoire, c'est le
-- seul critère de pertinence réelle. La ville sert désormais à CLASSER,
-- plus à exclure — un charpentier de Lomé doit voir une mission à Kara et
-- juger lui-même si le déplacement vaut la peine.
--
-- S'ajoutent deux déclencheurs qui n'existaient pas : nouveau message et
-- nouvelle candidature. Sans le second, un client ne savait jamais qu'on
-- avait répondu à sa demande.
--
-- Appliquée en base sous le nom `notifications_reach` (20260806080014).
-- =====================================================================

create extension if not exists unaccent with schema extensions;

create or replace function public.norm_city(p_city text)
returns text language sql immutable parallel safe as $$
  select nullif(regexp_replace(lower(trim(coalesce(p_city, ''))), '\s+', ' ', 'g'), '');
$$;

create or replace function public.same_city(a text, b text)
returns boolean language sql stable set search_path = '' as $$
  select public.norm_city(a) is not null
     and public.norm_city(b) is not null
     and extensions.unaccent(public.norm_city(a))
       = extensions.unaccent(public.norm_city(b));
$$;

grant execute on function public.norm_city(text)      to authenticated;
grant execute on function public.same_city(text,text) to authenticated;

create or replace function public.notify_matching_workers()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare v_trade text;
begin
  select name_fr into v_trade from public.trades where id = new.trade_id;

  insert into public.notifications (profile_id, kind, title, body, payload)
  select wt.worker_id, 'new_job',
         coalesce(v_trade, 'Nouvelle mission') || ' recherché' ||
           case when new.urgency = 'immediate' then ' — URGENT' else '' end,
         new.title || ' · ' || coalesce(new.neighborhood || ', ', '') || new.city,
         jsonb_build_object('job_id', new.id, 'trade_id', new.trade_id,
                            'city', new.city, 'urgency', new.urgency,
                            'same_city', public.same_city(pr.city, new.city))
    from public.worker_trades wt
    join public.worker_profiles wp on wp.profile_id = wt.worker_id
    join public.profiles pr        on pr.id = wt.worker_id
   where wt.trade_id = new.trade_id
     and wp.is_listed
     and wp.availability = 'available'
     and not pr.is_suspended
     and pr.id <> new.client_id
     -- Le pays cadre la portée ; la ville ne l'exclut plus.
     and (new.country_code is null or pr.country_code = new.country_code)
   order by public.same_city(pr.city, new.city) desc,
            wp.rating_avg desc, wp.jobs_completed desc
   limit 50;

  return null;
end;
$function$;

-- Nouveau message → le destinataire. Une seule notification non lue par
-- conversation : dix messages d'affilée ne doivent pas produire dix lignes.
create or replace function public.notify_on_message()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_dest uuid; v_from text;
begin
  select case when c.client_id = new.sender_id then c.worker_id else c.client_id end
    into v_dest from public.conversations c where c.id = new.conversation_id;

  if v_dest is null or v_dest = new.sender_id then return null; end if;

  if exists (select 1 from public.notifications n
              where n.profile_id = v_dest and n.kind = 'message'
                and n.read_at is null
                and n.payload ->> 'conversation_id' = new.conversation_id::text)
  then return null; end if;

  select full_name into v_from from public.profiles where id = new.sender_id;

  insert into public.notifications (profile_id, kind, title, body, payload)
  values (v_dest, 'message',
          coalesce(v_from, 'Quelqu''un') || ' t''a écrit',
          left(new.body, 120),
          jsonb_build_object('conversation_id', new.conversation_id,
                             'sender_id', new.sender_id));
  return null;
end;
$$;

drop trigger if exists messages_notify on public.messages;
create trigger messages_notify after insert on public.messages
  for each row execute function public.notify_on_message();

-- Nouvelle candidature → le client.
create or replace function public.notify_on_application()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_client uuid; v_title text; v_worker text;
begin
  select jr.client_id, jr.title into v_client, v_title
    from public.job_requests jr where jr.id = new.job_id;

  if v_client is null or v_client = new.worker_id then return null; end if;

  select full_name into v_worker from public.profiles where id = new.worker_id;

  insert into public.notifications (profile_id, kind, title, body, payload)
  values (v_client, 'application', 'Nouvelle proposition',
          coalesce(v_worker, 'Un ouvrier') || ' a répondu à « ' ||
            coalesce(v_title, 'ta demande') || ' »',
          jsonb_build_object('job_id', new.job_id, 'application_id', new.id,
                             'worker_id', new.worker_id));
  return null;
end;
$$;

drop trigger if exists job_applications_notify on public.job_applications;
create trigger job_applications_notify after insert on public.job_applications
  for each row execute function public.notify_on_application();
