# Règles R8 pour la build release.
#
# Elles ne servent qu'en release : la build debug ne minifie pas, ce qui
# explique qu'un crash puisse n'apparaître que sur l'APK distribué.

# WorkManager, tiré par le SDK Google Mobile Ads via androidx.startup.
#
# WorkManager stocke son état dans une base Room. Room n'instancie jamais
# WorkDatabase_Impl directement : il en construit le nom à l'exécution et
# passe par la réflexion. R8 ne voit donc aucun appelant et, en mode full
# (le défaut depuis AGP 8, encore plus agressif sur AGP 9), supprime le
# constructeur sans argument tout en gardant la classe.
#
# Room lève alors « Failed to create an instance of
# androidx.work.impl.WorkDatabase » depuis le ContentProvider
# androidx.startup.InitializationProvider, c'est-à-dire avant le premier
# écran : l'application plante au lancement sans que Dart s'exécute.
#
# Garder la classe seule ne suffit pas, il faut ses membres.
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# Même raisonnement pour les Worker : WorkManager les instancie par
# réflexion à partir du nom enregistré en base, via ce constructeur précis.
-keep class * extends androidx.work.ListenableWorker {
    <init>(android.content.Context, androidx.work.WorkerParameters);
}
