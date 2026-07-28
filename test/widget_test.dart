import 'package:flutter_test/flutter_test.dart';
import 'package:ticonnect/services/auth_service.dart';

/// Le test généré par `flutter create` référence `MyApp`, qui n'existe pas
/// ici : il fait échouer `flutter analyze`. Remplacé par un test réel.
///
/// La normalisation des numéros mérite d'être couverte : les utilisateurs
/// saisissent leur numéro de six façons différentes, et une erreur ici
/// empêcherait purement et simplement la connexion.
void main() {
  group('AuthService.normalizePhone', () {
    test("ajoute l'indicatif à un numéro local", () {
      expect(AuthService.normalizePhone('0758229140'), '+2250758229140');
    });

    test('supprime les espaces et les séparateurs', () {
      expect(AuthService.normalizePhone('07 58 22 91 40'), '+2250758229140');
      expect(AuthService.normalizePhone('07-58-22-91-40'), '+2250758229140');
      expect(AuthService.normalizePhone('07.58.22.91.40'), '+2250758229140');
    });

    test('laisse intact un numéro déjà international', () {
      expect(AuthService.normalizePhone('+2250758229140'), '+2250758229140');
    });

    test('convertit le préfixe 00 en +', () {
      expect(AuthService.normalizePhone('002250758229140'), '+2250758229140');
    });

    test('respecte un autre indicatif pays', () {
      expect(
        AuthService.normalizePhone('0612345678', dialCode: '+33'),
        '+33612345678',
      );
    });
  });
}
