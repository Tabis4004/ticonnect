-- =====================================================================
-- 13_payment_enums.sql — Nouvelles valeurs d'énumération
--
-- Isolé dans son propre fichier volontairement. PostgreSQL refuse
-- d'utiliser une valeur d'énumération dans la même transaction que celle
-- qui l'a créée. Les migrations suivantes s'appuient sur `fedapay`,
-- `geniuspay` et le type `billing_period` : ils doivent donc être validés
-- avant. Ne rien ajouter d'autre ici.
-- =====================================================================

-- Fournisseurs retenus après test : FedaPay et GeniusPay.
-- Les valeurs historiques restent en place — une énumération PostgreSQL
-- ne se réduit pas, et d'anciennes lignes de `payments` peuvent les porter.
alter type public.payment_provider add value if not exists 'fedapay';
alter type public.payment_provider add value if not exists 'geniuspay';

-- Périodicité de facturation.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'billing_period') then
    create type public.billing_period as enum ('monthly', 'annual');
  end if;
end
$$;
