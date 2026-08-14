pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // Lit android/app/google-services.json et en dérive les identifiants
    // Firebase à la compilation. Sans ce plugin, `Firebase.initializeApp()`
    // échoue au démarrage avec une erreur peu parlante sur l'option
    // « google_app_id » manquante.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
