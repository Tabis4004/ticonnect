import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Clé de signature de publication.
//
// key.properties et le .jks ne sont pas versionnés (voir .gitignore) : perdre
// la clé d'upload oblige à passer par une réinitialisation chez Google, et la
// diffuser permettrait à un tiers de publier une mise à jour de l'application.
// Voir android/key.properties.example pour le format attendu.
//
// Absente, le build release retombe sur la clé de debug : `flutter run
// --release` continue de marcher sur un poste qui n'a pas la clé, mais l'AAB
// produit serait refusé par la Play Console.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// App ID AdMob.
//
// Le SDK Google Mobile Ads lit cette valeur dans le manifeste depuis un
// ContentProvider qui s'exécute AVANT le premier écran : un ID absent ou mal
// formé fait planter l'application au démarrage, sans que le code Dart puisse
// intercepter quoi que ce soit. La valeur doit donc toujours être valide, même
// avant d'avoir un compte AdMob configuré.
//
// Par défaut on utilise l'App ID de test publié par Google : l'application
// démarre et se publie normalement, sans jamais servir de vraie publicité.
// Pour passer en production, créer android/admob.properties (non versionné,
// voir admob.properties.example) ou lancer ./set_admob_app_id.sh.
val admobProperties = Properties()
val admobPropertiesFile = rootProject.file("admob.properties")
if (admobPropertiesFile.exists()) {
    admobPropertiesFile.inputStream().use { admobProperties.load(it) }
}
val admobAppId: String =
    admobProperties.getProperty("admobAppId")?.takeIf { it.isNotBlank() }
        ?: "ca-app-pub-3940256099942544~3347511713"

android {
    namespace = "com.ticonnect.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ticonnect.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["admobAppId"] = admobAppId
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storePassword = keystoreProperties.getProperty("storePassword")
            // Chemin relatif à android/ s'il n'est pas absolu, pour que
            // key.properties reste portable d'un poste à l'autre.
            keystoreProperties.getProperty("storeFile")?.let {
                storeFile = rootProject.file(it)
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
