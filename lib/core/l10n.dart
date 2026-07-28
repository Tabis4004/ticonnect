import 'package:flutter/foundation.dart';

/// Traduction de l'interface.
///
/// Le français sert de clé : `'Se connecter'.tr` rend la traduction si elle
/// existe, la chaîne d'origine sinon. Choix assumé plutôt qu'un système de
/// clés abstraites — le code reste lisible, et une traduction manquante
/// dégrade proprement au lieu d'afficher `auth.signin.button`.
///
/// Anglais livré en premier : avec le français, il couvre la quasi-totalité
/// du continent. L'arabe et le portugais suivront ; en attendant, les pays
/// concernés retombent sur l'anglais.
class L extends ChangeNotifier {
  static final L instance = L._();
  L._();

  static const supported = {
    'fr': 'Français',
    'en': 'English',
  };

  /// Langues déclarées par les pays mais pas encore traduites.
  static const _fallbacks = {'ar': 'en', 'pt': 'en', 'es': 'en'};

  String _lang = 'fr';
  String get lang => _lang;
  bool get isRtl => _lang == 'ar';

  static String resolve(String? requested) {
    if (requested == null) return 'fr';
    if (supported.containsKey(requested)) return requested;
    return _fallbacks[requested] ?? 'fr';
  }

  void setLanguage(String? code) {
    final next = resolve(code);
    if (next == _lang) return;
    _lang = next;
    notifyListeners();
  }

  static String translate(String source) {
    if (instance._lang == 'fr') return source;
    return _en[source] ?? source;
  }

