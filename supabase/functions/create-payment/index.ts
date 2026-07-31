// =====================================================================
// create-payment — Initie un paiement d'abonnement
//
// Cette fonction existe pour une raison simple : les clés secrètes des
// fournisseurs ne doivent jamais atteindre le téléphone. Un APK se
// décompile, et une clé `sk_live_…` extraite d'une application permet de
// créer des transactions au nom du marchand.
//
// Le montant n'est pas non plus transmis par le client : il est relu dans
// `plan_prices` côté serveur. Sans cette précaution, une requête modifiée
// achèterait un abonnement premium annuel pour un franc.
//
// Déploiement :
//   supabase functions deploy create-payment
// (avec vérification du JWT : seul un utilisateur connecté peut payer)
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { initPayment, type Provider } from '../_shared/providers.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Méthode non autorisée' }, 405);

  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader) return json({ error: 'Non authentifié' }, 401);

    // Client « utilisateur » : sert uniquement à savoir qui appelle.
    const asUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false } },
    );

    const { data: userData } = await asUser.auth.getUser();
    const user = userData?.user;
    if (!user) return json({ error: 'Non authentifié' }, 401);

    const body = await req.json();
    const plan = String(body.plan ?? '');
    const period = String(body.billing_period ?? 'monthly');
    const provider = String(body.provider ?? 'geniuspay') as Provider;

    if (!['pro', 'premium'].includes(plan)) {
      return json({ error: 'Plan inconnu' }, 400);
    }
    if (!['monthly', 'annual'].includes(period)) {
      return json({ error: 'Périodicité inconnue' }, 400);
    }
    if (!['fedapay', 'geniuspay'].includes(provider)) {
      return json({ error: 'Fournisseur inconnu' }, 400);
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    );

    const { data: profile } = await admin
      .from('profiles')
      .select('id, full_name, country_code, is_suspended')
      .eq('id', user.id)
      .maybeSingle();

    if (!profile) return json({ error: 'Profil introuvable' }, 404);
    if (profile.is_suspended) return json({ error: 'Compte suspendu' }, 403);

    // Le tarif vient de la base, jamais de la requête.
    const { data: priceRows } = await admin.rpc('plan_price', {
      p_country: profile.country_code,
      p_plan: plan,
      p_period: period,
    });
    const price = Array.isArray(priceRows) ? priceRows[0] : priceRows;
    if (!price?.amount) {
      return json({ error: 'Aucun tarif défini pour ce pays' }, 404);
    }

    const { data: contact } = await admin
      .from('contact_details')
      .select('phone, email')
      .eq('profile_id', user.id)
      .maybeSingle();

    const label = plan === 'premium' ? 'Premium' : 'Pro';
    const periodLabel = period === 'annual' ? 'annuel' : 'mensuel';

    const init = await initPayment({
      provider,
      amount: Number(price.amount),
      currency: String(price.currency),
      description: `TiConnect ${label} — abonnement ${periodLabel}`,
      customerName: profile.full_name,
      customerPhone: contact?.phone ?? null,
      customerEmail: contact?.email ?? null,
      countryCode: profile.country_code,
      successUrl: Deno.env.get('PAYMENT_SUCCESS_URL') ?? null,
      errorUrl: Deno.env.get('PAYMENT_ERROR_URL') ?? null,
      metadata: {
        profile_id: user.id,
        purpose: 'subscription',
        plan,
        billing_period: period,
      },
    });

    // La ligne de paiement n'est écrite qu'une fois la référence connue :
    // `payments` impose l'unicité de (provider, provider_ref), un
    // marqueur temporaire créerait des collisions.
    const { error: insertError } = await admin.from('payments').insert({
      profile_id: user.id,
      provider,
      provider_ref: init.reference,
      amount: Number(price.amount),
      currency: String(price.currency),
      purpose: 'subscription',
      status: 'pending',
      metadata: { plan, billing_period: period },
    });

    if (insertError) {
      console.error('create-payment insert', insertError);
      return json({ error: "Impossible d'enregistrer le paiement" }, 500);
    }

    return json({
      reference: init.reference,
      checkout_url: init.checkoutUrl,
      amount: Number(price.amount),
      currency: String(price.currency),
    });
  } catch (e) {
    console.error('create-payment', e);
    return json({ error: (e as Error).message ?? 'Erreur interne' }, 500);
  }
});
