// =====================================================================
// providers.ts — FedaPay et GeniusPay
//
// Les deux fournisseurs retenus après test. Leurs API diffèrent sur à peu
// près tout — authentification, format de montant, schéma de signature —
// d'où cette couche d'adaptation : le reste du code manipule une seule
// forme, `InitResult`, et ignore lequel des deux répond.
//
// Secrets attendus (supabase secrets set …) :
//   FEDAPAY_SECRET_KEY        sk_live_… ou sk_sandbox_…
//   FEDAPAY_WEBHOOK_SECRET    wh_…
//   FEDAPAY_ENV               live | sandbox   (défaut : sandbox)
//   GENIUSPAY_API_KEY         pk_live_… ou pk_sandbox_…
//   GENIUSPAY_API_SECRET      sk_live_… ou sk_sandbox_…
//   GENIUSPAY_WEBHOOK_SECRET  whsec_…
// =====================================================================

export type Provider = 'fedapay' | 'geniuspay';

export interface InitPaymentInput {
  provider: Provider;
  amount: number;
  currency: string;
  description: string;
  customerName?: string | null;
  customerPhone?: string | null;
  customerEmail?: string | null;
  countryCode?: string | null;
  successUrl?: string | null;
  errorUrl?: string | null;
  /// Renvoyé tel quel dans le webhook. C'est ce qui relie le paiement au
  /// profil : sans lui, une notification de succès n'est rattachable à
  /// personne.
  metadata: Record<string, string>;
}

export interface InitResult {
  reference: string;
  checkoutUrl: string;
}

// =====================================================================
// GENIUSPAY
// =====================================================================
async function initGeniusPay(input: InitPaymentInput): Promise<InitResult> {
  const res = await fetch(
    'https://pay.genius.ci/api/v1/merchant/payments',
    {
      method: 'POST',
      headers: {
        'X-API-Key': Deno.env.get('GENIUSPAY_API_KEY') ?? '',
        'X-API-Secret': Deno.env.get('GENIUSPAY_API_SECRET') ?? '',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: input.amount,
        currency: input.currency,
        description: input.description,
        // `payment_method` volontairement omis : GeniusPay affiche alors sa
        // page de checkout, où le client choisit Wave, Orange, MTN, Moov ou
        // carte. Imposer un opérateur depuis l'application ferait perdre
        // tous ceux qui n'en ont pas de compte.
        customer: {
          name: input.customerName ?? undefined,
          email: input.customerEmail ?? undefined,
          phone: input.customerPhone ?? undefined,
          country: input.countryCode ?? undefined,
        },
        success_url: input.successUrl ?? undefined,
        error_url: input.errorUrl ?? undefined,
        metadata: input.metadata,
      }),
    },
  );

  const body = await res.json();
  if (!res.ok || !body?.success) {
    throw new Error(
      `GeniusPay : ${body?.error?.message ?? res.status}`,
    );
  }

  const data = body.data;
  const url = data.checkout_url ?? data.payment_url;
  if (!url) throw new Error('GeniusPay : aucune URL de paiement renvoyée');

  return { reference: String(data.reference), checkoutUrl: String(url) };
}

// =====================================================================
// FEDAPAY
// =====================================================================
function fedapayBase(): string {
  return Deno.env.get('FEDAPAY_ENV') === 'live'
    ? 'https://api.fedapay.com/v1'
    : 'https://sandbox-api.fedapay.com/v1';
}

async function initFedaPay(input: InitPaymentInput): Promise<InitResult> {
  const auth = {
    'Authorization': `Bearer ${Deno.env.get('FEDAPAY_SECRET_KEY') ?? ''}`,
    'Content-Type': 'application/json',
  };

  const created = await fetch(`${fedapayBase()}/transactions`, {
    method: 'POST',
    headers: auth,
    body: JSON.stringify({
      description: input.description,
      amount: Math.round(input.amount),
      currency: { iso: input.currency },
      callback_url: input.successUrl ?? undefined,
      customer: {
        firstname: input.customerName ?? 'Client',
        email: input.customerEmail ?? undefined,
        phone_number: input.customerPhone
          ? { number: input.customerPhone, country: input.countryCode ?? 'CI' }
          : undefined,
      },
      custom_metadata: input.metadata,
    }),
  });

  const createdBody = await created.json();
  if (!created.ok) {
    throw new Error(
      `FedaPay : ${createdBody?.message ?? created.status}`,
    );
  }

  const transaction = createdBody['v1/transaction'] ?? createdBody.transaction;
  const id = transaction?.id;
  if (!id) throw new Error('FedaPay : transaction sans identifiant');

  // FedaPay sépare la création de la transaction et la génération du lien
  // de paiement : deux appels, toujours.
  const tokenRes = await fetch(
    `${fedapayBase()}/transactions/${id}/token`,
    { method: 'POST', headers: auth },
  );
  const tokenBody = await tokenRes.json();
  if (!tokenRes.ok) {
    throw new Error(`FedaPay : ${tokenBody?.message ?? tokenRes.status}`);
  }

  const url = tokenBody?.url;
  if (!url) throw new Error('FedaPay : aucune URL de paiement renvoyée');

  return { reference: String(id), checkoutUrl: String(url) };
}

export function initPayment(input: InitPaymentInput): Promise<InitResult> {
  return input.provider === 'fedapay'
    ? initFedaPay(input)
    : initGeniusPay(input);
}

