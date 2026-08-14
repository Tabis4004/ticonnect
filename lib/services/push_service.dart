import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'devices_service.dart';

/// Notifications push.
///
/// Quatre maillons, et chacun est indispensable :
///   1. Firebase initialisé depuis `google-services.json`
///   2. la permission de l'utilisateur
///   3. le jeton enregistré dans `devices`
///   4. l'Edge Function `send-push`, déclenchée par la base
///
/// Ce fichier couvre les trois premiers. Sans le quatrième, un jeton bien
/// enregistré ne fait toujours rien sonner — c'est le maillon qu'on oublie
/// le plus souvent.
///
/// Rien ici ne doit faire échouer le démarrage : une permission refusée,
/// un Firebase mal configuré ou un réseau absent laissent l'application
/// parfaitement utilisable, simplement sans notification.
class PushService {
  static const _channel = AndroidNotificationChannel(
    'ticonnect',
    'TiConnect',
    description: 'Missions, messages et propositions',
    importance: Importance.high,
  );

  static final _local = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    // AdMob n'existe pas sur le web, Firebase Messaging non plus dans cette
    // configuration : on sort avant d'importer quoi que ce soit de lourd.
    if (kIsWeb || _ready) return;

    try {
      await Firebase.initializeApp();

      // Le canal doit exister avant la première notification, sinon
      // Android la classe en importance basse et elle n'apparaît pas en
      // bannière.
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _ready = true;
        return;
      }

      final token = await messaging.getToken();
      if (token != null) await DevicesService.register(token);

      // Le jeton change : réinstallation, restauration, effacement des
      // données. Sans cette écoute, l'appareil devient injoignable en
      // silence après l'un de ces événements.
      messaging.onTokenRefresh.listen(DevicesService.register);

      // Application au premier plan : Android n'affiche rien de lui-même,
      // c'est à nous de le faire.
      FirebaseMessaging.onMessage.listen(_showForeground);

      _ready = true;
    } catch (e) {
      // Firebase absent ou mal configuré : l'application continue.
      debugPrint('PushService indisponible : $e');
    }
  }

  static Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    if (n == null) return;

    await _local.show(
      m.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  /// À appeler à la déconnexion.
  ///
  /// Le partage d'un téléphone entre plusieurs personnes est la norme sur
  /// ce marché, pas l'exception : laisser le jeton en place enverrait les
  /// messages du compte précédent à quiconque se connecte ensuite.
  static Future<void> forget() async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await DevicesService.unregister(token);
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
