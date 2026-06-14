ThisBuild / organization := "com.example"
ThisBuild / version      := "0.1.0-SNAPSHOT"
ThisBuild / scalaVersion := "2.13.14"

ThisBuild / scalacOptions += "-Xsource:3"

val catsEffectVersion = "3.5.3"
val logbackVersion    = "1.4.14"
val sparkVersion      = "3.5.1"

val catsEffect = Seq("org.typelevel" %% "cats-effect" % catsEffectVersion)
val logging    = Seq("ch.qos.logback" % "logback-classic" % logbackVersion)
val spark = Seq(
  "org.apache.spark" %% "spark-core" % sparkVersion % "provided",
  "org.apache.spark" %% "spark-sql"  % sparkVersion % "provided"
)
val hadoop = Seq(
  "org.apache.hadoop"  % "hadoop-aws"         % "3.3.4",
  "com.amazonaws"      % "aws-java-sdk-bundle" % "1.12.262"
)
val kafka = Seq("org.apache.kafka" % "kafka-clients" % "3.7.0")
val mongo = Seq("org.mongodb.spark" %% "mongo-spark-connector" % "10.3.0")

lazy val domain = project
  .in(file("domain/model"))
  .settings(name := "domain", libraryDependencies ++= catsEffect ++ spark)

lazy val useCases = project
  .in(file("application/use-cases"))
  .settings(name := "use-cases", libraryDependencies ++= catsEffect ++ spark)
  .dependsOn(domain)

lazy val drivenAdapters = project
  .in(file("infrastructure/driven-adapters"))
  .settings(
    name := "driven-adapters",
    libraryDependencies ++= catsEffect ++ spark ++ hadoop ++ kafka ++ mongo
  )
  .dependsOn(domain)

lazy val entryPoints = project
  .in(file("infrastructure/entry-points"))
  .settings(
    name := "entry-points",
    libraryDependencies ++= Seq(
      "org.apache.spark" %% "spark-core" % sparkVersion,
      "org.apache.spark" %% "spark-sql"  % sparkVersion
    ) ++ logging,
    Compile / run / fork := true,
    Compile / run / baseDirectory := (ThisBuild / baseDirectory).value,
    Compile / run / javaOptions ++= Seq(
      "--add-opens=java.base/sun.nio.ch=ALL-UNNAMED",
      "--add-opens=java.base/java.nio=ALL-UNNAMED",
      "--add-opens=java.base/java.lang=ALL-UNNAMED",
      "--add-opens=java.base/java.lang.invoke=ALL-UNNAMED",
      "--add-opens=java.base/java.lang.reflect=ALL-UNNAMED",
      "--add-opens=java.base/java.io=ALL-UNNAMED",
      "--add-opens=java.base/java.net=ALL-UNNAMED",
      "--add-opens=java.base/java.util=ALL-UNNAMED",
      "--add-opens=java.base/java.util.concurrent=ALL-UNNAMED",
      "--add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED",
      "--add-opens=java.base/sun.nio.cs=ALL-UNNAMED",
      "--add-opens=java.base/sun.security.action=ALL-UNNAMED",
      "--add-opens=java.base/sun.util.calendar=ALL-UNNAMED",
      "--add-opens=java.security.jgss/sun.security.krb5=ALL-UNNAMED"
    ),
    Compile / run / mainClass := Some("com.example.reportetlservice.infrastructure.entrypoints.BatchMain"),
    assembly / mainClass := Some("com.example.reportetlservice.infrastructure.entrypoints.BatchMain"),
    assembly / assemblyMergeStrategy := {
      case PathList("META-INF", _ @ _*) => MergeStrategy.discard
      case _                            => MergeStrategy.first
    }
  )
  .dependsOn(useCases, drivenAdapters)

lazy val root = project
  .in(file("."))
  .aggregate(domain, useCases, drivenAdapters, entryPoints)
  .settings(name := "scala-hexagonal-architecture", publish / skip := true)
