plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.android")
}

android {
  namespace = "com.chenweikeng.monkeycraft.tsnetspike"
  compileSdk = 36
  ndkVersion = "28.2.13676358"

  defaultConfig {
    applicationId = "com.chenweikeng.monkeycraft.tsnetspike"
    minSdk = 24
    targetSdk = 36
    versionCode = 1
    versionName = "0.1-spike"
    ndk {
      abiFilters += listOf("armeabi-v7a", "arm64-v8a")
    }
    externalNativeBuild {
      cmake {
        arguments += listOf(
          "-DANDROID_STL=none",
          "-DLIBTAILSCALE_OUT=${rootProject.projectDir}/../out",
        )
      }
    }
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
  kotlin {
    compilerOptions {
      jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
  }

  sourceSets {
    getByName("main") {
      jniLibs.srcDir("../../out")
    }
  }

  externalNativeBuild {
    cmake {
      path = file("src/main/cpp/CMakeLists.txt")
    }
  }

  buildTypes {
    release {
      isMinifyEnabled = false
    }
  }
}

dependencies {
  implementation("androidx.core:core-ktx:1.16.0")
  implementation("androidx.appcompat:appcompat:1.7.1")
}
