// =====================================================================
// send-push — Envoie une notification FCM aux appareils d'un profil
//
// Appelée par le trigger `notifications_push` à chaque ligne insérée dans
// `notifications`. C'est le maillon qu'on oublie toujours : enregistrer un
// jeton n'envoie rien, il faut quelque chose qui pousse réellement.
//
// Utilise l'API FCM v1, qui exige un jeton OAuth signé par un compte de
// service — l'ancienne clé serveur héritée est en fin de vie chez Google.
//
// Déploiement :
//   supabase functions deploy send-push --no-verify-jwt
//
// Secret attendu — le JSON complet du compte de service Firebase
// (Console Firebase → Paramètres du projet → Comptes de service →
//  Générer une nouvelle clé privée) :
//   supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
//
// --no-verify-jwt parce que `pg_net` appelle sans jeton utilisateur. La
// fonction se protège autrement : elle exige l'en-tête `x-push-secret`,
// partagé avec la base.
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

// Le jeton OAuth vaut une heure. Le regénérer à chaque notification
// ajouterait un aller-retour Google à chaque message envoyé.
let cachedToken: { value: string; expiresAt: number } | null = null;

function pemToBytes(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === 'string'
    ? new TextEncoder().encode(data)
    : data;
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/// Échange un JWT auto-signé contre un jeton d'accès Google.
async function accessToken(sa: ServiceAccount): Promise<string> {
  if (cachedToken && Date.now() < cachedToken.expiresAt) {
    return cachedToken.value;
  }

  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );

  const assertion = `${header}.${claims}.${b64url(new Uint8Array(signature))}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });

  const body = await res.json();
  if (!res.ok) {
    throw new Error(`OAuth Google : ${body.error_description ?? res.status}`);
  }

  // Une minute de marge : un jeton qui expire pendant l'envoi coûte un
  // échec silencieux.
  cachedToken = {
    value: body.access_token,
    expiresAt: Date.now() + (body.expires_in - 60) * 1000,
  };
  return cachedToken.value;
}

Deno.serve(async (req) => {
  const json = (b: unknown, status = 200) =>
    new Response(JSON.stringify(b), {
      status,
      headers: { 'Content-Type': 'application/json' },
    });

  try {
    // Protection : la fonction est publique pour `pg_net`, mais seul le
    // porteur du secret peut l'utiliser.
    const expected = Deno.env.get('PUSH_SHARED_SECRET');
    if (expected && req.headers.get('x-push-secret') !== expected) {
      return json({ error: 'Non autorisé' }, 401);
    }

    const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    if (!raw) return json({ error: 'FIREBASE_SERVICE_ACCOUNT absent' }, 500);
    const sa = JSON.parse(raw) as ServiceAccount;

    const { profile_id, title, body: message, payload } = await req.json();
    if (!profile_id) return json({ error: 'profile_id manquant' }, 400);

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    );

    const { data: devices } = await admin
      .from('devices')
      .select('fcm_token')
      .eq('profile_id', profile_id);

    if (!devices || devices.length === 0) {
      return json({ sent: 0, note: 'Aucun appareil enregistré' });
    }

    const token = await accessToken(sa);
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    let sent = 0;
    const stale: string[] = [];

    for (const d of devices) {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: d.fcm_token,
            notification: { title, body: message },
            // Les données servent à ouvrir le bon écran au clic. FCM exige
            // des chaînes : tout objet imbriqué doit être sérialisé.
            data: Object.fromEntries(
              Object.entries(payload ?? {}).map(([k, v]) => [k, String(v)]),
            ),
            android: {
              priority: 'high',
              notification: { channel_id: 'ticonnect', sound: 'default' },
            },
          },
        }),
      });

      if (res.ok) {
        sent++;
      } else {
        const err = await res.json().catch(() => ({}));
        const code = err?.error?.details?.[0]?.errorCode ??
          err?.error?.status ?? '';
        // Un jeton révoqué le reste : le garder ferait échouer chaque
        // envoi futur et gonflerait la table indéfiniment.
        if (code === 'UNREGISTERED' || code === 'INVALID_ARGUMENT') {
          stale.push(d.fcm_token);
        }
        console.warn('send-push échec', code, JSON.stringify(err).slice(0, 200));
      }
    }

    if (stale.length > 0) {
      await admin.from('devices').delete().in('fcm_token', stale);
    }

    return json({ sent, removed: stale.length });
  } catch (e) {
    console.error('send-push', e);
    return json({ error: (e as Error).message }, 500);
  }
});
