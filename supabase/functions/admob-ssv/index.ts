// =====================================================================
// admob-ssv — Vérification serveur des publicités récompensées
//
// Sans cette fonction, `AdsService.showRewarded()` attend une validation
// qui n'arrive jamais et rend `null` : aucune récompense n'est accordée.
// C'était volontaire — mieux vaut ne rien donner que d'accorder ce qu'on
// ne peut pas vérifier — mais cela neutralisait le format publicitaire au
// meilleur rendement.
//
// AdMob appelle cette URL en GET après chaque visionnage complet. La
// requête est signée en ECDSA/SHA-256 avec une clé publique que Google
// publie. Vérifier cette signature est le seul moyen de distinguer un
// visionnage réel d'un APK modifié qui s'auto-crédite.
//
// Déploiement :
//   supabase functions deploy admob-ssv --no-verify-jwt
//
// Le drapeau --no-verify-jwt est indispensable : AdMob appelle sans jeton
// utilisateur. La sécurité vient de la signature, pas de l'authentification.
//
// L'URL à déclarer dans AdMob (Paramètres → Vérification côté serveur) :
//   https://<projet>.supabase.co/functions/v1/admob-ssv
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

const VERIFIER_KEYS_URL =
  'https://gstatic.com/admob/reward/verifier-keys.json';

interface VerifierKey {
  keyId: number;
  pem: string;
  base64: string;
}

// Les clés changent rarement. On les garde en mémoire entre deux appels
// à chaud plutôt que de solliciter Google à chaque publicité vue.
let keyCache: { keys: VerifierKey[]; fetchedAt: number } | null = null;
const KEY_TTL_MS = 24 * 60 * 60 * 1000;

async function verifierKeys(): Promise<VerifierKey[]> {
  if (keyCache && Date.now() - keyCache.fetchedAt < KEY_TTL_MS) {
    return keyCache.keys;
  }
  const res = await fetch(VERIFIER_KEYS_URL);
  if (!res.ok) throw new Error(`Clés AdMob indisponibles (${res.status})`);
  const body = await res.json();
  keyCache = { keys: body.keys as VerifierKey[], fetchedAt: Date.now() };
  return keyCache.keys;
}

function base64ToBytes(b64: string): Uint8Array {
  const normalized = b64.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    '=',
  );
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/// Convertit une signature ECDSA DER en format brut r||s.
///
/// Google signe en DER ; l'API Web Crypto n'accepte que le format P1363
/// (deux entiers de 32 octets concaténés). Sans cette conversion, la
/// vérification échoue systématiquement — et l'erreur ne dit rien de la
/// cause, ce qui en fait un piège classique de cette intégration.
function derToP1363(der: Uint8Array): Uint8Array {
  if (der[0] !== 0x30) throw new Error('Signature DER malformée');

  // Longueur de la séquence : forme courte ou longue.
  let i = 2;
  if (der[1] & 0x80) i = 2 + (der[1] & 0x7f);

  if (der[i] !== 0x02) throw new Error('Entier r absent');
  const rLen = der[i + 1];
  let r = der.slice(i + 2, i + 2 + rLen);

  let j = i + 2 + rLen;
  if (der[j] !== 0x02) throw new Error('Entier s absent');
  const sLen = der[j + 1];
  let s = der.slice(j + 2, j + 2 + sLen);

  // DER préfixe d'un 0x00 les entiers dont le bit de poids fort est à 1,
  // pour les garder positifs. P1363 n'en veut pas.
  const trim = (x: Uint8Array) => {
    let k = 0;
    while (k < x.length - 1 && x[k] === 0x00) k++;
    return x.slice(k);
  };
  const pad = (x: Uint8Array) => {
    const out = new Uint8Array(32);
    out.set(x, 32 - x.length);
    return out;
  };

  r = pad(trim(r));
  s = pad(trim(s));

  const out = new Uint8Array(64);
  out.set(r, 0);
  out.set(s, 32);
  return out;
}

