-- =====================================================================
-- 52_push_on_notification.sql — Faire sonner le téléphone
--
-- La table `notifications` alimente l'affichage DANS l'application. Elle
-- ne fait rien sonner : un ouvrier qui a fermé l'app ne savait jamais
-- qu'un client lui avait écrit. C'était le manque le plus coûteux de
-- TiConnect — un client sans réponse ne revient pas, et c'est le côté rare
-- de cette marketplace.
--
-- `pg_net` permet à Postgres d'appeler une URL sans bloquer la
-- transaction : l'insertion de la notification n'attend pas Google, et un
-- échec d'envoi ne fait pas échouer le message qui l'a déclenchée.
--
-- Le secret partagé ne vit PAS dans `app_settings` : cette table est
-- lisible par tout le monde depuis la migration 48. Il est posé par
--   alter database postgres set app.push_secret = '…'
-- et lu ici par `current_setting`. Voir docs/push.md.
--
-- Appliquée sous le nom `push_on_notification` (20260806111540).
-- =====================================================================

create extension if not exists pg_net with schema extensions;

insert into public.app_settings (key, value, description, control, label,
                                 group_name, sort_order, is_visible)
values
  ('push_enabled', 'true'::jsonb,
   'Envoi des notifications push. Couper ici arrête les envois sans toucher '
   'aux notifications dans l''application.',
   'switch', 'Notifications push', 'Notifications', 60, true),
  ('push_function_url',
   ('"https://feawmdvwzrbajuxtuzyf.supabase.co/functions/v1/send-push"')::jsonb,
   'URL de l''Edge Function d''envoi.',
   null, null, 'Notifications', 61, false)
on conflict (key) do nothing;

create or replace function public.push_on_notification()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_url text; v_secret text;
begin
  if coalesce((public.app_setting('push_enabled', 'true'::jsonb))::text::boolean, true) = false
  then return null; end if;

  v_url := (public.app_setting('push_function_url', '""'::jsonb)) #>> '{}';
  if v_url is null or v_url = '' then return null; end if;

  v_secret := current_setting('app.push_secret', true);

  perform extensions.net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-push-secret', coalesce(v_secret, '')),
    body    := jsonb_build_object(
                 'profile_id', new.profile_id,
                 'title',      new.title,
                 'body',       new.body,
                 'payload',    coalesce(new.payload, '{}'::jsonb)
                                 || jsonb_build_object('kind', new.kind)),
    timeout_milliseconds := 5000);

  return null;
end;
$$;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push after insert on public.notifications
  for each row execute function public.push_on_notification();
