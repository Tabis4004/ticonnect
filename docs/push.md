# Notifications push — mise en service

Tout est en place sauf **une chose que vous seul pouvez fournir** : la clé
du compte de service Firebase.

---

## 1. Récupérer la clé de compte de service

Console Firebase → projet `ticonnect-d2825` → **Paramètres du projet** →
onglet **Comptes de service** → **Générer une nouvelle clé privée**.

Un fichier JSON se télécharge. Il contient `client_email`, `private_key` et
`project_id`. Ne le versionnez jamais — il donne le droit d'envoyer des
notifications au nom de votre application.

## 2. Poser les secrets

```bash
cd ~/Documents/ticonnect

supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat ~/Downloads/ticonnect-d2825-*.json)"
supabase secrets set PUSH_SHARED_SECRET="$(openssl rand -hex 32)"
```

Notez la valeur du second : elle doit aussi être connue de la base.

## 3. Déclarer le secret partagé côté base

Dans l'éditeur SQL Supabase, avec la valeur générée ci-dessus :

```sql
alter database postgres set app.push_secret = 'la-valeur-generee';
```

Puis redémarrez le projet (Settings → General → Restart project) pour que
le paramètre soit pris en compte par les nouvelles connexions.

Sans ce secret, `send-push` refuse les appels : la fonction est publique
pour que `pg_net` puisse l'atteindre, et c'est cet en-tête qui la protège.

## 4. Déployer la fonction

```bash
supabase functions deploy send-push --no-verify-jwt
```

`--no-verify-jwt` parce que `pg_net` appelle sans jeton utilisateur.

## 5. Compiler

```bash
flutter pub get
ADS_TEST=false ./build_apk.sh
```

Le premier lancement demandera l'autorisation d'envoyer des notifications.

---

## Vérifier que ça marche

Envoyez un message depuis un compte vers un autre, puis :

```sql
-- Le jeton est-il enregistré ?
select profile_id, platform, app_version, last_active_at from public.devices;

-- La notification a-t-elle été créée ?
select kind, title, created_at from public.notifications
 order by created_at desc limit 5;

-- L'appel HTTP est-il parti ?
select id, status_code, content::text
  from net._http_response order by created_at desc limit 5;
```

Les journaux de `send-push` (Supabase → Edge Functions → send-push) donnent
le détail des échecs FCM.

---

## Ce que la chaîne fait

| Événement | Notification créée pour | Déclencheur |
|---|---|---|
| Nouvelle mission | ouvriers du métier, même pays | `job_requests_notify` |
| Nouveau message | le destinataire | `messages_notify` |
| Nouvelle candidature | le client | `job_applications_notify` |

Chaque insertion dans `notifications` déclenche `notifications_push`, qui
appelle `send-push` via `pg_net`. La fonction lit les jetons de `devices`,
signe un JWT avec le compte de service, obtient un jeton OAuth Google et
appelle l'API FCM v1.

Les jetons révoqués (`UNREGISTERED`) sont supprimés automatiquement : les
garder ferait échouer chaque envoi futur et gonflerait la table.

**Une seule notification non lue par conversation.** Dix messages d'affilée
ne produisent pas dix alertes : celle qui existe déjà suffit à dire qu'on
vous a écrit.

## Couper les push sans rien casser

Administration → réglages → **Notifications push**. Les notifications dans
l'application continuent de fonctionner ; seul l'envoi vers les téléphones
s'arrête.
