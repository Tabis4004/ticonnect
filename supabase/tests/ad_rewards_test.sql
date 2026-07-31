-- =====================================================================
-- ad_rewards_test.sql — Vérifications de la logique de récompense
--
-- À exécuter tel quel dans le SQL Editor de Supabase, après les
-- migrations `column_privileges`, `ad_rewards` et `ad_revenue_reporting`. Le script se termine par un ROLLBACK : il ne
-- laisse aucune trace, ni compte, ni impression, ni boost.
--
-- Pourquoi des tests ici plutôt qu'en Dart : c'est la base qui accorde
-- les récompenses, et le seul endroit du système où une erreur coûte de
-- l'argent — un boost gratuit accordé à qui ne l'a pas gagné vide le
-- modèle publicitaire de sa contrepartie, silencieusement.
--
-- Chaque bloc lève une exception explicite en cas d'échec. Un passage
-- complet affiche « TOUS LES TESTS PASSENT » à la fin.
-- =====================================================================

begin;

-- =====================================================================
-- MISE EN PLACE — deux ouvriers, aucune donnée réelle touchée
-- =====================================================================
create temporary table t_ids (
  label text primary key,
  id    uuid
) on commit drop;

do $$
declare
  v_alice uuid := gen_random_uuid();
  v_bob   uuid := gen_random_uuid();
begin
  -- Le trigger `on_auth_user_created` crée le profil public à partir des
  -- métadonnées : on ne l'insère donc pas nous-mêmes, ce serait un
  -- conflit de clé primaire. Le portefeuille suit par le trigger
  -- `profiles_create_wallet`.
  insert into auth.users (id, email, raw_user_meta_data)
  values
    (v_alice, 'alice.test@ticonnect.invalid',
     '{"full_name":"Alice Test","role":"worker","country_code":"TG"}'::jsonb),
    (v_bob,   'bob.test@ticonnect.invalid',
     '{"full_name":"Bob Test","role":"worker","country_code":"TG"}'::jsonb);

  insert into public.worker_profiles (profile_id)
  values (v_alice), (v_bob);

  insert into t_ids values ('alice', v_alice), ('bob', v_bob);
end
$$;

-- Simule un appel authentifié : `auth.uid()` lit cette configuration.
create or replace function pg_temp.login(p_id uuid)
returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_id::text)::text, true);
$$;

create or replace function pg_temp.new_impression(
  p_owner uuid, p_verified boolean, p_key text default 'boost_profile_rewarded')
returns uuid language sql as $$
  insert into public.ad_impressions
    (profile_id, placement_key, format, ssv_verified, reward_credits)
  values (p_owner, p_key, 'rewarded', p_verified, 0)
  returning id;
$$;

-- =====================================================================
-- TEST 1 — Une impression NON vérifiée n'accorde aucun boost
--
-- C'est le cœur du dispositif : sans la signature de Google, le
-- visionnage n'a pas eu lieu. Un APK modifié qui journalise des
-- impressions à la chaîne ne doit rien obtenir.
-- =====================================================================
do $$
declare
  v_alice uuid := (select id from t_ids where label = 'alice');
  v_imp   uuid;
  v_ok    boolean := false;
begin
  perform pg_temp.login(v_alice);
  v_imp := pg_temp.new_impression(v_alice, false);

  begin
    perform public.grant_boost(v_imp);
  exception when others then
    v_ok := true;
  end;

  if not v_ok then
    raise exception 'ÉCHEC test 1 : un boost a été accordé sans vérification SSV';
  end if;
  raise notice 'OK  test 1 — impression non vérifiée refusée';
end
$$;

-- =====================================================================
-- TEST 2 — On ne peut pas encaisser l'impression d'un autre
-- =====================================================================
do $$
declare
  v_alice uuid := (select id from t_ids where label = 'alice');
  v_bob   uuid := (select id from t_ids where label = 'bob');
  v_imp   uuid;
  v_ok    boolean := false;
begin
  v_imp := pg_temp.new_impression(v_bob, true);   -- appartient à Bob
  perform pg_temp.login(v_alice);                 -- Alice tente sa chance

  begin
    perform public.grant_boost(v_imp);
  exception when others then
    v_ok := true;
  end;

  if not v_ok then
    raise exception 'ÉCHEC test 2 : Alice a encaissé une impression de Bob';
  end if;
  raise notice 'OK  test 2 — impression d''autrui refusée';
end
$$;

-- =====================================================================
-- TEST 3 — Une impression vérifiée accorde bien un boost
-- =====================================================================
do $$
declare
  v_alice uuid := (select id from t_ids where label = 'alice');
  v_imp   uuid;
  v_until timestamptz;
  v_db    timestamptz;
