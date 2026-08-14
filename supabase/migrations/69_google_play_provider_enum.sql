-- Migration isolée, et elle doit le rester.
--
-- PostgreSQL refuse d'utiliser une valeur d'énumération dans la
-- transaction qui l'a créée. Toute la suite du socle Play Billing s'appuie
-- sur 'google_play' : la placer ici, seule, est la seule façon de rendre le
-- reste applicable.
alter type public.payment_provider add value if not exists 'google_play';
