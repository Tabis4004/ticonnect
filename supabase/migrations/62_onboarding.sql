-- =====================================================================
-- 62_onboarding.sql — Visite guidée de première connexion
--
-- Le contenu vit en base, comme les réglages et les emplacements : une
-- faute de frappe dans un écran d'accueil ne doit pas coûter un cycle de
-- publication sur le Play Store.
--
-- L'audience filtre par rôle : un client n'a que faire d'apprendre à
-- candidater. Le rôle `both` reçoit les deux parcours.
-- =====================================================================
create table if not exists public.onboarding_steps (
  id         smallserial primary key,
  audience   text not null default 'both'
             check (audience in ('client', 'worker', 'both')),
  sort_order smallint not null default 0,
  icon       text,
  title      text not null,
  body       text not null,
  is_active  boolean not null default true,
  updated_at timestamptz not null default now()
);

comment on column public.onboarding_steps.body is
  'Peut contenir {boost_hours}, remplacé à la lecture par la valeur '
  'courante de app_settings — pour qu''une durée modifiée en base ne '
  'contredise pas ce qu''annonce l''écran d''accueil.';

alter table public.onboarding_steps enable row level security;

drop policy if exists onboarding_steps_read on public.onboarding_steps;
create policy onboarding_steps_read on public.onboarding_steps
  for select to authenticated using (is_active);

drop policy if exists onboarding_steps_admin on public.onboarding_steps;
create policy onboarding_steps_admin on public.onboarding_steps
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Une date plutôt qu'un booléen : savoir *quand* permettra de rejouer la
-- visite après une refonte, en comparant à une date de version.
alter table public.profiles
  add column if not exists onboarding_seen_at timestamptz;

create or replace function public.mark_onboarding_seen()
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  update public.profiles set onboarding_seen_at = now()
   where id = auth.uid() and onboarding_seen_at is null;
end;
$$;

revoke execute on function public.mark_onboarding_seen() from public, anon;
grant  execute on function public.mark_onboarding_seen() to authenticated;

create or replace function public.onboarding_for_me()
returns table (sort_order smallint, icon text, title text, body text)
language plpgsql stable security definer set search_path = ''
as $$
declare v_role text; v_hours text;
begin
  select p.role::text into v_role from public.profiles p where p.id = auth.uid();
  v_role := coalesce(v_role, 'client');
  v_hours := coalesce((public.app_setting('boost_duration_hours', '6'::jsonb))::text, '6');

  return query
  select s.sort_order, s.icon, s.title, replace(s.body, '{boost_hours}', v_hours)
    from public.onboarding_steps s
   where s.is_active
     and (s.audience = 'both' or v_role = 'both' or s.audience = v_role)
   order by s.sort_order, s.id;
end;
$$;

revoke execute on function public.onboarding_for_me() from public, anon;
grant  execute on function public.onboarding_for_me() to authenticated;

insert into public.onboarding_steps (audience, sort_order, icon, title, body) values
  ('client', 10, 'post_add', 'Publiez votre besoin',
   'Décrivez le chantier, la ville et le quartier, un budget indicatif et le degré d''urgence. '
   'Votre demande apparaît aussitôt dans le fil des ouvriers du métier concerné.'),
  ('client', 20, 'assignment_turned_in', 'Comparez les candidatures',
   'Les ouvriers intéressés se manifestent avec un message et un prix. Vous voyez leur profil, '
   'leur note et leurs avis au même endroit, et vous ouvrez la conversation d''un geste.'),
  ('client', 30, 'phone_in_talk', 'Le contact est gratuit',
   'Numéro de téléphone, WhatsApp ou messagerie interne : à vous de choisir. '
   'Aucun abonnement, aucune commission sur le travail réalisé.'),
  ('worker', 40, 'work_outline', 'Les missions près de chez vous',
   'L''onglet Missions rassemble les demandes publiées. Complétez vos métiers et votre zone '
   'pour ne voir que ce qui vous concerne.'),
  ('worker', 50, 'forum_outlined', 'Candidatez, puis discutez',
   'Un message, un prix proposé, et la conversation démarre avec le client. '
   'Répondez vite : votre réactivité s''affiche sur votre profil.'),
  ('worker', 60, 'rocket_launch', 'Passez en tête',
   'Regardez une courte vidéo et votre profil remonte dans les résultats de recherche pendant '
   '{boost_hours} heures. C''est gratuit, et c''est ce qui vous fait trouver avant les autres. '
   'La note compte aussi : une position mise en avant reste réservée aux profils bien notés.'),
  ('both', 90, 'favorite_outline', 'Ticonnect vit grâce à vous',
   'L''application est gratuite pour les clients comme pour les ouvriers, et le restera. '
   'Soutenez-nous en regardant les annonces jusqu''au bout : elles financent l''hébergement '
   'et la maintenance. Rien d''autre ne vous sera jamais demandé.')
on conflict do nothing;
