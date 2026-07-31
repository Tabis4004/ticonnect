-- =====================================================================
-- 17_storage_buckets.sql — Stockage des fichiers
--
-- Quatre usages, trois publics et un privé. La distinction n'est pas
-- cosmétique : `id-documents` contient des pièces d'identité, et un
-- bucket public sur Supabase l'est réellement — n'importe qui devinant
-- l'URL y accède, sans jeton.
--
-- Les photos de réalisations sont le premier signal de confiance cité
-- par toutes les plateformes du secteur. Un profil d'ouvrier sans photo
-- ne se vend pas, quelle que soit la qualité du reste.
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars',      'avatars',      true,  2 * 1024 * 1024,
     array['image/jpeg', 'image/png', 'image/webp']),
  ('portfolio',    'portfolio',    true,  5 * 1024 * 1024,
     array['image/jpeg', 'image/png', 'image/webp']),
  ('job-photos',   'job-photos',   true,  5 * 1024 * 1024,
     array['image/jpeg', 'image/png', 'image/webp']),
  ('id-documents', 'id-documents', false, 8 * 1024 * 1024,
     array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- =====================================================================
-- CONVENTION DE NOMMAGE
--
-- Tout fichier est rangé sous un dossier portant l'identifiant de son
-- propriétaire : `<uid>/<nom-du-fichier>`. Les politiques ci-dessous s'y
-- adossent, ce qui évite une table de correspondance à maintenir.
-- =====================================================================

-- ---------------------------------------------------------- Buckets publics
--
-- Aucune politique SELECT n'est créée sur les buckets publics, et c'est
-- délibéré. Un bucket marqué `public` sert ses objets par URL directe sans
-- passer par la RLS : une politique de lecture n'ajoute rien à l'affichage,
-- mais elle autorise le LIST. N'importe quel client pourrait alors énumérer
-- tous les avatars, portfolios et photos de mission de la plateforme, et en
-- déduire qui est inscrit et sur quels chantiers.
--
-- Seules les écritures sont encadrées : chacun n'écrit que sous le dossier
-- portant son propre identifiant.
do $$
declare
  b text;
begin
  foreach b in array array['avatars', 'portfolio', 'job-photos'] loop
    execute format(
      'drop policy if exists %I on storage.objects', b || '_read_all');

    execute format(
      'drop policy if exists %I on storage.objects', b || '_write_own');
    execute format($p$
      create policy %I on storage.objects
        for insert to authenticated
        with check (
          bucket_id = %L
          and (storage.foldername(name))[1] = (select auth.uid())::text
        )
    $p$, b || '_write_own', b);

    execute format(
      'drop policy if exists %I on storage.objects', b || '_update_own');
    execute format($p$
      create policy %I on storage.objects
        for update to authenticated
        using (
          bucket_id = %L
          and (storage.foldername(name))[1] = (select auth.uid())::text
        )
    $p$, b || '_update_own', b);

    execute format(
      'drop policy if exists %I on storage.objects', b || '_delete_own');
    execute format($p$
      create policy %I on storage.objects
        for delete to authenticated
        using (
          bucket_id = %L
          and (storage.foldername(name))[1] = (select auth.uid())::text
        )
    $p$, b || '_delete_own', b);
  end loop;
end
$$;

-- ------------------------------------------------------- Pièces d'identité
-- Lisibles par leur propriétaire et par un administrateur, personne d'autre.
drop policy if exists id_documents_read_own on storage.objects;
create policy id_documents_read_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'id-documents'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.is_admin()
    )
  );

drop policy if exists id_documents_write_own on storage.objects;
create policy id_documents_write_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'id-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists id_documents_update_own on storage.objects;
create policy id_documents_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'id-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Pas de suppression par l'utilisateur : une pièce justificative retirée
-- juste après validation viderait la vérification de son sens.
drop policy if exists id_documents_delete_admin on storage.objects;
create policy id_documents_delete_admin on storage.objects
  for delete to authenticated
  using (bucket_id = 'id-documents' and public.is_admin());
