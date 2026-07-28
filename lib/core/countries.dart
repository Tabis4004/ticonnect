/// Indicatifs téléphoniques.
///
/// Le pays n'est pas figé dans le code : l'utilisateur le choisit à
/// l'inscription. Le marché de départ est ouest-africain, mais une partie
/// des utilisateurs sont des membres de la diaspora qui organisent des
/// travaux au pays depuis la France, la Belgique ou le Canada — leur
/// interdire leur propre numéro les exclurait d'emblée.
class Country {
  final String code; // ISO 3166-1 alpha-2
  final String name;
  final String dialCode;
  final String flag;

  const Country(this.code, this.name, this.dialCode, this.flag);

  @override
  String toString() => '$flag  $name  $dialCode';
}

class Countries {
  /// Afrique francophone en tête : c'est là que sont les utilisateurs.
  static const all = <Country>[
    Country('CI', "Côte d'Ivoire", '+225', '🇨🇮'),
    Country('SN', 'Sénégal', '+221', '🇸🇳'),
    Country('CM', 'Cameroun', '+237', '🇨🇲'),
    Country('BF', 'Burkina Faso', '+226', '🇧🇫'),
    Country('ML', 'Mali', '+223', '🇲🇱'),
    Country('BJ', 'Bénin', '+229', '🇧🇯'),
    Country('TG', 'Togo', '+228', '🇹🇬'),
    Country('NE', 'Niger', '+227', '🇳🇪'),
    Country('GN', 'Guinée', '+224', '🇬🇳'),
    Country('GA', 'Gabon', '+241', '🇬🇦'),
    Country('CG', 'Congo', '+242', '🇨🇬'),
    Country('CD', 'RD Congo', '+243', '🇨🇩'),
    Country('TD', 'Tchad', '+235', '🇹🇩'),
    Country('CF', 'Centrafrique', '+236', '🇨🇫'),
    Country('MR', 'Mauritanie', '+222', '🇲🇷'),
    Country('MG', 'Madagascar', '+261', '🇲🇬'),
    Country('RW', 'Rwanda', '+250', '🇷🇼'),
    Country('BI', 'Burundi', '+257', '🇧🇮'),
    Country('DJ', 'Djibouti', '+253', '🇩🇯'),
    Country('KM', 'Comores', '+269', '🇰🇲'),
    Country('MA', 'Maroc', '+212', '🇲🇦'),
    Country('DZ', 'Algérie', '+213', '🇩🇿'),
    Country('TN', 'Tunisie', '+216', '🇹🇳'),
    Country('GH', 'Ghana', '+233', '🇬🇭'),
    Country('NG', 'Nigéria', '+234', '🇳🇬'),
    Country('FR', 'France', '+33', '🇫🇷'),
    Country('BE', 'Belgique', '+32', '🇧🇪'),
    Country('CH', 'Suisse', '+41', '🇨🇭'),
    Country('CA', 'Canada', '+1', '🇨🇦'),
    Country('US', 'États-Unis', '+1', '🇺🇸'),
  ];

  static Country byCode(String code) => all.firstWhere(
        (c) => c.code == code.toUpperCase(),
        orElse: () => all.first,
      );

  /// Recherche par nom ou par indicatif, insensible à la casse.
  static List<Country> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.dialCode.contains(q) ||
            c.code.toLowerCase() == q)
        .toList();
  }
}
