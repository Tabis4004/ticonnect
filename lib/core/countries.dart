/// Pays couverts : l'ensemble du continent africain, plus les principales
/// destinations de la diaspora.
///
/// Chaque pays porte sa langue par défaut. C'est elle qui détermine la
/// langue de l'interface à l'inscription — un utilisateur au Ghana ne
/// devrait pas avoir à chercher où changer la langue avant de comprendre
/// l'écran d'accueil.
class Country {
  final String code; // ISO 3166-1 alpha-2
  final String name; // nom français
  final String nameEn;
  final String dialCode;
  final String flag;
  final String lang; // langue par défaut de l'interface

  const Country(
    this.code,
    this.name,
    this.nameEn,
    this.dialCode,
    this.flag,
    this.lang,
  );
}

class Countries {
  /// Afrique de l'Ouest et centrale en tête : c'est le marché de départ,
  /// et l'ordre d'une liste est une décision produit, pas un détail.
  static const all = <Country>[
    // --- Afrique de l'Ouest
    Country('CI', "Côte d'Ivoire", "Côte d'Ivoire", '+225', '🇨🇮', 'fr'),
    Country('SN', 'Sénégal', 'Senegal', '+221', '🇸🇳', 'fr'),
    Country('ML', 'Mali', 'Mali', '+223', '🇲🇱', 'fr'),
    Country('BF', 'Burkina Faso', 'Burkina Faso', '+226', '🇧🇫', 'fr'),
    Country('BJ', 'Bénin', 'Benin', '+229', '🇧🇯', 'fr'),
    Country('TG', 'Togo', 'Togo', '+228', '🇹🇬', 'fr'),
    Country('NE', 'Niger', 'Niger', '+227', '🇳🇪', 'fr'),
    Country('GN', 'Guinée', 'Guinea', '+224', '🇬🇳', 'fr'),
    Country('GW', 'Guinée-Bissau', 'Guinea-Bissau', '+245', '🇬🇼', 'pt'),
    Country('MR', 'Mauritanie', 'Mauritania', '+222', '🇲🇷', 'fr'),
    Country('GM', 'Gambie', 'Gambia', '+220', '🇬🇲', 'en'),
    Country('GH', 'Ghana', 'Ghana', '+233', '🇬🇭', 'en'),
    Country('NG', 'Nigéria', 'Nigeria', '+234', '🇳🇬', 'en'),
    Country('SL', 'Sierra Leone', 'Sierra Leone', '+232', '🇸🇱', 'en'),
    Country('LR', 'Libéria', 'Liberia', '+231', '🇱🇷', 'en'),
    Country('CV', 'Cap-Vert', 'Cabo Verde', '+238', '🇨🇻', 'pt'),

    // --- Afrique centrale
    Country('CM', 'Cameroun', 'Cameroon', '+237', '🇨🇲', 'fr'),
    Country('GA', 'Gabon', 'Gabon', '+241', '🇬🇦', 'fr'),
    Country('CG', 'Congo', 'Congo', '+242', '🇨🇬', 'fr'),
    Country('CD', 'RD Congo', 'DR Congo', '+243', '🇨🇩', 'fr'),
    Country('TD', 'Tchad', 'Chad', '+235', '🇹🇩', 'fr'),
    Country('CF', 'Centrafrique', 'Central African Rep.', '+236', '🇨🇫', 'fr'),
    Country('GQ', 'Guinée équatoriale', 'Equatorial Guinea', '+240', '🇬🇶', 'es'),
    Country('ST', 'Sao Tomé-et-Principe', 'São Tomé & Príncipe', '+239', '🇸🇹', 'pt'),
    Country('AO', 'Angola', 'Angola', '+244', '🇦🇴', 'pt'),

    // --- Afrique du Nord
    Country('MA', 'Maroc', 'Morocco', '+212', '🇲🇦', 'fr'),
    Country('DZ', 'Algérie', 'Algeria', '+213', '🇩🇿', 'fr'),
    Country('TN', 'Tunisie', 'Tunisia', '+216', '🇹🇳', 'fr'),
    Country('LY', 'Libye', 'Libya', '+218', '🇱🇾', 'ar'),
    Country('EG', 'Égypte', 'Egypt', '+20', '🇪🇬', 'ar'),
    Country('SD', 'Soudan', 'Sudan', '+249', '🇸🇩', 'ar'),

    // --- Afrique de l'Est
    Country('KE', 'Kenya', 'Kenya', '+254', '🇰🇪', 'en'),
    Country('TZ', 'Tanzanie', 'Tanzania', '+255', '🇹🇿', 'en'),
    Country('UG', 'Ouganda', 'Uganda', '+256', '🇺🇬', 'en'),
    Country('RW', 'Rwanda', 'Rwanda', '+250', '🇷🇼', 'fr'),
    Country('BI', 'Burundi', 'Burundi', '+257', '🇧🇮', 'fr'),
    Country('ET', 'Éthiopie', 'Ethiopia', '+251', '🇪🇹', 'en'),
    Country('SO', 'Somalie', 'Somalia', '+252', '🇸🇴', 'ar'),
    Country('DJ', 'Djibouti', 'Djibouti', '+253', '🇩🇯', 'fr'),
    Country('ER', 'Érythrée', 'Eritrea', '+291', '🇪🇷', 'en'),
    Country('SS', 'Soudan du Sud', 'South Sudan', '+211', '🇸🇸', 'en'),
    Country('MZ', 'Mozambique', 'Mozambique', '+258', '🇲🇿', 'pt'),
    Country('MG', 'Madagascar', 'Madagascar', '+261', '🇲🇬', 'fr'),
    Country('MU', 'Maurice', 'Mauritius', '+230', '🇲🇺', 'fr'),
    Country('KM', 'Comores', 'Comoros', '+269', '🇰🇲', 'fr'),
    Country('SC', 'Seychelles', 'Seychelles', '+248', '🇸🇨', 'en'),

    // --- Afrique australe
    Country('ZA', 'Afrique du Sud', 'South Africa', '+27', '🇿🇦', 'en'),
    Country('ZW', 'Zimbabwe', 'Zimbabwe', '+263', '🇿🇼', 'en'),
    Country('ZM', 'Zambie', 'Zambia', '+260', '🇿🇲', 'en'),
    Country('MW', 'Malawi', 'Malawi', '+265', '🇲🇼', 'en'),
    Country('BW', 'Botswana', 'Botswana', '+267', '🇧🇼', 'en'),
    Country('NA', 'Namibie', 'Namibia', '+264', '🇳🇦', 'en'),
    Country('LS', 'Lesotho', 'Lesotho', '+266', '🇱🇸', 'en'),
    Country('SZ', 'Eswatini', 'Eswatini', '+268', '🇸🇿', 'en'),

    // --- Diaspora
    Country('FR', 'France', 'France', '+33', '🇫🇷', 'fr'),
    Country('BE', 'Belgique', 'Belgium', '+32', '🇧🇪', 'fr'),
    Country('CH', 'Suisse', 'Switzerland', '+41', '🇨🇭', 'fr'),
    Country('CA', 'Canada', 'Canada', '+1', '🇨🇦', 'fr'),
    Country('GB', 'Royaume-Uni', 'United Kingdom', '+44', '🇬🇧', 'en'),
    Country('US', 'États-Unis', 'United States', '+1', '🇺🇸', 'en'),
    Country('PT', 'Portugal', 'Portugal', '+351', '🇵🇹', 'pt'),
  ];

  static Country byCode(String? code) => all.firstWhere(
        (c) => c.code == (code ?? '').toUpperCase(),
        orElse: () => all.first,
      );

  /// Recherche par nom français, nom anglais, indicatif ou code ISO.
  static List<Country> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.nameEn.toLowerCase().contains(q) ||
            c.dialCode.contains(q) ||
            c.code.toLowerCase() == q)
        .toList();
  }
}