begin
  perform pg_temp.login(v_alice);
  v_imp := pg_temp.new_impression(v_alice, true);

  v_until := public.grant_boost(v_imp);

  if v_until is null or v_until <= now() then
    raise exception 'ÉCHEC test 3 : aucune date de fin de boost valide (%)', v_until;
  end if;

  select boosted_until into v_db
    from public.worker_profiles where profile_id = v_alice;

  if v_db is distinct from v_until then
    raise exception 'ÉCHEC test 3 : boosted_until en base (%) ne correspond pas au retour (%)',
      v_db, v_until;
  end if;

  if (select consumed_at from public.ad_impressions where id = v_imp) is null then
    raise exception 'ÉCHEC test 3 : l''impression n''a pas été marquée consommée';
  end if;

  raise notice 'OK  test 3 — boost accordé jusqu''à %', v_until;
end
$$;

-- =====================================================================
-- TEST 4 — Rejeu impossible
--
-- Le cas le plus tentant pour un client modifié : rappeler grant_boost
-- en boucle avec la même impression déjà vérifiée.
-- =====================================================================
do $$
declare
  v_alice uuid := (select id from t_ids where label = 'alice');
  v_imp   uuid;
  v_ok    boolean := false;
begin
  perform pg_temp.login(v_alice);
  v_imp := pg_temp.new_impression(v_alice, true);
  perform public.grant_boost(v_imp);            -- premier échange, légitime

  begin
    perform public.grant_boost(v_imp);          -- rejeu
  exception when others then
    v_ok := true;
  end;

  if not v_ok then
    raise exception 'ÉCHEC test 4 : la même impression a été encaissée deux fois';
  end if;
  raise notice 'OK  test 4 — rejeu refusé';
end
$$;

-- =====================================================================
-- TEST 5 — Le cumul est borné
--
-- Les visionnages s'additionnent, mais jamais au-delà de
-- `boost_max_hours` : sans plafond, un ouvrier très assidu occuperait
-- les créneaux sponsorisés en permanence.
-- =====================================================================
do $$
declare
  v_bob  uuid := (select id from t_ids where label = 'bob');
  v_max  numeric := coalesce(
    (public.app_setting('boost_max_hours', '24'::jsonb))::text::numeric, 24);
  v_imp  uuid;
  v_until timestamptz;
begin
  perform pg_temp.login(v_bob);

  -- Bien plus de visionnages que le plafond ne peut en absorber.
  for i in 1..12 loop
    v_imp := pg_temp.new_impression(v_bob, true);
    v_until := public.grant_boost(v_imp);
  end loop;

  if v_until > now() + make_interval(hours => v_max::int) + interval '1 minute' then
    raise exception 'ÉCHEC test 5 : le plafond de % h n''est pas respecté (%)',
      v_max, v_until;
  end if;
  raise notice 'OK  test 5 — cumul plafonné à % h (fin : %)', v_max, v_until;
end
$$;

-- =====================================================================
-- TEST 6 — boosted_until n'est plus accessible en écriture directe
--
-- C'est la faille que colmate la migration `column_privileges`. Sans elle, tout ce qui
-- précède ne sert à rien : il suffisait d'un appel PostgREST pour se
-- placer en tête sans regarder la moindre vidéo.
-- =====================================================================
do $$
declare
  v_alice   uuid := (select id from t_ids where label = 'alice');
  v_blocked boolean := false;
  v_state   text;
begin
  perform pg_temp.login(v_alice);
  set local role authenticated;

  begin
    update public.worker_profiles
       set boosted_until = now() + interval '3650 days'
     where profile_id = v_alice;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    -- 42501 = privilège insuffisant. C'est bien le droit colonne qui
    -- refuse, pas un effet de bord de la RLS.
    v_blocked := (v_state = '42501');
  end;

  reset role;

  if not v_blocked then
    raise exception
      'ÉCHEC test 6 : un utilisateur peut encore écrire boosted_until '
      '(sqlstate reçu : %). La migration `column_privileges` est-elle appliquée ?',
      coalesce(v_state, 'aucune erreur');
  end if;
  raise notice 'OK  test 6 — écriture directe de boosted_until refusée';
end
$$;

-- =====================================================================
-- TEST 7 — is_suspended n'est plus accessible non plus
--
-- Même mécanique, autre conséquence : sans ce verrou, un compte banni se
-- réactivait lui-même et le bannissement ne voulait plus rien dire.
-- =====================================================================
do $$
declare
  v_alice   uuid := (select id from t_ids where label = 'alice');
  v_blocked boolean := false;
  v_state   text;
begin
  perform pg_temp.login(v_alice);
  set local role authenticated;

  begin
    update public.profiles set is_suspended = false where id = v_alice;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    v_blocked := (v_state = '42501');
  end;

  reset role;

  if not v_blocked then
    raise exception
      'ÉCHEC test 7 : un utilisateur peut encore écrire is_suspended '
      '(sqlstate reçu : %)', coalesce(v_state, 'aucune erreur');
  end if;
  raise notice 'OK  test 7 — écriture directe de is_suspended refusée';
end
$$;

do $$
begin
  raise notice '=========================================';
  raise notice ' TOUS LES TESTS PASSENT';
  raise notice '=========================================';
end
$$;

-- Rien n'est conservé : ni comptes de test, ni impressions, ni boosts.
rollback;
