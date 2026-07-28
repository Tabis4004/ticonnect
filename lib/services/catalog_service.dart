import '../core/supabase.dart';
import '../models/models.dart';

/// Référentiel des métiers. Chargé une fois puis gardé en mémoire :
/// 54 lignes qui ne changent jamais, inutile de les relire à chaque écran.
class CatalogService {
  static List<TradeCategory>? _categories;
  static List<Trade>? _trades;

  static Future<List<TradeCategory>> categories() async {
    if (_categories != null) return _categories!;
    final rows = await db
        .from('trade_categories')
        .select()
        .order('sort_order');
    _categories = rows.map<TradeCategory>((e) => TradeCategory.fromMap(e)).toList();
    return _categories!;
  }

  static Future<List<Trade>> trades() async {
    if (_trades != null) return _trades!;
    final rows = await db
        .from('trades')
        .select()
        .eq('is_active', true)
        .order('category_id')
        .order('sort_order');
    _trades = rows.map<Trade>((e) => Trade.fromMap(e)).toList();
    return _trades!;
  }

  static Future<List<Trade>> byCategory(int categoryId) async {
    final all = await trades();
    return all.where((t) => t.categoryId == categoryId).toList();
  }

  static Future<Trade?> byId(int id) async {
    final all = await trades();
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
