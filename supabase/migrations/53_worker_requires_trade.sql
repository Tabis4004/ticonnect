-- =====================================================================
-- 53_worker_requires_trade.sql — Un métier, sinon aucune visibilité
--
-- `worker_profiles.is_listed` valait `true` par défaut. Un profil créé
-- avant d'avoir choisi un métier apparaissait donc dans l'annuaire —
-- introuvable par la recherche par métier, et invisible pour
-- `notify_matching_workers()`, qui apparie sur `worker_trades`.
--
-- Résultat concret : sept profils sur onze ne pouvaient recevoir aucune
-- notification de mission, sans que rien ne le signale.
--
-- L'écran de configuration exigeait déjà un métier, mais il n'est pas le
-- seul chemin : le profil est créé par `upsertMine()` AVANT `setTrades()`,
-- et bascule aussi depuis « J'ai aussi des besoins ». Entre les deux
-- appels, ou si le second échoue, le profil restait listé et vide.
--
-- La règle appartient donc à la base : `is_listed` n'est plus un champ
-- qu'on pose, c'est une conséquence. Déclarer un métier rend visible ;
-- retirer le dernier fait disparaître.
--
-- Appliquée sous le nom `worker_requires_trade` (20260806113150).
-- =====================================================================

alter table public.worker_profiles alter column is_listed set default false;

comment on column public.worker_profiles.is_listed is
  'Géré automatiquement : vrai si et seulement si au moins un métier est '
  'déclaré dans worker_trades. Ne pas écrire directement.';

create or replace function public.sync_worker_listing()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_worker uuid := coalesce(new.worker_id, old.worker_id);
begin
  update public.worker_profiles wp
     set is_listed = exists (select 1 from public.worker_trades wt
                              where wt.worker_id = v_worker),
         updated_at = now()
   where wp.profile_id = v_worker;
  return null;
end;
$$;

drop trigger if exists worker_trades_sync_listing on public.worker_trades;
create trigger worker_trades_sync_listing
  after insert or delete on public.worker_trades
  for each row execute function public.sync_worker_listing();

-- L'autre sens : un appel PostgREST direct posant `is_listed = true` sur
-- un profil vide.
create or replace function public.enforce_listed_requires_trade()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.is_listed and not exists (select 1 from public.worker_trades wt
                                    where wt.worker_id = new.profile_id)
  then new.is_listed := false; end if;
  return new;
end;
$$;

drop trigger if exists worker_profiles_listed_guard on public.worker_profiles;
create trigger worker_profiles_listed_guard
  before insert or update of is_listed on public.worker_profiles
  for each row execute function public.enforce_listed_requires_trade();

update public.worker_profiles wp
   set is_listed = exists (select 1 from public.worker_trades wt
                            where wt.worker_id = wp.profile_id),
       updated_at = now()
 where wp.is_listed is distinct from exists (
         select 1 from public.worker_trades wt where wt.worker_id = wp.profile_id);
