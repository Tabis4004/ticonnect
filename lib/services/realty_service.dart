import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import 'ads_service.dart';
import 'settings_service.dart';

/// Annonces immobilières : lecture, dépôt, déblocage.
///
/// UNE RÈGLE À NE PAS OUBLIER EN TOUCHANT CE FICHIER
///
/// Jamais de `select('*')` sur `listings`. Trois colonnes — l'adresse
/// exacte, le numéro du vendeur — ont vu leur droit de lecture retiré au
/// niveau des privilèges Postgres : `*` les demande, et la requête entière
/// échoue par « permission denied ». Les colonnes libres sont donc
/// énumérées une fois, dans `_colonnes`, et c'est la seule liste à tenir.
///
/// Ce qui se paie passe par `private()` et `files()`, qui vérifient le
/// déblocage côté serveur.
const _colonnes =
    'id, seller_id, deal, property, title, description, '
    'country_code, city, neighborhood, price, currency, price_period, '
    'surface_m2, rooms, land_reference, status, views_count, '
    'unlocks_count, expires_at, created_at';

/// Ce que tout le monde voit, sans rien débloquer.
class Listing {
  Listing.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        sellerId = m['seller_id'] as String,
        deal = m['deal'] as String,
        property = m['property'] as String,
        title = m['title'] as String,
        description = m['description'] as String?,
        countryCode = m['country_code'] as String,
        city = m['city'] as String,
        neighborhood = m['neighborhood'] as String?,
        price = (m['price'] as num?)?.toDouble() ?? 0,
        currency = m['currency'] as String? ?? 'XOF',
        pricePeriod = m['price_period'] as String?,
        surfaceM2 = (m['surface_m2'] as num?)?.toDouble(),
        rooms = (m['rooms'] as num?)?.toInt(),
        landReference = m['land_reference'] as String?,
        status = m['status'] as String? ?? 'brouillon',
        unlocksCount = (m['unlocks_count'] as num?)?.toInt() ?? 0,
        previewPath = _premierApercu(m);

  final String id, sellerId, deal, property, title, countryCode, city, status;
  final String? description, neighborhood, pricePeriod, landReference;
  final String currency;
  final double price;
  final double? surfaceM2;
  final int? rooms;
  final int unlocksCount;
  final String? previewPath;

  bool get estVente => deal == 'vente';

  static String? _premierApercu(Map<String, dynamic> m) {
    final medias = m['listing_media'];
    if (medias is! List || medias.isEmpty) return null;
    for (final x in medias) {
      final p = (x as Map)['preview_path'];
      if (p is String && p.isNotEmpty) return p;
    }
    return null;
  }

  /// URL publique de l'aperçu. Le seau `listing-previews` est public :
  /// l'aperçu est fait pour être vu sans rien demander.
  String? get previewUrl => previewPath == null
      ? null
      : db.storage.from('listing-previews').getPublicUrl(previewPath!);
}

/// Ce que le déblocage ouvre.
class ListingPrivate {
  ListingPrivate(this.addressExact, this.phone, this.whatsapp,
      this.planExiste, this.planPret);

  final String? addressExact, phone, whatsapp;
  final bool planExiste, planPret;
}

/// Résultat d'un déblocage, pour que l'écran sache quoi dire.
enum UnlockOutcome { ouvert, videoRequise, paiementNonConfigure, refus }

class UnlockResult {
  UnlockResult(this.outcome, [this.message]);
  final UnlockOutcome outcome;
  final String? message;
  bool get ok => outcome == UnlockOutcome.ouvert;
}

class RealtyService {
  /// Le module est éteint par défaut. Rien ne doit apparaître dans
  /// l'application tant qu'il n'y a pas d'annonces à montrer.
  static bool get enabled => SettingsService.boolean('realty_enabled', false);

  static String get unlockMode =>
      SettingsService.string('realty_unlock_mode', 'gratuit');

  // ----------------------------------------------------------------- lecture

