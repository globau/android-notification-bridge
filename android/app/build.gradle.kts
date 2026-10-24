import java.util.Properties

plugins {
    id("com.android.application")
}

val localProps = Properties().also { props ->
    rootProject.file("local.properties").takeIf { it.exists() }?.reader()?.use(props::load)
}

val appVersion = rootProject.file("../VERSION").readText().trim()

android {
    namespace = "au.glob.notificationbridge"
    compileSdk {
        version = release(37) { minorApiLevel = 2 }
    }

    defaultConfig {
        applicationId = "au.glob.notificationbridge"
        minSdk = 34
        targetSdk = 37
        versionCode = appVersion.split(".").map(String::toInt).let { (major, minor, patch) ->
            major * 10000 + minor * 100 + patch
        }
        versionName = appVersion
    }

    signingConfigs {
        create("release") {
            storeFile = rootProject.file("../release-keystore.jks")
            storePassword = localProps.getProperty("KEYSTORE_PASS")
            keyAlias = "release"
            keyPassword = localProps.getProperty("KEY_PASS")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    // the android.jar org.json is a stub in local unit tests
    testImplementation("org.json:json:20250517")
}