async function signatureIsValid(url: URL): Promise<boolean> {
  const raw = url.search.startsWith('?') ? url.search.slice(1) : url.search;

  // Le contenu signé est tout ce qui précède `&signature=`. AdMob garantit
  // que `signature` et `key_id` sont les deux derniers paramètres.
  const cut = raw.indexOf('&signature=');
  if (cut < 0) return false;
  const signedContent = raw.slice(0, cut);

  const signatureB64 = url.searchParams.get('signature');
  const keyId = url.searchParams.get('key_id');
  if (!signatureB64 || !keyId) return false;

  const keys = await verifierKeys();
  const key = keys.find((k) => String(k.keyId) === keyId);
  if (!key) return false;

  const publicKey = await crypto.subtle.importKey(
    'spki',
    base64ToBytes(key.base64),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['verify'],
  );

  let signature: Uint8Array;
  try {
    signature = derToP1363(base64ToBytes(signatureB64));
  } catch {
    return false;
  }

  return await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    publicKey,
    signature,
    new TextEncoder().encode(signedContent),
  );
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // AdMob n'attend qu'un 200. Toute autre réponse déclenche des tentatives
  // répétées, et un corps d'erreur détaillé renseignerait un attaquant sur
  // ce qui a échoué. On reste laconique.
  const ok = () => new Response('OK', { status: 200 });
  const refuse = () => new Response('Invalid', { status: 400 });

  try {
    if (!(await signatureIsValid(url))) return refuse();

    const impressionId = url.searchParams.get('custom_data');
    const transactionId = url.searchParams.get('transaction_id');
    const userId = url.searchParams.get('user_id');
    if (!impressionId || !transactionId) return refuse();

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    );

    const { data: impression, error } = await supabase
      .from('ad_impressions')
      .select('id, profile_id, placement_key, ssv_verified')
      .eq('id', impressionId)
      .maybeSingle();

    if (error || !impression) return refuse();

    // Le user_id transmis à AdMob est l'identifiant du profil : s'il ne
    // correspond pas, la callback ne concerne pas cette impression.
    if (userId && userId !== impression.profile_id) return refuse();

    // Rejeu : la contrainte UNIQUE sur ssv_transaction_id le bloquerait de
    // toute façon, mais autant sortir avant d'écrire.
    if (impression.ssv_verified) return ok();

    const { data: placement } = await supabase
      .from('ad_placements')
      .select('reward_credits')
      .eq('key', impression.placement_key)
      .maybeSingle();

    const credits = placement?.reward_credits ?? 0;

    const { data: updated, error: updateError } = await supabase
      .from('ad_impressions')
      .update({
        ssv_verified: true,
        ssv_transaction_id: transactionId,
        reward_credits: credits,
        ad_network: url.searchParams.get('ad_network'),
      })
      .eq('id', impressionId)
      .eq('ssv_verified', false)
      .select('id');

    // Violation d'unicité = callback déjà traitée. Ce n'est pas une erreur.
    if (updateError) return ok();

    // Aucune ligne modifiée : une callback concurrente est passée entre la
    // lecture de `ssv_verified` plus haut et cette écriture. Le filtre
    // `.eq('ssv_verified', false)` a fait son travail, mais sans ce
    // contrôle du nombre de lignes on continuerait vers adjust_credits et
    // on créditerait deux fois le même visionnage. AdMob réémet ses
    // callbacks, donc le cas se produit.
    if (!updated || updated.length === 0) return ok();

    if (credits > 0) {
      await supabase.rpc('adjust_credits', {
        p_profile_id: impression.profile_id,
        p_amount: credits,
        p_type: 'ad_reward',
        p_reference_type: 'ad_impression',
        p_reference_id: impressionId,
        p_description: 'Récompense publicitaire vérifiée',
      });
    }

    return ok();
  } catch (e) {
    console.error('admob-ssv', e);
    // On répond 200 : un 500 ferait recommencer AdMob en boucle sur une
    // erreur qui ne se résoudra pas d'elle-même.
    return ok();
  }
});
