import 'package:flutter/material.dart';

import '../core/countries.dart';
import '../core/theme.dart';

/// Sélecteur de pays : drapeau + indicatif, ouvre une liste cherchable.
class CountryPickerButton extends StatelessWidget {
  final Country selected;
  final ValueChanged<Country> onChanged;

  const CountryPickerButton({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CountrySheet(),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(context),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDDE2DE)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(selected.flag, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 6),
          Text(selected.dialCode,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const Icon(Icons.arrow_drop_down, color: Colors.black45),
        ]),
      ),
    );
  }
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet();
  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  final _query = TextEditingController();
  List<Country> _results = Countries.all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Chercher un pays ou un indicatif',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _results = Countries.search(v)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final c = _results[i];
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                  title: Text(c.name),
                  trailing: Text(c.dialCode,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: AppTheme.primary)),
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