  // -------------------------------------------------------------- Anglais
  static const _en = <String, String>{
    // Accueil et authentification
    'Trouve un ouvrier près de chez toi, ou trouve du travail.':
        'Find a worker near you, or find work.',
    'Pseudo': 'Username',
    'Mot de passe': 'Password',
    'Se connecter': 'Sign in',
    'Créer un compte': 'Create account',
    'Créer mon compte': 'Create my account',
    'Entre ton pseudo et ton mot de passe': 'Enter your username and password',
    'Pseudo ou mot de passe incorrect': 'Wrong username or password',
    'Ce pseudo est déjà pris': 'That username is taken',
    'Au moins 3 caractères': 'At least 3 characters',
    'Au plus 24 caractères': 'At most 24 characters',
    'Lettres, chiffres, point et tiret bas seulement':
        'Letters, digits, dot and underscore only',
    'Mot de passe : 6 caractères minimum': 'Password: 6 characters minimum',
    'Entre ton nom': 'Enter your name',
    'Ton nom': 'Your name',
    'Tu viens pour…': "You're here to…",
    'Ton pays': 'Your country',
    "Détermine la langue de l'application et l'indicatif téléphonique.":
        'Sets the app language and the phone country code.',
    'Trouver un ouvrier': 'Find a worker',
    'Trouver du travail': 'Find work',
    "Chercher dans l'annuaire, publier des demandes. Gratuit.":
        'Browse the directory, post requests. Free.',
    'Être alerté des missions près de chez toi.':
        'Get alerts for jobs near you.',

    // Navigation
    'Chercher': 'Search',
    'Demandes': 'Requests',
    'Messages': 'Messages',
    'Compte': 'Account',
    'Missions': 'Jobs',
    'Mon compte': 'My account',
    'Alertes': 'Alerts',

    // Recherche d'ouvriers
    'Maçon, chauffeur, plombier…': 'Mason, driver, plumber…',
    'Disponibles': 'Available',
    'Aucun ouvrier trouvé': 'No worker found',
    'Nouveau': 'New',
    'Identité vérifiée': 'Verified identity',
    'EN AVANT': 'FEATURED',
    'Voir le numéro (gratuit)': 'Show number (free)',
    'Appeler': 'Call',
    'Message': 'Message',
    'Avis': 'Reviews',
    'missions': 'jobs',
    'expérience': 'experience',

    // Missions
    'Missions disponibles': 'Available jobs',
    'Mes métiers': 'My trades',
    'Urgent': 'Urgent',
    'Cette semaine': 'This week',
    'Flexible': 'Flexible',
    'Aucune mission pour le moment': 'No jobs right now',
    'Voir tous les métiers': 'See all trades',
    'Mission': 'Job',
    'Proposer mes services (gratuit)': 'Offer my services (free)',
    'Proposer mes services': 'Offer my services',
    'Candidature envoyée': 'Application sent',
    'Ton prix': 'Your price',
    'Envoyer': 'Send',
    'Annuler': 'Cancel',
    'Contact obtenu': 'Contact obtained',
    'Contact gratuit': 'Free contact',
    'Contacter le client': 'Contact the client',
    'Déjà postulé': 'Already applied',

    // Demandes côté client
    'Mes demandes': 'My requests',
    'Publier': 'Post',
    'Publier une demande': 'Post a request',
    'Aucune demande publiée': 'No request posted',
    'Quel métier ?': 'Which trade?',
    'Titre': 'Title',
    'Description': 'Description',
    'Ville': 'City',
    'Quartier': 'Neighbourhood',
    'Budget indicatif': 'Indicative budget',
    'Minimum': 'Minimum',
    'Maximum': 'Maximum',
    'Par heure': 'Per hour',
    'Par jour': 'Per day',
    'Forfait': 'Fixed price',
    'Quand ?': 'When?',
    'Candidatures': 'Applications',
    'Choisir': 'Choose',
    'Voir le profil': 'View profile',
    'Marquer la mission terminée': 'Mark job as complete',
    "Noter l'ouvrier": 'Rate the worker',
    'Ton commentaire (facultatif)': 'Your comment (optional)',
    'Plus tard': 'Later',
    'Merci pour ton avis': 'Thanks for your review',

    // Compte et coordonnées
    'Mes coordonnées': 'My contact details',
    'Téléphone, WhatsApp, email, position': 'Phone, WhatsApp, email, location',
    'Téléphone': 'Phone',
    'WhatsApp (facultatif, si différent)': 'WhatsApp (optional, if different)',
    'Email (facultatif)': 'Email (optional)',
    'Où tu te trouves': 'Where you are',
    'Ma position sur la carte': 'My location on the map',
    'Facultatif': 'Optional',
    'Utiliser ma position': 'Use my location',
    'Actualiser': 'Refresh',
    'Retirer': 'Remove',
    'Enregistrer': 'Save',
    'Coordonnées enregistrées': 'Contact details saved',
    'Entre un numéro valide': 'Enter a valid number',
    'Adresse email invalide': 'Invalid email address',
    'Disponible': 'Available',
    'Indisponible': 'Unavailable',
    'Mon profil ouvrier': 'My worker profile',
    'Métiers, tarifs, disponibilité': 'Trades, rates, availability',
    'Devenir ouvrier': 'Become a worker',
    'Mes crédits': 'My credits',
    'Se déconnecter': 'Sign out',
    'Langue': 'Language',
    'Administration': 'Administration',
    'Une phrase sur toi': 'One line about you',
    "Années d'expérience": 'Years of experience',
    'Tes métiers': 'Your trades',
    'Ton tarif': 'Your rate',
    'De': 'From',
    'À': 'To',
    'Choisis au moins un métier': 'Pick at least one trade',
    'Profil enregistré': 'Profile saved',

    // Messagerie
    'Aucune conversation': 'No conversation',
    'Écris ton message…': 'Write your message…',
    'Lance la conversation': 'Start the conversation',

    // Divers
    'À négocier': 'Negotiable',
    "à l'instant": 'just now',
    'Aucune alerte': 'No alerts',
    "Une erreur est survenue. Vérifie ta connexion.":
        'Something went wrong. Check your connection.',
  };
}

extension Tr on String {
  /// Traduction dans la langue courante, ou la chaîne française d'origine.
  String get tr => L.translate(this);
}
