-- =====================================================================
-- 65_job_alert_scope.sql — Portée des alertes de nouvelle demande
--
-- L'appariement exigeait le métier exact. Sur sept demandes récentes,
-- cinq n'ont atteint personne : aucun ouvrier n'avait déclaré Jardinier,
-- Plombier, Ménage ou Veilleur de nuit. Une marketplace qui ne prévient
-- personne ne peut pas être réactive.
--
-- La portée devient un réglage, parce que le bon choix change avec la
-- taille : `country` tant que l'annuaire est mince, `category` ensuite,
-- `trade` quand chaque métier compte assez d'ouvriers — sans quoi on
-- transforme l'alerte en spam et les ouvriers coupent les notifications,
-- définitivement.
-- =====================================================================
insert into public.app_settings (key, value, description, control, label, group_name, choices)
values
  ('job_alert_scope', '"country"'::jsonb,
   'Qui est prévenu à la publication d''une demande.',
   'choice', 'Portée des alertes', 'Notifications',
   '[{"value":"trade","label":"Métier exact"},
     {"value":"category","label":"Même catégorie"},
     {"value":"country","label":"Tout le pays"}]'::jsonb),
  ('job_alert_max_recipients', '200'::jsonb,
   'Nombre maximum d''ouvriers prévenus par demande.',
   'number', 'Destinataires par demande', 'Notifications', null)
on conflict (key) do nothing;

create or replace function public.notify_matching_workers()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_trade text; v_category smallint; v_scope text; v_max integer;
begin
  select t.name_fr, t.category_id into v_trade, v_category
    from public.trades t where t.id = new.trade_id;

  v_scope := coalesce((public.app_setting('job_alert_scope', '"country"'::jsonb)) #>> '{}', 'country');
  v_max := coalesce((public.app_setting('job_alert_max_recipients', '200'::jsonb))::text::int, 200);

  insert into public.notifications (profile_id, kind, title, body, payload)
  select wt.worker_id, 'new_job',
         coalesce(v_trade, 'Nouvelle mission') || ' recherché' ||
           case when new.urgency = 'immediate' then ' — URGENT' else '' end,
         new.title || ' · ' || coalesce(new.neighborhood || ', ', '') || new.city,
         jsonb_build_object(
           'job_id', new.id, 'trade_id', new.trade_id, 'city', new.city,
           'urgency', new.urgency, 'same_city', public.same_city(pr.city, new.city),
           -- L'ouvrier saura si l'alerte relève de son métier ou d'un
           -- élargissement : sans cette nuance, une alerte hors métier
           -- passe pour une erreur et use la confiance.
           'exact_trade', exists (select 1 from public.worker_trades w2
                                   where w2.worker_id = wt.worker_id and w2.trade_id = new.trade_id))
    from (
      -- Dédoublonnage : un ouvrier déclarant plusieurs métiers de la même
      -- catégorie recevrait autant d'alertes que de métiers partagés.
      select distinct on (wt0.worker_id) wt0.worker_id, wt0.trade_id
        from public.worker_trades wt0
       order by wt0.worker_id, (wt0.trade_id = new.trade_id) desc
    ) wt
    join public.worker_profiles wp on wp.profile_id = wt.worker_id
    join public.profiles pr        on pr.id = wt.worker_id
   where wp.is_listed and wp.availability = 'available'
     and not pr.is_suspended and pr.id <> new.client_id
     and (new.country_code is null or pr.country_code = new.country_code)
     and (v_scope = 'country'
          or (v_scope = 'category' and exists (
                select 1 from public.worker_trades w3
                  join public.trades t3 on t3.id = w3.trade_id
                 where w3.worker_id = wt.worker_id and t3.category_id = v_category))
          or (v_scope = 'trade' and exists (
                select 1 from public.worker_trades w4
                 where w4.worker_id = wt.worker_id and w4.trade_id = new.trade_id)))
   order by
     exists (select 1 from public.worker_trades w5
              where w5.worker_id = wt.worker_id and w5.trade_id = new.trade_id) desc,
     exists (select 1 from public.worker_trades w6
               join public.trades t6 on t6.id = w6.trade_id
              where w6.worker_id = wt.worker_id and t6.category_id = v_category) desc,
     public.same_city(pr.city, new.city) desc,
     wp.rating_avg desc, wp.jobs_completed desc
   limit v_max;
  return null;
end;
$$;
