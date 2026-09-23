pluginManagement {
  val parentLocal = file("../../../local.properties")
  if (parentLocal.exists() && !file("local.properties").exists()) {
    parentLocal.copyTo(file("local.properties"))
  }
  repositories {
    google()
    mavenCentral()
    gradlePluginPortal()
  }
}

plugins {
  id("com.android.application") version "8.11.1" apply false
  id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories {
    google()
    mavenCentral()
  }
}

rootProject.name = "tsnet-spike"
include(":app")
