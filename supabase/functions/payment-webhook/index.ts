// =====================================================================
// payment-webhook — Confirmation de paiement FedaPay et GeniusPay
//
// C'est ici, et nulle part ailleurs, qu'un abonnement s'active. Le
// téléphone ne peut pas le faire : `activate_subscription()` a son droit
// d'exécution révoqué pour `anon` et `authenticated`, et les tables
// `subscriptions` et `payments` n'acceptent aucune écriture cliente.
// Un APK modifié ne peut donc pas s'offrir de premium.
//
// Un seul point d'entrée pour les deux fournisseurs, distingués par le
// segment d'URL :
//   …/functions/v1/payment-webhook/geniuspay
//   …/functions/v1/payment-webhook/fedapay
//
// Déploiement :
//   supabase functions deploy payment-webhook --no-verify-jwt
//
// --no-verify-jwt est indispensable : les fournisseurs appellent sans
// jeton Supabase. L'authenticité vient de la signature HMAC, vérifiée
// avant toute écriture.
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  type Provider,
  readEvent,
  verifyFedaPay,
  verifyGeniusPay,
} from '../_shared/providers.ts';

Deno.serve(async (req) => {
  // Les deux fournisseurs réessaient tant qu'ils ne reçoivent pas un 2xx —
  // FedaPay jusqu'à dix fois avant de désactiver le webhook. On répond
  // donc 200 sur tout ce qui n'est pas une erreur transitoire, et on
  // journalise le reste.
  const ok = (note?: string) =>
    new Response(JSON.stringify({ received: true, note }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  const refuse = (reason: string) =>
    new Response(JSON.stringify({ error: reason }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });

  try {
    const segments = new URL(req.url).pathname.split('/').filter(Boolean);
    const provider = segments[segments.length - 1] as Provider;
    if (!['fedapay', 'geniuspay'].includes(provider)) {
      return new Response('Fournisseur inconnu', { status: 404 });
    }

    // Le corps brut, jamais l'objet reparsé : la signature porte sur les
    // octets reçus.
    const rawBody = await req.text();

    const check = provider === 'fedapay'
      ? await verifyFedaPay(rawBody, req.headers)
      : await verifyGeniusPay(rawBody, req.headers);

    if (!check.valid) {
      console.warn('payment-webhook signature refusée', provider, check.reason);
      return refuse(check.reason ?? 'Signature invalide');
    }

    const payload = JSON.parse(rawBody) as Record<string, unknown>;
    const event = readEvent(provider, payload);
    if (!event) return ok('Événement ignoré');
    if (!event.succeeded && !event.failed) return ok('Statut intermédiaire');

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    );

    const { data: payment } = await admin
      .from('payments')
      .select('id, profile_id, status, purpose, amount, currency, metadata')
      .eq('provider', provider)
      .eq('provider_ref', event.reference)
      .maybeSingle();

    if (!payment) {
      // Paiement inconnu : très probablement un webhook d'un autre
      // environnement pointant sur la même URL. On ne crée rien.
      console.warn('payment-webhook référence inconnue', event.reference);
      return ok('Référence inconnue');
    }

    // Idempotence : les deux fournisseurs peuvent livrer le même événement
    // plusieurs fois, et FedaPay le fait explicitement en cas de réessai.
    if (payment.status === 'success') return ok('Déjà traité');

    if (event.failed) {
      await admin
        .from('payments')
        .update({ status: 'failed', updated_at: new Date().toISOString() })
        .eq('id', payment.id);
      return ok('Échec enregistré');
    }

    // Le montant reçu doit correspondre à celui attendu. Un écart signale
    // soit une manipulation, soit une erreur de configuration — dans les
    // deux cas, il ne faut rien activer.
    if (event.amount != null && Number(payment.amount) !== Number(event.amount)) {
      console.error(
        'payment-webhook montant divergent',
        payment.id, payment.amount, event.amount,
      );
      await admin
        .from('payments')
        .update({ status: 'failed', updated_at: new Date().toISOString() })
        .eq('id', payment.id);
      return ok('Montant divergent');
    }

    await admin
      .from('payments')
      .update({ status: 'success', updated_at: new Date().toISOString() })
      .eq('id', payment.id);

    const meta = { ...(payment.metadata ?? {}), ...event.metadata } as
      Record<string, string>;

    if (payment.purpose === 'subscription') {
      const plan = meta.plan;
      const period = meta.billing_period ?? 'monthly';
      if (!['pro', 'premium'].includes(plan)) {
        console.error('payment-webhook plan absent', payment.id, meta);
        return ok('Plan absent');
      }

      const { data: profile } = await admin
        .from('profiles')
        .select('country_code')
        .eq('id', payment.profile_id)
        .maybeSingle();

      const { error } = await admin.rpc('activate_subscription', {
        p_profile: payment.profile_id,
        p_plan: plan,
        p_period: period,
        p_amount: Number(payment.amount),
        p_currency: payment.currency,
        p_country: profile?.country_code ?? null,
        p_payment_id: payment.id,
      });

      if (error) {
        console.error('activate_subscription', error);
        // 500 : celle-ci mérite un réessai du fournisseur, le paiement est
        // encaissé mais l'abonnement n'est pas posé.
        return new Response(JSON.stringify({ error: error.message }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      // La notification est un confort : son échec ne doit pas provoquer
      // un réessai du fournisseur sur un abonnement déjà posé.
      const { error: notifyError } = await admin.from('notifications').insert({
        profile_id: payment.profile_id,
        kind: 'subscription',
        title: plan === 'premium'
          ? 'Abonnement Premium activé'
          : 'Abonnement Pro activé',
        body: period === 'annual'
          ? 'Ton abonnement est valable un an. Ton profil est mis en avant dès maintenant.'
          : 'Ton abonnement est valable un mois. Ton profil est mis en avant dès maintenant.',
        payload: { plan, billing_period: period },
      });
      if (notifyError) console.warn('notification abonnement', notifyError);

      return ok('Abonnement activé');
    }

    if (payment.purpose === 'credits') {
      const credits = Number(meta.credits ?? 0);
      if (credits > 0) {
        await admin.rpc('adjust_credits', {
          p_profile_id: payment.profile_id,
          p_amount: credits,
          p_type: 'purchase',
          p_reference_type: 'payment',
          p_reference_id: payment.id,
          p_description: 'Achat de crédits',
        });
      }
      return ok('Crédits accordés');
    }

    return ok('Objet du paiement non traité');
  } catch (e) {
    console.error('payment-webhook', e);
    return new Response(JSON.stringify({ error: 'Erreur interne' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
