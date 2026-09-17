// =====================================================================
// listing-watermark — Fabrique la copie du plan marquée au nom de l'acheteur
//
// Appelée par le déclencheur `listing_unlocks_watermark` après chaque
// déblocage. Elle lit le plan original dans le seau privé, y inscrit le
// pseudo, le numéro et la date de l'acheteur, et range le résultat sous
// `watermarked/<annonce>/<acheteur>.jpg`.
//
// POURQUOI PAS DE SECRET PARTAGÉ
//
// Elle n'agit que sur un déblocage DÉJÀ acquis, désigné par un identifiant
// qui doit exister, et elle est idempotente. Un inconnu qui appellerait
// cette URL n'obtiendrait rien qu'il n'ait déjà — le fichier produit n'est
// lisible que par URL signée, délivrée après vérification par
// `listing-file`. Ajouter un secret ici protégerait du bruit, pas d'une
// fuite.
//
// LA FONTE EST DANS LE FICHIER
//
// Dessiner du texte suppose une fonte. La télécharger à chaque démarrage à
// froid ajouterait une dépendance réseau à une opération qui doit être
// sûre ; l'embarquer en TTF pèserait plus que tout le reste du module. On
// embarque donc une fonte matricielle 5×7, quarante-cinq signes : majuscules,
// chiffres et la ponctuation d'un numéro de téléphone. Le filigrane n'a
// besoin de rien d'autre.
//
// Déploiement : supabase functions deploy listing-watermark --no-verify-jwt
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';

// Chaque signe : sept octets, un par ligne, cinq bits utiles.
const FONT: Record<string, string> = {
  'A':'0E11111F111111','B':'1E11111E11111E','C':'0F10101010100F','D':'1E11111111111E',
  'E':'1F10101E10101F','F':'1F10101E101010','G':'0E11101711110F','H':'1111111F111111',
  'I':'1F04040404041F','J':'0702020202120C','K':'11121418141211','L':'1010101010101F',
  'M':'111B1515111111','N':'11191513111111','O':'0E11111111110E','P':'1E11111E101010',
  'Q':'0E11111115120D','R':'1E11111E141211','S':'0F10100E01011E','T':'1F040404040404',
  'U':'1111111111110E','V':'11111111110A04','W':'11111115151B11','X':'11110A040A1111',
  'Y':'11110A04040404','Z':'1F01020408101F','0':'0E11111111110E','1':'040C040404040E',
  '2':'0E11010608101F','3':'1F02040201110E','4':'02060A121F0202','5':'1F101E0101110E',
  '6':'0608101E11110E','7':'1F010204080808','8':'0E11110E11110E','9':'0E11110F01020C',
  ' ':'00000000000000','.':'00000000000C0C',',':'000000000C0C18','-':'0000001F000000',
  '+':'0004041F040400','/':'01020204080810','@':'0E11171517100E','#':'0A0A1F0A1F0A0A',
  ':':'000C0C000C0C00',
};

/// Mélange une couleur sur le pixel existant. `setPixelAt` remplace sans
/// tenir compte de l'alpha : un filigrane opaque masquerait le plan, un
/// filigrane transparent n'apparaîtrait pas.
function blend(img: Image, x: number, y: number,
               r: number, g: number, b: number, a: number) {
  if (x < 1 || y < 1 || x > img.width || y > img.height) return;
  // `>>>` et non `>>` : une couleur dont le rouge dépasse 127 a le bit de
  // poids fort à 1, et le décalage signé rendrait un nombre négatif.
  const p = img.getPixelAt(x, y) >>> 0;
  const sr = (p >>> 24) & 0xff, sg = (p >>> 16) & 0xff, sb = (p >>> 8) & 0xff;
  const nr = Math.round(sr + (r - sr) * a);
  const ng = Math.round(sg + (g - sg) * a);
  const nb = Math.round(sb + (b - sb) * a);
  img.setPixelAt(x, y, (((nr << 24) | (ng << 16) | (nb << 8) | 0xff) >>> 0));
}

