-- =====================================================================
-- 11_free_contact_unlock.sql — La prise de contact devient gratuite
--
-- On ne supprime pas la mécanique de crédits : on met le coût à zéro.
-- `unlock_cost` reste le levier. Repasser une valeur > 0 (globalement via
-- le DEFAULT, ou mission par mission) réactive la monétisation sans toucher
-- au code de l'application ni republier sur le Play Store.
-- =====================================================================

alter table public.job_requests alter column unlock_cost set default 0;
update public.job_requests set unlock_cost = 0 where unlock_cost <> 0;

comment on column public.job_requests.unlock_cost is
  'Crédits nécessaires à l''ouvrier pour accéder au contact du client. '
  '0 = gratuit (réglage actuel). Passer à une valeur > 0 rétablit le paywall.';

-- Le coût nul faisait échouer la fonction : adjust_credits() refuse un
-- mouvement de zéro crédit. On traite ce cas avant toute facturation.
create or replace function public.unlock_contact(
  p_target_profile_id uuid,
  p_job_id            uuid default null,
  p_ad_impression_id  uuid default null
)
returns public.contact_unlocks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me       uuid := auth.uid();
  v_cost     smallint := 0;
  v_method   public.unlock_method;
  v_existing public.contact_unlocks;
  v_result   public.contact_unlocks;
  v_free     smallint;
  v_has_sub  boolean;
begin
  if v_me is null then
    raise exception 'Authentification requise';
  end if;
  if v_me = p_target_profile_id then
    raise exception 'Deverrouillage inutile sur son propre profil';
  end if;

  select * into v_existing
    from public.contact_unlocks
   where unlocker_id = v_me and target_profile_id = p_target_profile_id;
  if found then
    return v_existing;
  end if;

  -- Un client qui consulte un ouvrier : toujours gratuit.
  if p_job_id is null then
    insert into public.contact_unlocks
      (unlocker_id, target_profile_id, job_id, method, credits_spent)
    values (v_me, p_target_profile_id, null, 'free_quota', 0)
    returning * into v_result;
    return v_result;
  end if;

  select unlock_cost into v_cost from public.job_requests where id = p_job_id;
  v_cost := coalesce(v_cost, 0);

  -- Coût nul : gratuit, sans mouvement de crédit ni consommation de quota.
  -- On enregistre quand même la ligne : c'est la mesure des mises en
  -- relation réelles, l'indicateur le plus important du produit.
  if v_cost = 0 then
    insert into public.contact_unlocks
      (unlocker_id, target_profile_id, job_id, method, credits_spent, ad_impression_id)
    values (v_me, p_target_profile_id, p_job_id, 'free_quota', 0, p_ad_impression_id)
    returning * into v_result;
    return v_result;
  end if;

  -- ---- À partir d'ici : cas payant, conservé pour un retour arrière ----
  select exists (
    select 1 from public.subscriptions s
     where s.profile_id = v_me
       and s.status = 'active'
       and s.plan <> 'free'
       and (s.expires_at is null or s.expires_at > now())
  ) into v_has_sub;

  if v_has_sub then
    v_method := 'subscription';
    v_cost := 0;

  elsif p_ad_impression_id is not null then
    perform 1
       from public.ad_impressions ai
      where ai.id = p_ad_impression_id
        and ai.profile_id = v_me
        and ai.ssv_verified
        and not exists (
          select 1 from public.contact_unlocks cu where cu.ad_impression_id = ai.id
        );
    if not found then
      raise exception 'Recompense publicitaire invalide ou deja utilisee';
    end if;
    v_method := 'rewarded_ad';
    v_cost := 0;

  else
    select free_unlocks_left into v_free
      from public.worker_profiles
     where profile_id = v_me
     for update;

    if coalesce(v_free, 0) > 0 then
      update public.worker_profiles
         set free_unlocks_left = free_unlocks_left - 1
       where profile_id = v_me;
      v_method := 'free_quota';
      v_cost := 0;
    else
      perform public.adjust_credits(
        v_me, -v_cost, 'spend_unlock', 'job_request', p_job_id, 'Deverrouillage de contact'
      );
      v_method := 'credits';
    end if;
  end if;

  insert into public.contact_unlocks
    (unlocker_id, target_profile_id, job_id, method, credits_spent, ad_impression_id)
  values
    (v_me, p_target_profile_id, p_job_id, v_method, v_cost, p_ad_impression_id)
  returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.unlock_contact(uuid, uuid, uuid) from public, anon;
grant  execute on function public.unlock_contact(uuid, uuid, uuid) to authenticated;
