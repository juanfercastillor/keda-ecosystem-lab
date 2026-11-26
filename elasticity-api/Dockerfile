# syntax=docker/dockerfile:1

# ---------- Etapa 1: compilación ----------
FROM docker.io/library/gradle:9-jdk25 AS build
WORKDIR /home/gradle/app

# Redes sin ruta IPv6 (podman/WSL, VPN): Java debe preferir direcciones IPv4
# para resolver dependencias de Gradle durante el build.
ENV JAVA_TOOL_OPTIONS="-Djava.net.preferIPv4Addresses=true"

COPY build.gradle.kts settings.gradle.kts gradle.properties ./
RUN gradle --no-daemon dependencies

COPY src ./src
RUN gradle --no-daemon bootJar -x test

# ---------- Etapa 2: ejecución ----------
FROM docker.io/library/eclipse-temurin:25-jre
WORKDIR /app

RUN useradd --system --uid 1001 appuser
USER appuser

COPY --from=build /home/gradle/app/build/libs/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
