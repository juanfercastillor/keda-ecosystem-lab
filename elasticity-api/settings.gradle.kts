plugins {
    // Permite que Gradle descargue automáticamente el JDK 25 (toolchain)
    // si la máquina local no lo tiene instalado.
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

rootProject.name = "elasticity-api"