  static Future<List<Listing>> browse({
    String? countryCode,
    String? deal,
    String? property,
    String? city,
    String? recherche,
    int limit = 40,
  }) async {
    var q = db
        .from('listings')
        .select('$_colonnes, listing_media(preview_path, sort_order)')
        .eq('status', 'publiee');

    if (countryCode != null) q = q.eq('country_code', countryCode);
    if (deal != null) q = q.eq('deal', deal);
    if (property != null) q = q.eq('property', property);
    if (city != null && city.trim().isNotEmpty) {
      q = q.ilike('city', '%${city.trim()}%');
    }
    if (recherche != null && recherche.trim().isNotEmpty) {
      final r = recherche.trim();
      q = q.or('title.ilike.%$r%,description.ilike.%$r%,'
          'neighborhood.ilike.%$r%,land_reference.ilike.%$r%');
    }

    final rows = await q.order('created_at', ascending: false).limit(limit);
    return [
      for (final r in rows) Listing.fromMap(Map<String, dynamic>.from(r)),
    ];
  }

  /// Les annonces déposées par l'utilisateur, brouillons compris.
  static Future<List<Listing>> mine() async {
    if (uid == null) return const [];
    final rows = await db
        .from('listings')
        .select('$_colonnes, listing_media(preview_path, sort_order)')
        .eq('seller_id', uid!)
        .order('created_at', ascending: false);
    return [
      for (final r in rows) Listing.fromMap(Map<String, dynamic>.from(r)),
    ];
  }

  static Future<Listing?> byId(String id) async {
    final rows = await db
        .from('listings')
        .select('$_colonnes, listing_media(preview_path, sort_order)')
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return null;
    return Listing.fromMap(Map<String, dynamic>.from(rows.first));
  }

