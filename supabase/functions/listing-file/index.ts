// =====================================================================
// listing-file — Délivre les images fermées d'une annonce, en URL signée
//
// Le seau `listing-media` est privé et n'a aucune politique de lecture :
// ses objets ne sortent que par une URL signée, valable quelques minutes,
// fabriquée ici après vérification du déblocage.
//
// La vérification n'est pas faite dans ce fichier : `listing_private()` est
// appelée avec le jeton de l'APPELANT et lève `LOCKED` si rien n'a été
// débloqué. La règle reste en base, avec le reste. Cette fonction ne fait
// que signer ce que la base a déjà autorisé.
//
// Le plan rendu est TOUJOURS la copie filigranée au nom de l'acheteur,
// jamais l'original. Tant qu'elle n'est pas fabriquée, on le dit plutôt
// que de servir l'original « en attendant » — ce serait la seule copie
// non traçable du document, et elle circulerait.
//
// Déploiement : supabase functions deploy listing-file
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

// Court : l'URL finit dans le cache du navigateur et dans l'historique de
// la Webview. Dix minutes suffisent à regarder un plan, pas à le partager.
const DUREE_SECONDES = 600;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'NOT_AUTHENTICATED' }, 401);

  let listingId = '';
  try {
    listingId = String((await req.json()).listing_id ?? '');
  } catch {
    return json({ error: 'BAD_REQUEST' }, 400);
  }
  if (!listingId) return json({ error: 'BAD_REQUEST' }, 400);

  const url = Deno.env.get('SUPABASE_URL')!;

  const asCaller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: rows, error: refus } = await asCaller
    .rpc('listing_private', { p_listing: listingId });
  if (refus) {
    return json({ error: refus.message },
                /LOCKED/.test(refus.message) ? 403 : 400);
  }

  const prive = Array.isArray(rows) ? rows[0] : rows;
  if (!prive) return json({ error: 'LISTING_UNKNOWN' }, 404);

  const asService = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  const signer = async (path: string | null) => {
    if (!path) return null;
    const { data } = await asService.storage
      .from('listing-media').createSignedUrl(path, DUREE_SECONDES);
    return data?.signedUrl ?? null;
  };

  // Les photos en pleine définition : leur chemin est dans une colonne que
  // le client n'a pas le droit de lire, on le relit donc ici.
  const { data: medias } = await asService
    .from('listing_media')
    .select('kind, storage_path, sort_order')
    .eq('listing_id', listingId)
    .eq('kind', 'photo')
    .order('sort_order');

  const photos: string[] = [];
  for (const m of medias ?? []) {
    const signed = await signer(m.storage_path as string);
    if (signed) photos.push(signed);
  }

  return json({
    plan: await signer(prive.watermarked_path ?? null),
    // Un plan existe mais son filigrane n'est pas encore prêt. L'écran doit
    // dire « en préparation », pas « aucun plan » : les deux se corrigent
    // très différemment.
    plan_en_preparation: !!prive.plan_path && !prive.watermarked_path,
    photos,
    expire_dans: DUREE_SECONDES,
  });
});
