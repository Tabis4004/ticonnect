-- =====================================================================
-- 44_response_tracking.sql — Mesure de la réactivité des ouvriers
--
-- `worker_profiles.response_rate` existe depuis la migration 01 et n'a
-- jamais été alimenté : NULL pour tout le monde, aucune fonction ne
-- l'écrit. Cette migration le remplit enfin, et ajoute le délai médian de
-- première réponse.
--
-- **Mesurer, pas encore verrouiller.** Rien ici n'empêche quoi que ce
-- soit : ni de se mettre en avant, ni d'apparaître dans la recherche. Avec
-- deux ouvriers et une conversation, un seuil serait du bruit, et gater sur
-- du bruit est pire que ne pas gater. On accumule d'abord la donnée ; le
-- verrou viendra quand il y aura de quoi calibrer.
--
-- C'est la même démarche que `contains_contact` pour la fuite hors
-- plateforme : instrumenter avant de décider.
--
-- Ce qui est mesuré, précisément : le client écrit en premier, l'ouvrier
-- répond — ou non. Une conversation ouverte par l'ouvrier et laissée sans
-- réponse par le client ne compte pas : on ne reproche pas à quelqu'un le
-- silence d'un autre.
-- =====================================================================

alter table public.conversations
  add column if not exists client_first_message_at timestamptz,
  add column if not exists worker_first_reply_at   timestamptz;

comment on column public.conversations.client_first_message_at is
  'Premier message envoyé par le client. Point de départ du délai de réponse.';
comment on column public.conversations.worker_first_reply_at is
  'Première réponse de l''ouvrier APRÈS ce message. NULL = pas encore répondu.';

create index if not exists conversations_response_idx
  on public.conversations (worker_id, client_first_message_at)
  where client_first_message_at is not null;

alter table public.worker_profiles
  add column if not exists response_median_minutes integer,
  add column if not exists response_sample         integer not null default 0;

comment on column public.worker_profiles.response_rate is
  'Part des conversations mûres où l''ouvrier a répondu, en pourcentage.';
comment on column public.worker_profiles.response_median_minutes is
  'Délai médian de première réponse. La médiane, pas la moyenne : une '
  'réponse arrivée trois semaines plus tard ne doit pas détruire le chiffre.';
comment on column public.worker_profiles.response_sample is
  'Nombre de conversations retenues. Sans lui, un taux de 0 %% sur une seule '
  'conversation se lirait comme un taux de 0 %% sur cent.';

-- =====================================================================
-- FENÊTRE DE MATURITÉ
--
-- Une conversation ouverte il y a dix minutes et sans réponse n'est pas un
-- échec : l'ouvrier dort peut-être. Sans ce délai, le taux plongerait à
-- chaque nouveau message et ne voudrait rien dire.
-- =====================================================================
insert into public.app_settings
  (key, value, description, control, label, group_name,
   min_value, max_value, step, suffix, sort_order)
values
  ('response_window_hours', '24'::jsonb,
   'Délai laissé à un ouvrier avant qu''une conversation sans réponse soit '
   'comptée contre lui. En dessous, elle est ignorée — ni succès ni échec.',
   'number', 'Délai avant de compter un silence', 'Réactivité',
   1, 168, 1, 'heures', 50)
on conflict (key) do nothing;

-- =====================================================================
-- AGRÉGATION
--
-- Appelable pour un ouvrier (à chaud, quand il répond) ou pour tous (par
-- tâche planifiée, car une conversation qui franchit la fenêtre de
-- maturité change le dénominateur sans qu'aucun message n'ait été envoyé).
-- =====================================================================
create or replace function public.refresh_response_stats(p_worker uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_window integer;
  v_count  integer;
begin
  v_window := coalesce(
    (public.app_setting('response_window_hours', '24'::jsonb))::text::int, 24);

  with mature as (
    select c.worker_id,
           (c.worker_first_reply_at is not null) as answered,
           case when c.worker_first_reply_at is not null
                then extract(epoch from
                       (c.worker_first_reply_at - c.client_first_message_at)) / 60.0
           end as minutes
      from public.conversations c
     where c.client_first_message_at is not null
       -- Répondue, ou restée muette assez longtemps pour que le silence
       -- signifie quelque chose.
       and (
         c.worker_first_reply_at is not null
         or c.client_first_message_at < now() - make_interval(hours => v_window)
       )
       and (p_worker is null or c.worker_id = p_worker)
  ),
  agg as (
    select worker_id,
           count(*)::int as n,
           round(100.0 * count(*) filter (where answered) / count(*), 2) as rate,
           percentile_cont(0.5) within group (order by minutes)
             filter (where minutes is not null) as median_minutes
      from mature
     group by worker_id
  )
  update public.worker_profiles wp
     set response_rate           = a.rate,
         response_median_minutes = round(a.median_minutes)::int,
         response_sample         = a.n,
         updated_at              = now()
    from agg a
   where wp.profile_id = a.worker_id;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Le téléphone n'a rien à faire ici : ces chiffres se déduisent des
-- messages, ils ne se déclarent pas.
revoke execute on function public.refresh_response_stats(uuid)
  from public, anon, authenticated;

-- =====================================================================
-- DATATION AU FIL DES MESSAGES
-- =====================================================================
create or replace function public.track_response_times()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv record;
begin
  select c.id, c.client_id, c.worker_id,
         c.client_first_message_at, c.worker_first_reply_at
    into v_conv
    from public.conversations c
   where c.id = new.conversation_id;

  if not found then
    return null;
  end if;

  if new.sender_id = v_conv.client_id then
    if v_conv.client_first_message_at is null then
      update public.conversations
         set client_first_message_at = new.created_at
       where id = v_conv.id;
    end if;

  elsif new.sender_id = v_conv.worker_id then
    -- Une réponse ne compte que s'il y avait quelque chose à répondre.
    if v_conv.worker_first_reply_at is null
       and v_conv.client_first_message_at is not null then
      update public.conversations
         set worker_first_reply_at = new.created_at
       where id = v_conv.id;

      perform public.refresh_response_stats(v_conv.worker_id);
    end if;
  end if;

  return null;
end;
$$;

drop trigger if exists messages_track_response on public.messages;
create trigger messages_track_response
  after insert on public.messages
  for each row execute function public.track_response_times();

-- =====================================================================
-- RATTRAPAGE DE L'HISTORIQUE
-- =====================================================================
update public.conversations c
   set client_first_message_at = f.first_at
  from (
    select m.conversation_id, min(m.created_at) as first_at
      from public.messages m
      join public.conversations cc on cc.id = m.conversation_id
     where m.sender_id = cc.client_id
     group by m.conversation_id
  ) f
 where c.id = f.conversation_id
   and c.client_first_message_at is null;

update public.conversations c
   set worker_first_reply_at = f.first_at
  from (
    select m.conversation_id, min(m.created_at) as first_at
      from public.messages m
      join public.conversations cc on cc.id = m.conversation_id
     where m.sender_id = cc.worker_id
       and cc.client_first_message_at is not null
       and m.created_at >= cc.client_first_message_at
     group by m.conversation_id
  ) f
 where c.id = f.conversation_id
   and c.worker_first_reply_at is null;

select public.refresh_response_stats();
