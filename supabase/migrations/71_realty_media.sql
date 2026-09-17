-- =====================================================================
-- 71_realty_media.sql — Stockage des images d'annonces, et filigrane
--
-- Deux seaux, et la distinction est le module tout entier :
--
--   listing-previews (public)  l'aperçu léger et flouté, que tout le monde
--                              voit sans rien débloquer.
--   listing-media    (privé)   l'original en pleine définition et le plan.
--                              Jamais servi par URL directe : un seau
--                              public l'est réellement, il suffirait de
--                              deviner le chemin.
--
-- LE FILIGRANE
--
-- Le plan est ce qui se paie, et c'est aussi ce qui se repartage le plus
-- facilement : un acheteur ouvre, capture l'écran, poste dans un groupe
-- WhatsApp, et le revenu s'arrête au premier acheteur. On ne peut pas
-- empêcher la copie — on peut la rendre traçable. Chaque acheteur reçoit
-- donc SA copie, marquée de son pseudo, de son numéro et de la date.
--
-- Il est apposé côté serveur, à l'ouverture. Appliqué dans l'application,
-- il suffirait de lire le fichier brut dans le cache du téléphone.
--
-- Le déclencheur ci-dessous appelle l'Edge Function `listing-watermark`
-- après chaque déblocage — même mécanique que `push_on_notification`.
-- =====================================================================

create extension if not exists pg_net with schema extensions;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('listing-previews', 'listing-previews', true,   400 * 1024,
     array['image/jpeg', 'image/png', 'image/webp']),
  ('listing-media',    'listing-media',    false, 3 * 1024 * 1024,
     array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- Écritures : chacun sous le dossier portant son identifiant, comme pour
-- les autres seaux. Le chemin est `<uid>/<annonce>/<fichier>`.
--
-- Les copies filigranées vivent sous `watermarked/…`, écrit par la clé de
-- service uniquement : « watermarked » n'étant l'identifiant de personne,
-- aucune politique ci-dessous ne l'ouvre.
-- ---------------------------------------------------------------------------
do $$
declare b text;
begin
  foreach b in array array['listing-previews', 'listing-media'] loop
    execute format('drop policy if exists %I on storage.objects', b || '_write_own');
    execute format('drop policy if exists %I on storage.objects', b || '_update_own');
    execute format('drop policy if exists %I on storage.objects', b || '_delete_own');

    execute format($p$
      create policy %I on storage.objects
        for insert to authenticated
        with check (bucket_id = %L
                    and (storage.foldername(name))[1] = auth.uid()::text)
    $p$, b || '_write_own', b);

    execute format($p$
      create policy %I on storage.objects
        for update to authenticated
        using (bucket_id = %L
               and (storage.foldername(name))[1] = auth.uid()::text)
    $p$, b || '_update_own', b);

    execute format($p$
      create policy %I on storage.objects
        for delete to authenticated
        using (bucket_id = %L
               and (storage.foldername(name))[1] = auth.uid()::text)
    $p$, b || '_delete_own', b);
  end loop;
end $$;

-- Aucune politique de lecture sur `listing-media` : le seau est privé et
-- ses objets ne se servent que par URL signée, fabriquée par
-- `listing-file` après vérification du déblocage.

-- ---------------------------------------------------------------------------
-- Pourquoi un filigrane manquant doit se voir
--
-- Sans cette colonne, un échec de fabrication laisserait `watermarked_path`
-- à nul, indistinguable d'une fabrication encore en cours. On a déjà perdu
-- du temps sur exactement ça avec les erreurs de chargement publicitaire.
-- ---------------------------------------------------------------------------
alter table public.listing_unlocks
  add column if not exists watermark_error text;

-- ---------------------------------------------------------------------------
-- Appel de la fabrique
-- ---------------------------------------------------------------------------
insert into public.app_settings (key, value, description, control, label,
                                 group_name, sort_order, is_visible)
values
  ('realty_watermark_url',
   '"https://feawmdvwzrbajuxtuzyf.supabase.co/functions/v1/listing-watermark"'::jsonb,
   'URL de la fabrique de filigranes. Vider pour suspendre la fabrication.',
   null, null, 'Immobilier', 90, false)
on conflict (key) do nothing;

create or replace function public.listing_unlock_watermark()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_url text;
begin
  v_url := (public.app_setting('realty_watermark_url', '""'::jsonb)) #>> '{}';
  if v_url is null or v_url = '' then return null; end if;

  -- Aucun secret partagé, et c'est raisonné : la fabrique ne fait rien
  -- d'autre que poser un filigrane sur une annonce DÉJÀ débloquée, à partir
  -- d'un identifiant de déblocage qui doit exister. Un inconnu qui
  -- appellerait cette URL n'obtient rien qu'il n'ait déjà, et l'opération
  -- est idempotente. Ce qu'il faut protéger, c'est la lecture du fichier —
  -- et elle l'est, par URL signée après vérification.
  -- `net.http_post` et non `extensions.net.http_post` : pg_net installe
  -- toujours ses objets dans le schéma `net`, quel que soit le schéma
  -- demandé à la création de l'extension. Trois composants seraient lus
  -- comme base.schéma.fonction, et Postgres refuse — la référence croisée
  -- entre bases n'existe pas.
  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body    := jsonb_build_object('unlock_id', new.id),
    timeout_milliseconds := 5000);

  return null;
end;
$$;

drop trigger if exists listing_unlocks_watermark on public.listing_unlocks;
create trigger listing_unlocks_watermark
  after insert on public.listing_unlocks
  for each row execute function public.listing_unlock_watermark();

-- ---------------------------------------------------------------------------
-- Ce dont la fabrique a besoin, et rien de plus.
--
-- Elle s'exécute avec la clé de service : lui laisser reconstituer
-- elle-même le chemin du plan et l'identité de l'acheteur l'obligerait à
-- connaître le schéma. Une fonction dédiée garde cette connaissance ici.
-- ---------------------------------------------------------------------------
create or replace function public.watermark_job(p_unlock uuid)
returns table (
  listing_id  uuid,
  buyer_id    uuid,
  plan_path   text,
  buyer_label text,
  already     boolean
)
language sql
stable
security definer
set search_path to 'public'
as $$
  select
    u.listing_id,
    u.buyer_id,
    (select m.storage_path from public.listing_media m
      where m.listing_id = u.listing_id and m.kind = 'plan'
      order by m.sort_order limit 1),
    -- Ce qui sera écrit sur le plan. Le pseudo seul ne dissuade pas ;
    -- le numéro, si — c'est lui qu'on ne veut pas voir circuler avec le
    -- document dans un groupe WhatsApp.
    coalesce('@' || p.username, p.full_name, 'compte ' || left(u.buyer_id::text, 8))
      || coalesce(' - ' || cd.phone, '')
      || ' - ' || to_char(u.created_at, 'DD/MM/YYYY'),
    u.watermarked_path is not null
  from public.listing_unlocks u
  join public.profiles p on p.id = u.buyer_id
  left join public.contact_details cd on cd.profile_id = u.buyer_id
  where u.id = p_unlock;
$$;

revoke all on function public.watermark_job(uuid) from public, anon, authenticated;

create or replace function public.watermark_done(
  p_unlock uuid, p_path text, p_error text default null)
returns void
language sql
security definer
set search_path to 'public'
as $$
  update public.listing_unlocks
     set watermarked_path = coalesce(p_path, watermarked_path),
         watermark_error  = p_error
   where id = p_unlock;
$$;

revoke all on function public.watermark_done(uuid, text, text) from public, anon, authenticated;