/// Écrit `text` à partir de (x, y), chaque point de la fonte occupant un
/// carré de `scale` pixels. Ombre portée d'abord : sur un plan clair comme
/// sur une photo sombre, le texte doit rester lisible.
function drawText(img: Image, x0: number, y0: number, text: string, scale: number) {
  // Deux passes, et non une ombre dessinée juste avant chaque point :
  // l'ombre d'un point voisin repasserait sinon sur le point déjà éclairci,
  // et le texte ressortirait gris et sale au lieu de net.
  // Halo clair d'abord, corps sombre ensuite. L'inverse — texte clair,
  // ombre portée — a été essayé : sur un plan blanc, seul le gris de
  // l'ombre ressortait, et le filigrane devenait un brouillard illisible.
  for (const halo of [true, false]) {
    const decal = halo ? scale : 0;
    let x = x0;
    for (const ch of text.toUpperCase()) {
      const glyph = FONT[ch] ?? FONT[' '];
      for (let row = 0; row < 7; row++) {
        const bits = parseInt(glyph.substring(row * 2, row * 2 + 2), 16);
        for (let col = 0; col < 5; col++) {
          if ((bits & (1 << (4 - col))) === 0) continue;
          const px = x + col * scale + decal;
          const py = y0 + row * scale + decal;
          for (let dx = 0; dx < scale; dx++) {
            for (let dy = 0; dy < scale; dy++) {
              if (halo) blend(img, px + dx, py + dy, 255, 255, 255, 0.55);
              else blend(img, px + dx, py + dy, 0, 0, 0, 0.42);
            }
          }
        }
      }
      x += 6 * scale;
    }
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);

  let unlockId = '';
  try {
    unlockId = String((await req.json()).unlock_id ?? '');
  } catch {
    return json({ error: 'BAD_REQUEST' }, 400);
  }
  if (!unlockId) return json({ error: 'BAD_REQUEST' }, 400);

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: rows, error: jobErr } = await db.rpc('watermark_job', {
    p_unlock: unlockId,
  });
  if (jobErr) return json({ error: jobErr.message }, 500);

  const job = Array.isArray(rows) ? rows[0] : rows;
  if (!job) return json({ error: 'UNLOCK_UNKNOWN' }, 404);
  if (job.already) return json({ ok: true, skipped: 'deja fabrique' });

  // Une annonce sans plan n'est pas une anomalie : une chambre en location
  // n'en a pas. Il n'y a simplement rien à filigraner.
  if (!job.plan_path) return json({ ok: true, skipped: 'aucun plan' });

  const echec = async (message: string, status = 500) => {
    await db.rpc('watermark_done', {
      p_unlock: unlockId, p_path: null, p_error: message.substring(0, 300),
    });
    return json({ error: message }, status);
  };

  try {
    const { data: file, error: dlErr } = await db.storage
      .from('listing-media').download(job.plan_path);
    if (dlErr || !file) return await echec(`plan illisible : ${dlErr?.message}`);

    const img = await Image.decode(new Uint8Array(await file.arrayBuffer()));

    // 1600 px de large suffisent à lire des cotes et des numéros de borne,
    // et tiennent dans 250 ko environ. Au-delà, on paie du stockage pour
    // une précision que l'écran d'un téléphone ne rend pas.
    if (img.width > 1600) img.resize(1600, Image.RESIZE_AUTO);

    const scale = Math.max(2, Math.round(img.width / 440));
    const label = String(job.buyer_label ?? '').replace(/\s+/g, ' ').trim();
    const lineH = 7 * scale;

    // Des bandes réparties sur toute la hauteur, décalées d'une bande à
    // l'autre : rogner le filigrane reviendrait à rogner le plan.
    const step = Math.max(lineH * 6, Math.round(img.height / 6));
    let band = 0;
    for (let y = Math.round(step / 3); y < img.height - lineH; y += step) {
      const x = 10 + (band % 2 === 0 ? 0 : Math.round(img.width / 5));
      drawText(img, x, y, label, scale);
      band++;
    }

    const jpeg = await img.encodeJPEG(80);
    const path = `watermarked/${job.listing_id}/${job.buyer_id}.jpg`;

    const { error: upErr } = await db.storage
      .from('listing-media')
      .upload(path, jpeg, { contentType: 'image/jpeg', upsert: true });
    if (upErr) return await echec(`dépôt refusé : ${upErr.message}`);

    const { error: doneErr } = await db.rpc('watermark_done', {
      p_unlock: unlockId, p_path: path, p_error: null,
    });
    if (doneErr) return await echec(`écriture du chemin : ${doneErr.message}`);

    return json({ ok: true, path, bytes: jpeg.length });
  } catch (e) {
    return await echec(`fabrication : ${e instanceof Error ? e.message : e}`);
  }
});
