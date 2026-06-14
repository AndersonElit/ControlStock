# Stage 1 — cachear dependencias SBT (capa separada → rebuilds más rápidos)
FROM sbtscala/scala-sbt:eclipse-temurin-17.0.10_7_1.9.8_2.13.14 AS builder
WORKDIR /app
COPY build.sbt .
COPY project/ project/
RUN sbt update

# Copiar fuentes y ensamblar fat JAR
COPY . .
RUN sbt "entryPoints/assembly"

# Stage 2 — runtime (JRE only; Spark runs embedded in local[*] mode)
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
COPY --from=builder /app/infrastructure/entry-points/target/scala-2.13/entry-points-assembly-*.jar app.jar

ENV SPARK_MASTER="local[*]"

ENTRYPOINT ["java",\
  "--add-opens=java.base/sun.nio.ch=ALL-UNNAMED",\
  "--add-opens=java.base/java.nio=ALL-UNNAMED",\
  "--add-opens=java.base/java.lang=ALL-UNNAMED",\
  "--add-opens=java.base/java.lang.invoke=ALL-UNNAMED",\
  "--add-opens=java.base/java.lang.reflect=ALL-UNNAMED",\
  "--add-opens=java.base/java.io=ALL-UNNAMED",\
  "--add-opens=java.base/java.net=ALL-UNNAMED",\
  "--add-opens=java.base/java.util=ALL-UNNAMED",\
  "--add-opens=java.base/java.util.concurrent=ALL-UNNAMED",\
  "--add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED",\
  "--add-opens=java.base/sun.nio.cs=ALL-UNNAMED",\
  "--add-opens=java.base/sun.security.action=ALL-UNNAMED",\
  "--add-opens=java.base/sun.util.calendar=ALL-UNNAMED",\
  "--add-opens=java.security.jgss/sun.security.krb5=ALL-UNNAMED",\
  "-jar","app.jar"]
