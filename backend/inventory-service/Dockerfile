# ── Build stage ────────────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21-alpine AS builder
WORKDIR /app

# Copy pom files first to leverage Docker layer caching for dependencies
COPY pom.xml .
COPY domain/model/pom.xml domain/model/
COPY application/use-cases/pom.xml application/use-cases/
COPY infrastructure/driven-adapters/postgres/pom.xml infrastructure/driven-adapters/postgres/
COPY infrastructure/entry-points/rest-api/pom.xml infrastructure/entry-points/rest-api/
COPY infrastructure/entry-points/app/pom.xml infrastructure/entry-points/app/
COPY infrastructure/driven-adapters/outbox/pom.xml infrastructure/driven-adapters/outbox/
COPY infrastructure/driven-adapters/kafka-producer/pom.xml infrastructure/driven-adapters/kafka-producer/
COPY infrastructure/entry-points/kafka-consumer/pom.xml infrastructure/entry-points/kafka-consumer/
RUN mvn dependency:go-offline -B --no-transfer-progress

# Copy source and build
COPY . .
RUN mvn clean package -DskipTests --no-transfer-progress

# ── Runtime stage ───────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/infrastructure/entry-points/app/target/*.jar app.jar
EXPOSE 8083
ENTRYPOINT ["java", "-jar", "app.jar"]