  static Future<bool> isUnlocked(String listingId) async {
    try {
      return (await db.rpc('listing_is_unlocked',
          params: {'p_listing': listingId}) as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Les champs fermés. Lève si rien n'est débloqué — c'est voulu :
  /// l'appelant ne doit pas pouvoir confondre « vide » et « fermé ».
  static Future<ListingPrivate> private(String listingId) async {
    final rows = await db.rpc('listing_private', params: {'p_listing': listingId});
    final m = Map<String, dynamic>.from((rows as List).first);
    return ListingPrivate(
      m['address_exact'] as String?,
      m['contact_phone'] as String?,
      m['contact_whatsapp'] as String?,
      m['plan_path'] != null,
      m['watermarked_path'] != null,
    );
  }

  /// URL signées du plan filigrané et des photos en pleine définition.
  ///
  /// Dix minutes de validité : l'adresse finit dans le cache de la Webview
  /// et dans l'historique. On la redemande plutôt que de la garder.
  static Future<({String? plan, bool planEnPreparation, List<String> photos})>
      files(String listingId) async {
    final res = await db.functions.invoke(
      'listing-file',
      body: {'listing_id': listingId},
    );
    final data = res.data;
    if (data is! Map) return (plan: null, planEnPreparation: false, photos: <String>[]);
    if (data['error'] != null) throw Exception('${data['error']}');
    return (
      plan: data['plan'] as String?,
      planEnPreparation: data['plan_en_preparation'] == true,
      photos: [for (final p in (data['photos'] as List? ?? [])) '$p'],
    );
  }

  // --------------------------------------------------------------- déblocage

  static Future<UnlockResult> unlock(String listingId,
      {String? adImpressionId}) async {
    try {
      await db.rpc('unlock_listing', params: {
        'p_listing': listingId,
        'p_ad_impression_id': adImpressionId,
      });
      return UnlockResult(UnlockOutcome.ouvert);
    } catch (e) {
      final s = '$e';
      if (s.contains('AD_REQUIRED') || s.contains('AD_NOT_VERIFIED')) {
        return UnlockResult(UnlockOutcome.videoRequise,
            'Regarde la vidéo jusqu\'au bout pour ouvrir cette annonce.');
      }
      if (s.contains('PAYMENT_NOT_CONFIGURED')) {
        return UnlockResult(UnlockOutcome.paiementNonConfigure,
            'Les ouvertures payantes ne sont pas encore disponibles.');
      }
      if (s.contains('LISTING_OWN')) {
        return UnlockResult(UnlockOutcome.refus, 'C\'est ta propre annonce.');
      }
      if (s.contains('LISTING_CLOSED')) {
        return UnlockResult(UnlockOutcome.refus,
            'Cette annonce n\'est plus disponible.');
      }
      return UnlockResult(UnlockOutcome.refus, humanError(e));
    }
  }

  /// Ouverture contre le visionnage d'une vidéo récompensée.
  ///
  /// Même mécanique que la mise en avant d'un ouvrier : l'écran
  /// d'introduction annonce la récompense et laisse une porte de sortie,
  /// ce qu'AdMob exige du format récompensé. L'identifiant d'impression
  /// n'arrive qu'après la validation du serveur de Google — c'est lui qui
  /// distingue un visionnage réel d'un APK modifié.
  static Future<UnlockResult> unlockByWatchingAd(String listingId) async {
    final blocage = await AdsService.blockReason(AdKeys.realtyUnlockRewarded);
    if (blocage != null) {
      return UnlockResult(UnlockOutcome.refus, blocage);
    }

    final impressionId =
        await AdsService.showRewarded(AdKeys.realtyUnlockRewarded);
    if (impressionId == null) {
      // Ne pas reprocher un abandon à quelqu'un qui n'a jamais vu de vidéo.
      final erreur = AdsService.lastLoadError;
      return UnlockResult(
        UnlockOutcome.videoRequise,
        erreur == null
            ? 'La vidéo n\'a pas été validée. Regarde-la jusqu\'au bout pour '
                'ouvrir cette annonce.'
            : 'Aucune annonce disponible pour le moment. Réessaie plus tard.',
      );
    }

    return unlock(listingId, adImpressionId: impressionId);
  }

  // ------------------------------------------------------------------ dépôt

  /// Crée l'annonce et rend son identifiant. Le statut reste `brouillon` :
  /// on ne publie qu'une fois les images déposées, sinon la première
  /// annonce d'un vendeur apparaît vide dans la liste le temps qu'il
  /// choisisse ses photos.
  static Future<String> create(Map<String, dynamic> valeurs) async {
    final row = await db
        .from('listings')
        .insert({...valeurs, 'seller_id': uid})
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> update(String id, Map<String, dynamic> valeurs) =>
      db.from('listings').update(valeurs).eq('id', id);

  static Future<void> publish(String id) =>
      db.from('listings').update({'status': 'publiee'}).eq('id', id);

  static Future<void> remove(String id) =>
      db.from('listings').delete().eq('id', id);

  /// Dépose une image et enregistre le média.
  ///
  /// Deux fichiers pour une seule image choisie :
  ///
  ///   l'original, dans le seau privé, jamais servi tel quel ;
  ///   un aperçu minuscule, dans le seau public, que tout le monde voit.
  ///
  /// L'aperçu est fabriqué en redécodant l'image à 48 pixels de large. Le
  /// flou ne coûte rien : c'est l'agrandissement d'une image minuscule qui
  /// le produit. On évite ainsi une bibliothèque de traitement d'image de
  /// plusieurs mégaoctets pour un effet qu'un redimensionnement donne.
  static Future<void> addMedia({
    required String listingId,
    required XFile fichier,
    required String kind,
    int sortOrder = 0,
  }) async {
    final bytes = await fichier.readAsBytes();
    final base = '$uid/$listingId/${DateTime.now().millisecondsSinceEpoch}';

    final ext = fichier.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final cheminOriginal = '$base-$kind.$ext';

    await db.storage.from('listing-media').uploadBinary(
          cheminOriginal,
          bytes,
          fileOptions: FileOptions(
            contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
            upsert: true,
          ),
        );

    String? cheminApercu;
    // Le plan n'a pas d'aperçu : le montrer même flouté donnerait déjà la
    // forme de la parcelle, et c'est une partie de ce qui se paie.
    if (kind == 'photo') {
      final apercu = await _apercu(bytes);
      if (apercu != null) {
        cheminApercu = '$base-apercu.png';
        await db.storage.from('listing-previews').uploadBinary(
              cheminApercu,
              apercu,
              fileOptions: const FileOptions(
                contentType: 'image/png',
                upsert: true,
              ),
            );
      }
    }

    await db.from('listing_media').insert({
      'listing_id': listingId,
      'kind': kind,
      'storage_path': cheminOriginal,
      'preview_path': cheminApercu,
      'sort_order': sortOrder,
    });
  }

  static Future<Uint8List?> _apercu(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 48);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      // Une image illisible ne doit pas empêcher le dépôt : l'annonce
      // existera sans vignette plutôt que pas du tout.
      return null;
    }
  }
}
