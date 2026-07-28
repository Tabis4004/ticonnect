import 'package:intl/intl.dart';

/// Formatage adapté au marché : le franc CFA n'a pas de décimales et
/// s'écrit avec un séparateur de milliers par espace.
class Fmt {
  static final _money = NumberFormat.decimalPattern('fr');

  static String money(num? amount, String currency) {
    if (amount == null) return '—';
    return '${_money.format(amount.round())} $currency';
  }

  static String range(num? min, num? max, String currency) {
    if (min == null && max == null) return 'À négocier';
    if (min != null && max != null) {
      return '${_money.format(min.round())} – ${_money.format(max.round())} $currency';
    }
    return money(min ?? max, currency);
  }

  static String unit(String pricingUnit) => switch (pricingUnit) {
        'hour' => '/heure',
        'day' => '/jour',
        'project' => 'au forfait',
        _ => '',
      };

  static String urgency(String value) => switch (value) {
        'immediate' => 'Urgent',
        'this_week' => 'Cette semaine',
        'flexible' => 'Flexible',
        _ => value,
      };

  /// Temps relatif court, sans dépendance à une locale téléchargée.
  static String ago(DateTime? date) {
    if (date == null) return '';
    final d = DateTime.now().difference(date);
    if (d.inMinutes < 1) return "à l'instant";
    if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'il y a ${d.inHours} h';
    if (d.inDays < 7) return 'il y a ${d.inDays} j';
    return DateFormat('d MMM', 'fr').format(date);
  }

  static String time(DateTime date) => DateFormat('HH:mm').format(date);

  static String distance(double? km) {
    if (km == null) return '';
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }
}