// =====================================================================
// VÉRIFICATION DES SIGNATURES DE WEBHOOK
// =====================================================================

async function hmacSha256Hex(secret: string, data: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(data),
  );
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/// Comparaison à temps constant. Un `===` sur une signature fuit sa
/// valeur octet par octet : l'écart de durée entre deux échecs indique
/// combien de caractères étaient corrects.
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const MAX_SKEW_SECONDS = 300;

export interface WebhookCheck {
  valid: boolean;
  reason?: string;
}

/// GeniusPay — signature = HMAC-SHA256(timestamp + "." + payload, secret),
/// en-têtes `X-Webhook-Signature` et `X-Webhook-Timestamp`.
///
/// La documentation officielle recalcule le corps via `json_encode` après
/// décodage. Rien ne garantit que ce ré-encodage reproduise le corps brut
/// à l'octet près, donc on essaie les deux formes plutôt que de rejeter un
/// webhook authentique sur une virgule d'espacement.
export async function verifyGeniusPay(
  rawBody: string,
  headers: Headers,
): Promise<WebhookCheck> {
  const secret = Deno.env.get('GENIUSPAY_WEBHOOK_SECRET');
  if (!secret) return { valid: false, reason: 'GENIUSPAY_WEBHOOK_SECRET absent' };

  const signature = headers.get('x-webhook-signature');
  const timestamp = headers.get('x-webhook-timestamp');
  if (!signature || !timestamp) {
    return { valid: false, reason: 'En-têtes de signature manquants' };
  }

  const age = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (!Number.isFinite(age) || age > MAX_SKEW_SECONDS) {
    return { valid: false, reason: 'Horodatage hors tolérance' };
  }

  const candidates = [rawBody];
  try {
    candidates.push(JSON.stringify(JSON.parse(rawBody)));
  } catch {
    // Corps non-JSON : la seule forme testable est le brut.
  }

  for (const body of candidates) {
    const expected = await hmacSha256Hex(secret, `${timestamp}.${body}`);
    if (safeEqual(expected, signature)) return { valid: true };
  }
  return { valid: false, reason: 'Signature invalide' };
}

/// FedaPay — en-tête `X-FEDAPAY-SIGNATURE` au format `t=<ts>,s=<sig>`,
/// signature = HMAC-SHA256(`<ts>.<corps brut>`, secret).
export async function verifyFedaPay(
  rawBody: string,
  headers: Headers,
): Promise<WebhookCheck> {
  const secret = Deno.env.get('FEDAPAY_WEBHOOK_SECRET');
  if (!secret) return { valid: false, reason: 'FEDAPAY_WEBHOOK_SECRET absent' };

  const header = headers.get('x-fedapay-signature');
  if (!header) return { valid: false, reason: 'En-tête de signature manquant' };

  let timestamp = '';
  const signatures: string[] = [];
  for (const part of header.split(',')) {
    const [k, v] = part.split('=', 2);
    if (k?.trim() === 't') timestamp = v?.trim() ?? '';
    if (k?.trim() === 's') signatures.push(v?.trim() ?? '');
  }
  if (!timestamp || signatures.length === 0) {
    return { valid: false, reason: 'En-tête de signature malformé' };
  }

  const age = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (!Number.isFinite(age) || age > MAX_SKEW_SECONDS) {
    return { valid: false, reason: 'Horodatage hors tolérance' };
  }

  const expected = await hmacSha256Hex(secret, `${timestamp}.${rawBody}`);
  for (const s of signatures) {
    if (safeEqual(expected, s)) return { valid: true };
  }
  return { valid: false, reason: 'Signature invalide' };
}

// =====================================================================
// LECTURE UNIFIÉE DES ÉVÉNEMENTS
// =====================================================================
export interface PaymentEvent {
  provider: Provider;
  reference: string;
  succeeded: boolean;
  failed: boolean;
  amount?: number;
  currency?: string;
  metadata: Record<string, string>;
}

export function readEvent(
  provider: Provider,
  payload: Record<string, unknown>,
): PaymentEvent | null {
  if (provider === 'geniuspay') {
    const event = String(payload.event ?? '');
    const data = (payload.data ?? {}) as Record<string, unknown>;
    const reference = data.reference ? String(data.reference) : '';
    if (!reference) return null;

    return {
      provider,
      reference,
      succeeded: event === 'payment.success' ||
        String(data.status ?? '') === 'completed',
      failed: ['payment.failed', 'payment.cancelled', 'payment.expired']
        .includes(event),
      amount: data.amount != null ? Number(data.amount) : undefined,
      currency: data.currency ? String(data.currency) : undefined,
      metadata: (data.metadata ?? {}) as Record<string, string>,
    };
  }

  // FedaPay
  const name = String(payload.name ?? '');
  const entity = (payload.entity ?? {}) as Record<string, unknown>;
  const reference = entity.id != null ? String(entity.id) : '';
  if (!reference) return null;

  return {
    provider,
    reference,
    succeeded: name === 'transaction.approved' ||
      String(entity.status ?? '') === 'approved',
    failed: ['transaction.declined', 'transaction.canceled'].includes(name),
    amount: entity.amount != null ? Number(entity.amount) : undefined,
    currency: (entity.currency as Record<string, unknown> | undefined)?.iso
      ? String((entity.currency as Record<string, unknown>).iso)
      : undefined,
    metadata: (entity.custom_metadata ?? {}) as Record<string, string>,
  };
}
