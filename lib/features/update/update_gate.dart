import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../services/update_service.dart';
import '../../widgets/common.dart';

/// Interpose un écran de mise à jour devant l'application, si besoin.
///
/// Placé au-dessus de l'aiguillage de session, et non dans l'application
/// elle-même : une version dont on veut retirer l'usage doit être arrêtée
/// avant l'écran de connexion, pas après. Quelqu'un qui n'arrive pas à se
/// connecter parce que la version est cassée doit lire pourquoi.
///
/// La vérification ne retarde jamais l'affichage. Tant qu'elle n'a pas
/// répondu, l'application s'affiche normalement — un démarrage suspendu à
/// un appel réseau serait un blocage certain contre un risque hypothétique,
/// sur un marché où la connexion tombe souvent.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  UpdateStatus _status = UpdateStatus.none;

  @override
  void initState() {
    super.initState();
    _verifier();
  }

  Future<void> _verifier() async {
    final status = await UpdateService.check();
    if (!mounted) return;
    setState(() => _status = status);

    if (status == UpdateStatus.suggested && !UpdateService.suggestionShown) {
      UpdateService.suggestionShown = true;
      // Après la construction : on ne peut pas ouvrir une boîte de dialogue
      // pendant que l'arbre se construit.
      WidgetsBinding.instance.addPostFrameCallback((_) => _proposer());
    }
  }

  Future<void> _proposer() async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Une nouvelle version est disponible'),
        content: Text(
          'Tu utilises la version ${UpdateService.installedVersion}. '
          'La version ${UpdateService.targetVersion} corrige des problèmes '
          'et ajoute des fonctionnalités.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mettre à jour'),
          ),
        ],
      ),
    );
    if (ok == true) await _ouvrirLaFiche();
  }

  Future<void> _ouvrirLaFiche() async {
    final uri = Uri.tryParse(UpdateService.storeUrl);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showError(context, "Impossible d'ouvrir le Play Store.");
      }
    } catch (_) {
      if (mounted) showError(context, "Impossible d'ouvrir le Play Store.");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status != UpdateStatus.required) return widget.child;

    // Aucun bouton de sortie, et `PopScope` ferme la porte de derrière :
    // le blocage ne sert à rien s'il suffit du bouton retour pour l'éviter.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.system_update,
                      size: 64, color: AppTheme.primary.withValues(alpha: 0.8)),
                  const SizedBox(height: 24),
                  const Text(
                    'Mise à jour nécessaire',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Cette version de Ticonnect n\'est plus utilisable. '
                    'Installe la version ${UpdateService.targetVersion} pour '
                    'continuer.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _ouvrirLaFiche,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Mettre à jour'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Version installée : ${UpdateService.installedVersion}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black38),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
