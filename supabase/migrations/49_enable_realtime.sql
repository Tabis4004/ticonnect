-- =====================================================================
-- 49_enable_realtime.sql — Activer la diffusion temps réel
--
-- `ChatService.stream()` utilise `.stream(primaryKey: ['id'])`, qui
-- s'appuie sur la publication PostgreSQL `supabase_realtime`. Cette
-- publication était **vide** : aucune table n'y figurait.
--
-- Symptôme exact : les messages partent bien et sont écrits en base, mais
-- rien ne les pousse vers l'autre appareil. Le destinataire ne les
-- découvre qu'en quittant la conversation et en y revenant, puisque le
-- chargement initial fonctionne, lui.
--
-- Ni l'envoi ni les politiques RLS n'étaient en cause — les deux sont
-- corrects. C'est le canal de diffusion qui n'existait pas. Le genre de
-- panne qui se diagnostique mal parce que tout a l'air de marcher : le
-- message est bien là, simplement pas au bon moment.
--
-- `conversations` suit, pour la liste des discussions et les compteurs de
-- non-lus. `notifications` aussi : une alerte de nouvelle mission n'a
-- d'intérêt que si elle arrive sans qu'on rafraîchisse.
--
-- La RLS continue de s'appliquer au temps réel : un client ne reçoit que
-- les lignes que `messages_select_participant` l'autorise à lire.
-- =====================================================================

alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.conversations;
alter publication supabase_realtime add table public.notifications;
