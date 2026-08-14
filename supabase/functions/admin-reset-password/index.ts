// =====================================================================
// admin-reset-password — Un administrateur fixe le mot de passe d'un compte
//
// Pourquoi une Edge Function et pas une fonction SQL : changer un mot de
// passe passe par l'API d'administration de Supabase Auth, qui exige la
// clé de service. Cette clé donne tous les droits sur le projet. Elle doit
// rester sur le serveur — glissée dans l'application, elle serait lisible
// par quiconque décompresse l'APK ou ouvre le JavaScript de la version web.
//
// L'autorisation n'est pas décidée ici. Elle l'est par
// `admin_prepare_password_reset()`, appelée avec le jeton de l'APPELANT :
// les règles vivent en base, avec le reste, et cette fonction ne peut pas
// les contourner puisqu'elle n'agit qu'après un appel réussi.
//
// Déploiement :
//   supabase functions deploy admin-reset-password
//
// Pas de --no-verify-jwt : seul un utilisateur connecté appelle, et son
// jeton est précisément ce qui permet de savoir qui il est.
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'NOT_AUTHENTICATED' }, 401);

  let profileId: string;
  let password: string;
  try {
    const body = await req.json();
    profileId = String(body.profile_id ?? '');
    password = String(body.password ?? '');
  } catch {
    return json({ error: 'BAD_REQUEST' }, 400);
  }

  if (!profileId) return json({ error: 'BAD_REQUEST' }, 400);

  // Supabase impose six caractères ; on exige davantage. Un mot de passe
  // temporaire circule par SMS ou de vive voix, il est plus exposé qu'un
  // autre — et il ouvre l'accès à des conversations privées.
  if (password.length < 10) return json({ error: 'PASSWORD_TOO_SHORT' }, 400);

  const url = Deno.env.get('SUPABASE_URL')!;

  // Premier client : celui de l'appelant. Son jeton porte son identité,
  // donc `auth.uid()` vaut l'administrateur et les garde-fous SQL
  // s'appliquent réellement. Utiliser la clé de service ici les
  // désactiverait tous d'un coup, sans que rien ne le signale.
  const asCaller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: prepared, error: refus } = await asCaller
    .rpc('admin_prepare_password_reset', { p_target: profileId });

  if (refus) {
    // Le message de la base est repris tel quel : c'est lui qui distingue
    // « tu n'es pas administrateur » de « tu ne peux pas réinitialiser un
    // administrateur ». Une erreur générique ferait chercher au mauvais
    // endroit.
    const code = /FORBIDDEN|RESET_ADMIN/.test(refus.message) ? 403 : 400;
    return json({ error: refus.message }, code);
  }

  // Second client : la clé de service, et seulement pour l'écriture du mot
  // de passe, une fois l'autorisation acquise.
  const asService = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  const { error: echec } = await asService.auth.admin.updateUserById(profileId, {
    password,
  });

  if (echec) {
    // Le marqueur `must_change_password` a été posé par la fonction SQL
    // alors que le mot de passe, lui, n'a pas changé. L'utilisateur devrait
    // en choisir un nouveau sans raison — on remet donc les choses en
    // place avant de rendre l'erreur.
    await asService
      .from('profiles')
      .update({ must_change_password: false })
      .eq('id', profileId);
    return json({ error: echec.message }, 500);
  }

  const cible = Array.isArray(prepared) ? prepared[0] : prepared;
  return json({
    ok: true,
    username: cible?.username ?? null,
    full_name: cible?.full_name ?? null,
  });
});
