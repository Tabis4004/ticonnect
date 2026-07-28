import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/countries.dart';
import '../core/l10n.dart';
import '../core/supabase.dart';

/// Authentification par pseudo et mot de passe.
///
/// Pas de SMS, pas d'email : sur ce marché, exiger une adresse email écarte
/// une partie des ouvriers, et le SMS coûte environ 0,24 $ l'unité vers la
/// Côte d'Ivoire — une barrière à l'inscription autant qu'un poste de coût.
///
/// Supabase Auth réclame un identifiant de forme email pour le mot de passe.
/// On en synthétise un à partir du pseudo ; l'utilisateur ne le voit jamais.
/// Le pseudo réel, unique, vit dans `profiles.username`.
///
/// L'inscription ne demande que le pseudo, le mot de passe et le nom.
/// Les coordonnées — téléphone, WhatsApp, ville — se renseignent ensuite
/// depuis le profil : chaque champ supplémentaire à l'inscription fait
/// abandonner une part des utilisateurs, et rien n'oblige à les collecter
/// avant que la personne ait vu à quoi sert l'application.
class AuthService {
  static const _domain = 'users.ticonnect.app';

  static String _emailFor(String identifier) {
    final id = identifier.trim().toLowerCase();
    // Un identifiant contenant @ est traité tel quel : c'est ainsi que les
    // comptes administrateur et de test se connectent.
    return id.contains('@') ? id : '$id@$_domain';
  }

  /// Normalise un numéro saisi vers le format international.
  /// Accepte « 07 58 22 91 40 », « 0758229140 », « +2250758229140 ».
  static String normalizePhone(
    String input, {
    String dialCode = AppConfig.defaultDialCode,
  }) {
    var s = input.replaceAll(RegExp(r'[\s\.\-\(\)]'), '');
    if (s.startsWith('00')) s = '+${s.substring(2)}';
    if (s.startsWith('+')) return s;
    s = s.replaceFirst(RegExp(r'^0+'), '');
    return '$dialCode$s';
  }

  /// Règles de forme du pseudo, identiques à la contrainte SQL.
  static String? validateUsername(String value) {
    final v = value.trim().toLowerCase();
    if (v.length < 3) return 'Au moins 3 caractères';
    if (v.length > 24) return 'Au plus 24 caractères';
    if (!RegExp(r'^[a-z0-9._]+$').hasMatch(v)) {
      return 'Lettres, chiffres, point et tiret bas seulement';
    }
    return null;
  }

  static Future<bool> usernameAvailable(String username) async {
    try {
      final r = await db.rpc('username_available',
          params: {'p_username': username.trim().toLowerCase()});
      return r == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> signUp({
    required String username,
    required String password,
    required String fullName,
    String role = 'client',
    Country? country,
  }) async {
    final c = country ?? Countries.byCode(AppConfig.defaultCountry);
    await db.auth.signUp(
      email: _emailFor(username),
      password: password,
      data: {
        'username': username.trim().toLowerCase(),
        'full_name': fullName.trim(),
        'role': role,
        'country_code': c.code,
        // Langue déduite du pays : personne ne devrait avoir à chercher
        // où changer la langue avant de comprendre l'écran d'accueil.
        'preferred_language': L.resolve(c.lang),
      },
    );
  }

  /// Accepte un pseudo ou une adresse email (comptes admin et de test).
  static Future<void> signIn(String identifier, String password) async {
    await db.auth.signInWithPassword(
      email: _emailFor(identifier),
      password: password,
    );
  }

  static Future<bool> isAdmin() async {
    try {
      final r = await db.rpc('is_admin');
      return r == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> signOut() => db.auth.signOut();
}
