import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/countries.dart';
import '../core/supabase.dart';

/// Authentification par numéro de téléphone.
///
/// Choix délibéré : pas d'email. Sur le marché visé, l'email est rare et le
/// numéro est l'identité de fait. Il sert aussi de coordonnée de contact,
/// enregistrée automatiquement par le trigger `handle_new_user`.
class AuthService {
  /// Normalise un numéro saisi vers le format international attendu.
  ///
  /// Accepte « 07 58 22 91 40 », « 0758229140 », « +2250758229140 ».
  static String normalizePhone(String input, {String dialCode = AppConfig.defaultDialCode}) {
    var s = input.replaceAll(RegExp(r'[\s\.\-\(\)]'), '');
    if (s.startsWith('00')) s = '+${s.substring(2)}';
    if (s.startsWith('+')) return s;
    s = s.replaceFirst(RegExp(r'^0+'), '');
    return '$dialCode$s';
  }

  static Future<void> sendCode(
    String phone, {
    String dialCode = AppConfig.defaultDialCode,
  }) async {
    await db.auth.signInWithOtp(phone: normalizePhone(phone, dialCode: dialCode));
  }

  static Future<void> verifyCode({
    required String phone,
    required String code,
    String? fullName,
    String role = 'client',
    Country? country,
  }) async {
    await db.auth.verifyOTP(
      phone: normalizePhone(phone, dialCode: country?.dialCode ?? AppConfig.defaultDialCode),
      token: code,
      type: OtpTypeCompat.sms,
    );

    // Le trigger SQL crée le profil avec un nom par défaut si les métadonnées
    // ne sont pas encore disponibles. On le complète ici.
    if (fullName != null && fullName.trim().isNotEmpty) {
      await db.from('profiles').update({
        'full_name': fullName.trim(),
        'role': role,
        if (country != null) 'country_code': country.code,
      }).eq('id', uid!);
    }
  }

  /// Connexion par email et mot de passe.
  ///
  /// Sert au compte administrateur et aux comptes de test : le SMS demande
  /// un fournisseur configuré et facturé, inutilisable pendant le
  /// développement.
  static Future<void> signInWithEmail(String email, String password) async {
    await db.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
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
}

/// Petit alias pour isoler l'énumération du SDK et limiter l'impact
/// d'un changement d'API lors d'une montée de version.
class OtpTypeCompat {
  static const sms = OtpType.sms;
}
