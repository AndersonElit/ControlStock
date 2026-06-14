#!/usr/bin/env bash

# ===========================================================================
# scaffold-all-services.sh — Generar el scaffolding de microservicios
#                            (backend Spring Boot hexagonal) y frontend Next.js
#
# Prerrequisitos:
#   - Python 3 disponible
#   - Los templates .claude/templates/maven_hexagonal_scaffold.py y
#     .claude/templates/nextjs_feature_scaffold.py deben existir
#
# Qué hace:
#   1. Verifica prerequisitos (python3, templates)
#   2. Crea el directorio backend/ y frontend/
#   3. Backend — genera microservicios Spring Boot hexagonal
#   4. Frontend — genera proyecto Next.js feature-based
#   5. PostgreSQL — genera changelogs Liquibase iniciales en db/<svc>/changelog/
#   6. iam-service — genera 00002_seed_roles.yaml en db/iam-service/changelog/
#   7. Checklist de verificación de directorios y changelogs generados
# ===========================================================================

set -euo pipefail

log()     { echo "[$(date '+%H:%M:%S')] $*"; }
log_ok()  { echo "[$(date '+%H:%M:%S')] OK  $*"; }
log_err() { echo "[$(date '+%H:%M:%S')] ERR $*" >&2; }
log_warn(){ echo "[$(date '+%H:%M:%S')] WRN $*"; }

BOLD="\033[1m"
RESET="\033[0m"
HEADER() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEMPLATES_DIR="$REPO_ROOT/.claude/templates"
MAVEN_TEMPLATE="$TEMPLATES_DIR/maven_hexagonal_scaffold.py"
NEXTJS_TEMPLATE="$TEMPLATES_DIR/nextjs_feature_scaffold.py"
INTEGRATION_TEMPLATE="$TEMPLATES_DIR/integration_service_scaffold.py"
SCALA_TEMPLATE="$TEMPLATES_DIR/scala_hexagonal_scaffold.py"
REPORT_LAMBDAS_TEMPLATE="$TEMPLATES_DIR/report_lambdas_scaffold.py"

BACKEND_DIR="$REPO_ROOT/backend"
FRONTEND_DIR="$REPO_ROOT/frontend"

SCHEMA_FILES=("$REPO_ROOT/docs/design/database"/*.sql)
SCHEMA_SQL="${SCHEMA_FILES[0]}"
SCHEMA_BASENAME="$(basename "$SCHEMA_SQL" 2>/dev/null || echo "schema.sql")"
REST_MODULE="rest-api"

# ──────────────────────────────────────────────────────────────────────────────
# Argumentos de línea de comandos
#
# --backend nombre:db:messaging:puerto   (repetible, obligatorio)
#   Define un microservicio backend con su base de datos, mensajería y puerto.
#   Se puede usar tantas veces como servicios se desee generar.
#   Ejemplo:
#     --backend iam-service:postgres:none:8081
#
# --frontend nombre                       (opcional)
#   Nombre del proyecto frontend Next.js a generar.
#   Si se omite, no se genera frontend.
#   Ejemplo:
#     --frontend miproyecto-web
#
# --bc-tags servicio=TAG                  (repetible, opcional)
#   Mapea un microservicio PostgreSQL a su tag en el schema.sql para generar
#   los changelogs Liquibase iniciales. Si se omite, no se generan changelogs.
#   Ejemplo:
#     --bc-tags clientes-service=BC-01
# ──────────────────────────────────────────────────────────────────────────────
BACKEND_SERVICES=()
FRONTEND_NAME=""
HAS_FRONTEND=0
declare -A BC_TAGS
# Camel / Saga
INTEGRATION_SYSTEMS=""      # valor de --integration-service: "buro=BC-01,pasarela=BC-02"
HAS_INTEGRATION=0
INTEGRATION_NAME="integration-service"
INTEGRATION_PORT="8090"
SAGA_FLOWS=""               # valor de --saga-flows: "originacion,desembolso"
declare -A OUTBOX_SERVICES        # --outbox <servicio>
declare -A SAGA_PARTICIPANTS      # --saga-participant <servicio>
# Reportería (ETL Spark + lambdas de formato)
REPORT_EXTRACTION=()              # --report-extraction <svc>:<source>:<topic-out>
REPORT_PROCESSING=()              # --report-processing <svc>:<topic-in>:<topic-out>
REPORT_TYPES=""                   # --report-types ventas-mensual,saldos
REPORT_FORMATS=""                 # --report-formats pdf,xls,csv
REPORT_SCHEDULE="0 * * * *"      # --report-schedule CRON (CronJob K8s, default: cada hora)
PROJECT_NAME=""
PG_DB_NAME=""
MONGO_DB_NAME=""
DB_USER=""
DB_PASSWORD=""
VPS_IP=""
MIGRATIONS_REPO=""

usage() {
  cat <<EOF
Uso: $0 -P <proyecto> --backend nombre:db:messaging:puerto [--backend ...] \
        -p <pg-db> -m <mongo-db> -u <usuario> -w <clave> \
        [--frontend nombre] [--bc-tags servicio=TAG ...]

  -P, --project NOMBRE   Slug del proyecto. Se propaga como --org a los templates
                         (organización Gitea, prefijo de secrets, path del recurso
                         de la shared library). (obligatorio)

  --backend   Par nombre:db:messaging:puerto. Repetir una vez por servicio (obligatorio).
              db       = postgres | mongo
              messaging = none | kafka-producer | kafka-consumer | rabbit-producer | rabbit-consumer
              puerto   = número de puerto HTTP

  -p, --pg-db    NOMBRE   Base de datos PostgreSQL (obligatorio)
  -m, --mongo-db NOMBRE   Base de datos MongoDB    (obligatorio)
  -u, --user     NOMBRE   Usuario de aplicación    (obligatorio)
  -w, --password CLAVE    Clave del usuario         (obligatorio)
  --vps-ip       IP       IP del VPS donde corren los servicios systemd.
                          Se propaga a create-all-secrets-dev.sh, run-liquibase-migrations.sh
                          y las verificaciones de servicios en K3s. (obligatorio)

  --frontend  Nombre del proyecto frontend Next.js (opcional).
              Si se omite, no se genera frontend.

  --integration-service "sis=BC-XX,..."  (opcional)
              Genera el integration-service (Apache Camel + orquestador de saga LRA),
              con una ruta Camel por sistema externo. El valor mapea sistema=bounded-context.
  --saga-flows flujo1,flujo2             (opcional) Un orquestador de saga por flujo.
  --integration-port PUERTO              (opcional) Puerto del integration-service (default: 8090).
  --outbox SERVICIO                      (opcional, repetible) Añade Transactional Outbox al servicio.
  --saga-participant SERVICIO            (opcional, repetible) Marca el servicio como participante
              de saga (endpoint de compensación + processed_message); implica --outbox.

  --bc-tags   Par servicio=BC-XX (opcional, repetible).
              Mapea un servicio PostgreSQL a su tag en el schema.sql para
              generar el changelog Liquibase inicial (00001_initial_schema.yaml).

  --migrations-repo PATH  (opcional)
              Ruta local donde se generan los changelogs Liquibase antes del push.
              Si se omite: se usa <repo_root>/db/.
              En ambos casos se crea el repo <project>-migrations en Gitea (VPS_IP:3000)
              y se hace push automático del schema inicial.

  --report-extraction <svc>:<source>:<topic-out>   (opcional, repetible)
              Genera el report-extraction-service (MS1, Spark) con scala_hexagonal_scaffold.py
              --report-role extraction. source = mongo (read model CQRS, default) | jdbc.
  --report-processing <svc>:<topic-in>:<topic-out> (opcional, repetible)
              Genera el report-processing-service (MS2, Spark) --report-role processing.
  --report-types lista,csv                         (opcional)
              Tipos de reporte de MS2: un ReportTransformer + registro por tipo (Factory, DR-10).
  --report-formats pdf,xls,csv                     (opcional)
              Genera la capa serverless (lambdas PDF/XLS/CSV + Kafka consumer + Terraform EventBridge).
  --report-schedule "CRON"                          (opcional)
              Expresión cron del CronJob K8s para los batch jobs Spark.
              Default: "0 * * * *" (cada hora). Ej: "0 2 * * *" = 2 AM diario.

Ejemplo:
  bash $0 \\
    -P miproyecto \\
    --backend iam-service:postgres:none:8081 \\
    --backend clientes-service:postgres:kafka-producer:8082 \\
    --backend configuracion-service:postgres:kafka-producer:8083 \\
    -p miproyecto_dev -m miproyecto_audit \\
    -u appuser -w secret123 \\
    --frontend miproyecto-web \\
    --bc-tags clientes-service=BC-01 \\
    --bc-tags configuracion-service=BC-02

EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -P|--project)
      if [[ -z "${2:-}" ]]; then
        log_err "--project requiere un valor (slug del proyecto)."
        exit 1
      fi
      PROJECT_NAME="$2"
      shift 2
      ;;
    --project=*)
      PROJECT_NAME="${1#*=}"
      shift
      ;;
    --backend)
      if [[ -z "${2:-}" ]]; then
        log_err "--backend requiere un valor (nombre:db:messaging:puerto)."
        exit 1
      fi
      BACKEND_SERVICES+=("$2")
      shift 2
      ;;
    --backend=*)
      VAL="${1#*=}"
      if [[ -z "$VAL" ]]; then
        log_err "--backend requiere un valor (nombre:db:messaging:puerto)."
        exit 1
      fi
      BACKEND_SERVICES+=("$VAL")
      shift
      ;;
    --frontend)
      if [[ -z "${2:-}" ]]; then
        log_err "--frontend requiere un valor (nombre del proyecto)."
        exit 1
      fi
      FRONTEND_NAME="$2"
      HAS_FRONTEND=1
      shift 2
      ;;
    --frontend=*)
      FRONTEND_NAME="${1#*=}"
      if [[ -z "$FRONTEND_NAME" ]]; then
        log_err "--frontend requiere un valor (nombre del proyecto)."
        exit 1
      fi
      HAS_FRONTEND=1
      shift
      ;;
    --bc-tags)
      if [[ -z "${2:-}" ]]; then
        log_err "--bc-tags requiere un valor (servicio=TAG)."
        exit 1
      fi
      PAIR="$2"
      SERVICE="${PAIR%%=*}"
      TAG="${PAIR#*=}"
      if [[ -z "$SERVICE" || -z "$TAG" || "$SERVICE" == "$TAG" ]]; then
        log_err "Formato inválido en --bc-tags: '$PAIR' (esperado servicio=TAG)"
        exit 1
      fi
      BC_TAGS["$SERVICE"]="$TAG"
      shift 2
      ;;
    --bc-tags=*)
      PAIR="${1#*=}"
      SERVICE="${PAIR%%=*}"
      TAG="${PAIR#*=}"
      if [[ -z "$SERVICE" || -z "$TAG" || "$SERVICE" == "$TAG" ]]; then
        log_err "Formato inválido en --bc-tags: '$PAIR' (esperado servicio=TAG)"
        exit 1
      fi
      BC_TAGS["$SERVICE"]="$TAG"
      shift
      ;;
    -p|--pg-db)
      if [[ -z "${2:-}" ]]; then
        log_err "--pg-db requiere un valor (nombre de la base de datos PostgreSQL)."
        exit 1
      fi
      PG_DB_NAME="$2"
      shift 2
      ;;
    --pg-db=*)
      PG_DB_NAME="${1#*=}"
      shift
      ;;
    -m|--mongo-db)
      if [[ -z "${2:-}" ]]; then
        log_err "--mongo-db requiere un valor (nombre de la base de datos MongoDB)."
        exit 1
      fi
      MONGO_DB_NAME="$2"
      shift 2
      ;;
    --mongo-db=*)
      MONGO_DB_NAME="${1#*=}"
      shift
      ;;
    -u|--user)
      if [[ -z "${2:-}" ]]; then
        log_err "--user requiere un valor (usuario de aplicación)."
        exit 1
      fi
      DB_USER="$2"
      shift 2
      ;;
    --user=*)
      DB_USER="${1#*=}"
      shift
      ;;
    -w|--password)
      if [[ -z "${2:-}" ]]; then
        log_err "--password requiere un valor (clave del usuario)."
        exit 1
      fi
      DB_PASSWORD="$2"
      shift 2
      ;;
    --password=*)
      DB_PASSWORD="${1#*=}"
      shift
      ;;
    --integration-service)
      if [[ -z "${2:-}" ]]; then
        log_err "--integration-service requiere un valor (\"sistema=BC-XX,...\")."
        exit 1
      fi
      INTEGRATION_SYSTEMS="$2"
      HAS_INTEGRATION=1
      shift 2
      ;;
    --integration-service=*)
      INTEGRATION_SYSTEMS="${1#*=}"
      HAS_INTEGRATION=1
      shift
      ;;
    --integration-port)
      INTEGRATION_PORT="${2:?--integration-port requiere un valor}"
      shift 2
      ;;
    --integration-port=*)
      INTEGRATION_PORT="${1#*=}"
      shift
      ;;
    --saga-flows)
      SAGA_FLOWS="${2:?--saga-flows requiere un valor (flujo1,flujo2)}"
      shift 2
      ;;
    --saga-flows=*)
      SAGA_FLOWS="${1#*=}"
      shift
      ;;
    --outbox)
      OUTBOX_SERVICES["${2:?--outbox requiere el nombre del servicio}"]=1
      shift 2
      ;;
    --outbox=*)
      OUTBOX_SERVICES["${1#*=}"]=1
      shift
      ;;
    --saga-participant)
      SVC="${2:?--saga-participant requiere el nombre del servicio}"
      SAGA_PARTICIPANTS["$SVC"]=1
      OUTBOX_SERVICES["$SVC"]=1   # un participante de saga publica eventos vía outbox
      shift 2
      ;;
    --saga-participant=*)
      SVC="${1#*=}"
      SAGA_PARTICIPANTS["$SVC"]=1
      OUTBOX_SERVICES["$SVC"]=1
      shift
      ;;
    --report-extraction)
      REPORT_EXTRACTION+=("${2:?--report-extraction requiere <svc>:<source>:<topic-out>}")
      shift 2
      ;;
    --report-extraction=*)
      REPORT_EXTRACTION+=("${1#*=}")
      shift
      ;;
    --report-processing)
      REPORT_PROCESSING+=("${2:?--report-processing requiere <svc>:<topic-in>:<topic-out>}")
      shift 2
      ;;
    --report-processing=*)
      REPORT_PROCESSING+=("${1#*=}")
      shift
      ;;
    --report-types)
      REPORT_TYPES="${2:?--report-types requiere una lista CSV}"
      shift 2
      ;;
    --report-types=*)
      REPORT_TYPES="${1#*=}"
      shift
      ;;
    --report-formats)
      REPORT_FORMATS="${2:?--report-formats requiere una lista CSV (pdf,xls,csv)}"
      shift 2
      ;;
    --report-formats=*)
      REPORT_FORMATS="${1#*=}"
      shift
      ;;
    --report-schedule)
      REPORT_SCHEDULE="${2:?--report-schedule requiere una expresión cron entre comillas}"
      shift 2
      ;;
    --report-schedule=*)
      REPORT_SCHEDULE="${1#*=}"
      shift
      ;;
    --vps-ip)
      VPS_IP="${2:?--vps-ip requiere una IP}"
      shift 2
      ;;
    --vps-ip=*)
      VPS_IP="${1#*=}"
      shift
      ;;
    --migrations-repo)
      MIGRATIONS_REPO="${2:?--migrations-repo requiere una ruta}"
      shift 2
      ;;
    --migrations-repo=*)
      MIGRATIONS_REPO="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      log_err "Argumento desconocido: $1"
      usage
      ;;
  esac
done

MISSING_ARGS=()
[[ -z "$PROJECT_NAME" ]] && MISSING_ARGS+=("-P/--project")
[[ "${#BACKEND_SERVICES[@]}" -eq 0 ]] && MISSING_ARGS+=("--backend")
[[ -z "$PG_DB_NAME"    ]] && MISSING_ARGS+=("-p/--pg-db")
[[ -z "$MONGO_DB_NAME" ]] && MISSING_ARGS+=("-m/--mongo-db")
[[ -z "$DB_USER"       ]] && MISSING_ARGS+=("-u/--user")
[[ -z "$DB_PASSWORD"   ]] && MISSING_ARGS+=("-w/--password")
[[ -z "$VPS_IP"        ]] && MISSING_ARGS+=("--vps-ip")

if [[ ${#MISSING_ARGS[@]} -gt 0 ]]; then
  log_err "Faltan parámetros obligatorios: ${MISSING_ARGS[*]}"
  log_err "Ejecute con --help para ver la ayuda."
  exit 1
fi

MIGRATIONS_REPO_DIR="${MIGRATIONS_REPO:-$REPO_ROOT/db}"

log "Servicios backend: ${#BACKEND_SERVICES[@]} definidos."
if [[ "$HAS_FRONTEND" -eq 1 ]]; then
  log "Frontend: $FRONTEND_NAME"
else
  log "Frontend: omitido (no se especificó --frontend)."
fi
if [[ "${#BC_TAGS[@]}" -gt 0 ]]; then
  log "BC_TAGS: ${#BC_TAGS[@]} servicios para changelogs Liquibase."
else
  log "BC_TAGS: omitidos (no se generarán changelogs Liquibase iniciales)."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 1. Validación de prerequisitos
# ──────────────────────────────────────────────────────────────────────────────
HEADER "1. Verificando prerequisitos"

if ! command -v python3 &>/dev/null; then
  log_err "python3 no está instalado. Abortando."
  exit 1
fi
log_ok "python3 encontrado ($(command -v python3))."

if [[ ! -f "$MAVEN_TEMPLATE" ]]; then
  log_err "Template no encontrado: $MAVEN_TEMPLATE"
  exit 1
fi
log_ok "Template Maven hexagonal encontrado: $MAVEN_TEMPLATE"

if [[ "$HAS_FRONTEND" -eq 1 ]]; then
  if [[ ! -f "$NEXTJS_TEMPLATE" ]]; then
    log_err "Template no encontrado: $NEXTJS_TEMPLATE"
    exit 1
  fi
  log_ok "Template Next.js encontrado: $NEXTJS_TEMPLATE"
else
  log "Template Next.js: omitido (no se generará frontend)."
fi

# Validar formato de cada --backend
for svc_spec in "${BACKEND_SERVICES[@]}"; do
  IFS=':' read -r name db messaging port <<< "$svc_spec"
  if [[ -z "$name" || -z "$db" || -z "$messaging" || -z "$port" ]]; then
    log_err "Formato inválido en --backend: '$svc_spec' (esperado nombre:db:messaging:puerto)."
    exit 1
  fi
done

# ──────────────────────────────────────────────────────────────────────────────
# 2. Crear directorios base
# ──────────────────────────────────────────────────────────────────────────────
HEADER "2. Creando directorios backend/ y frontend/"

mkdir -p "$BACKEND_DIR"
log_ok "Directorio backend/ creado: $BACKEND_DIR"

if [[ "$HAS_FRONTEND" -eq 1 ]]; then
  mkdir -p "$FRONTEND_DIR"
  log_ok "Directorio frontend/ creado: $FRONTEND_DIR"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3. Generar scaffolding de microservicios backend
# ──────────────────────────────────────────────────────────────────────────────
HEADER "3. Generando microservicios Spring Boot (${#BACKEND_SERVICES[@]} servicios)"

BACKEND_FAILED=()

for svc_spec in "${BACKEND_SERVICES[@]}"; do
  IFS=':' read -r name db messaging port <<< "$svc_spec"

  if [[ -d "$BACKEND_DIR/$name" ]]; then
    log_warn "$name — directorio ya existe; omitiendo."
    continue
  fi

  EXTRA_FLAGS=()
  [[ -n "${OUTBOX_SERVICES[$name]:-}" ]] && EXTRA_FLAGS+=("--outbox")
  [[ -n "${SAGA_PARTICIPANTS[$name]:-}" ]] && EXTRA_FLAGS+=("--saga-participant")

  log "Generando $name (db=$db, messaging=$messaging, port=$port${EXTRA_FLAGS:+, ${EXTRA_FLAGS[*]}})..."
  # Database-per-Service: pasar prefijos para que el script generado derive la BD
  # correcta (<prefix>_<servicio_slug>), consistente con init-databases.sh.
  if (cd "$BACKEND_DIR" && python3 "$MAVEN_TEMPLATE" -n "$name" -d "$db" -m "$messaging" -p "$port" \
        --org "$PROJECT_NAME" \
        --pg-db "$PG_DB_NAME" --mongo-db "$MONGO_DB_NAME" \
        --migrations-dir "$MIGRATIONS_REPO_DIR" \
        "${EXTRA_FLAGS[@]}"); then
    log_ok "$name generado."
  else
    log_err "$name — falló la generación."
    BACKEND_FAILED+=("$name")
  fi
done

# ──────────────────────────────────────────────────────────────────────────────
# 3b. Generar el integration-service (capa de integración Camel + orquestador de saga)
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$HAS_INTEGRATION" -eq 1 ]]; then
  HEADER "3b. Generando integration-service (Apache Camel + Saga EIP/LRA)"
  if [[ ! -f "$INTEGRATION_TEMPLATE" ]]; then
    log_err "Template no encontrado: $INTEGRATION_TEMPLATE"
    BACKEND_FAILED+=("$INTEGRATION_NAME")
  elif [[ -d "$BACKEND_DIR/$INTEGRATION_NAME" ]]; then
    log_warn "$INTEGRATION_NAME — directorio ya existe; omitiendo."
  else
    log "Generando $INTEGRATION_NAME (externos='$INTEGRATION_SYSTEMS', sagas='$SAGA_FLOWS', port=$INTEGRATION_PORT)..."
    if (cd "$BACKEND_DIR" && python3 "$INTEGRATION_TEMPLATE" \
          -n "$INTEGRATION_NAME" --org "$PROJECT_NAME" -p "$INTEGRATION_PORT" \
          --external-systems "$INTEGRATION_SYSTEMS" --saga-flows "$SAGA_FLOWS"); then
      log_ok "$INTEGRATION_NAME generado."
    else
      log_err "$INTEGRATION_NAME — falló la generación."
      BACKEND_FAILED+=("$INTEGRATION_NAME")
    fi
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3c. Reportería — ETL Spark (MS1/MS2) + capa serverless de formatos
# ──────────────────────────────────────────────────────────────────────────────
HAS_REPORTING=0
[[ ${#REPORT_EXTRACTION[@]} -gt 0 || ${#REPORT_PROCESSING[@]} -gt 0 || -n "$REPORT_FORMATS" ]] && HAS_REPORTING=1

if [[ "$HAS_REPORTING" -eq 1 ]]; then
  HEADER "3c. Reportería (Spark ETL + lambdas de formato)"

  # MS1 — report-extraction-service(s): <svc>:<source>:<topic-out>
  for spec in "${REPORT_EXTRACTION[@]}"; do
    IFS=':' read -r rname rsource rtopic_out <<< "$spec"
    rsource="${rsource:-mongo}"
    rtopic_out="${rtopic_out:-report.extracted}"
    if [[ -z "$rname" ]]; then
      log_err "Formato inválido en --report-extraction: '$spec' (esperado <svc>:<source>:<topic-out>)."
      BACKEND_FAILED+=("report-extraction")
      continue
    fi
    if [[ -d "$BACKEND_DIR/$rname" ]]; then
      log_warn "$rname — directorio ya existe; omitiendo."
    elif [[ ! -f "$SCALA_TEMPLATE" ]]; then
      log_err "Template no encontrado: $SCALA_TEMPLATE"
      BACKEND_FAILED+=("$rname")
    else
      log "Generando $rname (extraction, source=$rsource, out=$rtopic_out)..."
      if (cd "$BACKEND_DIR" && python3 "$SCALA_TEMPLATE" \
            --service-name "$rname" --report-role extraction \
            --source "$rsource" --kafka-out "$rtopic_out" \
            --org "$PROJECT_NAME" --schedule "$REPORT_SCHEDULE" \
            --pg-db "$PG_DB_NAME"); then
        log_ok "$rname generado."
      else
        log_err "$rname — falló la generación."
        BACKEND_FAILED+=("$rname")
      fi
    fi
  done

  # MS2 — report-processing-service(s): <svc>:<topic-in>:<topic-out>
  for spec in "${REPORT_PROCESSING[@]}"; do
    IFS=':' read -r rname rtopic_in rtopic_out <<< "$spec"
    rtopic_in="${rtopic_in:-report.extracted}"
    rtopic_out="${rtopic_out:-report.processed}"
    if [[ -z "$rname" ]]; then
      log_err "Formato inválido en --report-processing: '$spec' (esperado <svc>:<topic-in>:<topic-out>)."
      BACKEND_FAILED+=("report-processing")
      continue
    fi
    if [[ -d "$BACKEND_DIR/$rname" ]]; then
      log_warn "$rname — directorio ya existe; omitiendo."
    elif [[ ! -f "$SCALA_TEMPLATE" ]]; then
      log_err "Template no encontrado: $SCALA_TEMPLATE"
      BACKEND_FAILED+=("$rname")
    else
      log "Generando $rname (processing, in=$rtopic_in, out=$rtopic_out, types='$REPORT_TYPES')..."
      if (cd "$BACKEND_DIR" && python3 "$SCALA_TEMPLATE" \
            --service-name "$rname" --report-role processing \
            --kafka-in "$rtopic_in" --kafka-out "$rtopic_out" \
            --report-types "$REPORT_TYPES" \
            --org "$PROJECT_NAME" --schedule "$REPORT_SCHEDULE"); then
        log_ok "$rname generado."
      else
        log_err "$rname — falló la generación."
        BACKEND_FAILED+=("$rname")
      fi
    fi
  done

  # Capa serverless de formatos (lambdas + Terraform EventBridge)
  if [[ -n "$REPORT_FORMATS" ]]; then
    if [[ ! -f "$REPORT_LAMBDAS_TEMPLATE" ]]; then
      log_err "Template no encontrado: $REPORT_LAMBDAS_TEMPLATE"
      BACKEND_FAILED+=("reporting-lambdas")
    elif [[ -d "$REPO_ROOT/reporting-lambdas" ]]; then
      log_warn "reporting-lambdas/ ya existe; omitiendo capa serverless."
    else
      log "Generando capa serverless de formatos ($REPORT_FORMATS)..."
      if (cd "$REPO_ROOT" && python3 "$REPORT_LAMBDAS_TEMPLATE" \
            --org "$PROJECT_NAME" \
            --kafka-topic report.processed); then
        log_ok "reporting-lambdas/ generado."
      else
        log_err "reporting-lambdas — falló la generación."
        BACKEND_FAILED+=("reporting-lambdas")
      fi
    fi
  fi
else
  log "Reportería: omitida (sin --report-extraction/--report-processing/--report-formats)."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4. Generar scaffolding frontend
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$HAS_FRONTEND" -eq 1 ]]; then
  HEADER "4. Generando frontend Next.js"

  FRONTEND_FAILED=0

  if [[ -d "$FRONTEND_DIR/$FRONTEND_NAME" ]]; then
    log_warn "frontend/$FRONTEND_NAME — directorio ya existe; omitiendo."
  else
    log "Generando $FRONTEND_NAME..."
    if (cd "$FRONTEND_DIR" && python3 "$NEXTJS_TEMPLATE" -n "$FRONTEND_NAME" --org "$PROJECT_NAME"); then
      log_ok "$FRONTEND_NAME generado."
    else
      log_err "$FRONTEND_NAME — falló la generación."
      FRONTEND_FAILED=1
    fi
  fi
else
  FRONTEND_FAILED=0
  HEADER "4. Frontend omitido"
  log "No se especificó --frontend; sin frontend que generar."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 5. PostgreSQL — generar changelogs Liquibase iniciales por microservicio
# ──────────────────────────────────────────────────────────────────────────────
# Flyway requiere JDBC bloqueante — incompatible con servicios R2DBC. Liquibase
# corre como proceso independiente (run-liquibase-migrations.sh) antes del
# despliegue; los changelogs viven en db/<servicio>/changelog/, fuera del JAR.
HEADER "5. PostgreSQL — generando changelogs Liquibase iniciales por microservicio"

if [[ "${#BC_TAGS[@]}" -gt 0 ]]; then
  if [[ ! -f "$SCHEMA_SQL" ]]; then
    log_warn "Schema SQL no encontrado: $SCHEMA_SQL — omitiendo generación de changelogs Liquibase."
  else
    for SERVICE in "${!BC_TAGS[@]}"; do
      TAG="${BC_TAGS[$SERVICE]}"
      CHANGELOG_DIR="$MIGRATIONS_REPO_DIR/$SERVICE/changelog"
      CHANGELOG_FILE="$CHANGELOG_DIR/00001_initial_schema.yaml"

      BLOCK=$(awk -v tag="-- $TAG:" '
        $0 ~ tag        { found=1; next }
        found && /^-- BC-[0-9]+:/ { exit }
        found           { print }
      ' "$SCHEMA_SQL" 2>/dev/null | sed '/^[[:space:]]*$/N;/^\n$/d' || true)

      if [[ -z "$BLOCK" ]]; then
        log_warn "$SERVICE ($TAG) — bloque no encontrado en schema.sql; se generará un placeholder."
        BLOCK="-- TODO: extraer manualmente desde $SCHEMA_SQL las tablas de $TAG"
      fi

      # El generador por-servicio (maven_hexagonal_scaffold.py) deja un stub
      # con "-- TODO: contenido poblado por scaffold-all-services.sh". Esta sección
      # es la fuente autoritativa del 00001 desde el schema.sql: sobreescribe el
      # stub, pero respeta un changelog ya poblado a mano (DDL real).
      if [[ -f "$CHANGELOG_FILE" ]] && ! grep -q "TODO: contenido poblado por scaffold" "$CHANGELOG_FILE"; then
        log_warn "$SERVICE — $CHANGELOG_FILE ya tiene DDL real; omitiendo (no se sobreescribe)."
        continue
      fi

      mkdir -p "$CHANGELOG_DIR"

      INDENTED_BLOCK=$(echo "$BLOCK" | sed 's/^/              /')

      cat > "$CHANGELOG_FILE" <<EOF
databaseChangeLog:
  - changeSet:
      id: 00001-initial-schema
      author: scaffold
      comment: "Schema inicial — Microservicio: $SERVICE, Bounded Context: $TAG — Fuente: docs/design/database/$SCHEMA_BASENAME"
      changes:
        - sql:
            sql: |
$INDENTED_BLOCK
            stripComments: true
EOF

      log_ok "$SERVICE — $CHANGELOG_FILE generado."
    done
  fi
else
  log "Sin --bc-tags definidos; omitiendo generación de changelogs Liquibase."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 6. iam-service — generar 00002_seed_roles.yaml (Liquibase)
# ──────────────────────────────────────────────────────────────────────────────
HEADER "6. iam-service — generando 00002_seed_roles.yaml"

IAM_SERVICE_DIR="$BACKEND_DIR/iam-service"
IAM_CHANGELOG_DIR="$MIGRATIONS_REPO_DIR/iam-service/changelog"
V2_FILE="$IAM_CHANGELOG_DIR/00002_seed_roles.yaml"

if [[ -d "$IAM_SERVICE_DIR" ]]; then
  if [[ -f "$V2_FILE" ]]; then
    log_warn "iam-service — $V2_FILE ya existe; omitiendo."
  else
    mkdir -p "$IAM_CHANGELOG_DIR"

    IAM_ROOT_YAML="$IAM_CHANGELOG_DIR/root.yaml"
    if [[ -f "$IAM_ROOT_YAML" ]] && ! grep -q "00002_seed_roles.yaml" "$IAM_ROOT_YAML"; then
      echo "  - include:" >> "$IAM_ROOT_YAML"
      echo "      file: changelog/00002_seed_roles.yaml" >> "$IAM_ROOT_YAML"
      echo "      relativeToChangelogFile: true" >> "$IAM_ROOT_YAML"
      log "  Incluido 00002_seed_roles.yaml en root.yaml de iam-service."
    fi

    cat > "$V2_FILE" <<'YAML_EOF'
databaseChangeLog:
  - changeSet:
      id: 00002-seed-roles-permisos
      author: scaffold
      comment: "Semilla: 7 roles del sistema, permisos por bounded context y mapeo roles_permisos"
      changes:
        - sql:
            sql: |
              INSERT INTO roles (id, nombre, descripcion, created_at)
              VALUES
                (gen_random_uuid(), 'Administrador', 'Acceso total al sistema',                                 NOW()),
                (gen_random_uuid(), 'Supervisor',    'Supervision de operaciones e inventario',                 NOW()),
                (gen_random_uuid(), 'Operador',      'Operaciones de inventario y ajustes',                    NOW()),
                (gen_random_uuid(), 'Gerente',       'Reportes y analitica',                                   NOW()),
                (gen_random_uuid(), 'Analista',      'Consultas y analisis de datos',                          NOW()),
                (gen_random_uuid(), 'Auditor',       'Acceso de solo lectura a logs y auditoria',              NOW()),
                (gen_random_uuid(), 'APIConsumer',   'Acceso programatico via API key para integraciones',     NOW())
              ON CONFLICT (nombre) DO NOTHING;
              INSERT INTO permisos (id, modulo, operacion, descripcion)
              VALUES
                (gen_random_uuid(), 'catalog',      'read',     'Leer catalogo de productos'),
                (gen_random_uuid(), 'catalog',      'write',    'Crear/editar productos'),
                (gen_random_uuid(), 'inventory',    'read',     'Consultar inventario'),
                (gen_random_uuid(), 'inventory',    'write',    'Registrar movimientos de stock'),
                (gen_random_uuid(), 'adjustment',   'read',     'Leer solicitudes de ajuste'),
                (gen_random_uuid(), 'adjustment',   'write',    'Crear solicitudes de ajuste'),
                (gen_random_uuid(), 'adjustment',   'approve',  'Aprobar ajustes de inventario'),
                (gen_random_uuid(), 'alert',        'read',     'Consultar alertas de stock'),
                (gen_random_uuid(), 'supplier',     'read',     'Consultar proveedores'),
                (gen_random_uuid(), 'supplier',     'write',    'Gestionar proveedores'),
                (gen_random_uuid(), 'reporting',    'read',     'Consultar reportes'),
                (gen_random_uuid(), 'reporting',    'generate', 'Generar reportes'),
                (gen_random_uuid(), 'audit',        'read',     'Leer registros de auditoria'),
                (gen_random_uuid(), 'integration',  'read',     'Consultar estado de integraciones'),
                (gen_random_uuid(), 'integration',  'write',    'Gestionar integraciones externas')
              ON CONFLICT (modulo, operacion) DO NOTHING;
              INSERT INTO rol_permisos (rol_id, permiso_id)
              SELECT r.id, p.id FROM roles r, permisos p WHERE r.nombre = 'Administrador'
              ON CONFLICT DO NOTHING;
              INSERT INTO rol_permisos (rol_id, permiso_id)
              SELECT r.id, p.id FROM roles r
              JOIN permisos p ON p.modulo IN ('catalog','inventory','adjustment','alert','supplier','reporting','audit','integration')
                             AND p.operacion IN ('read')
              WHERE r.nombre = 'Supervisor' ON CONFLICT DO NOTHING;
              INSERT INTO rol_permisos (rol_id, permiso_id)
              SELECT r.id, p.id FROM roles r
              JOIN permisos p ON (p.modulo, p.operacion) IN (
                ('catalog','read'),('catalog','write'),
                ('inventory','read'),('inventory','write'),
                ('adjustment','read'),('adjustment','write'),
                ('supplier','read')
              )
              WHERE r.nombre = 'Operador' ON CONFLICT DO NOTHING;
              INSERT INTO rol_permisos (rol_id, permiso_id)
              SELECT r.id, p.id FROM roles r
              JOIN permisos p ON p.operacion IN ('read','generate')
                             AND p.modulo IN ('reporting','inventory','catalog','audit')
              WHERE r.nombre = 'Gerente' ON CONFLICT DO NOTHING;
              INSERT INTO rol_permisos (rol_id, permiso_id)
              SELECT r.id, p.id FROM roles r
              JOIN permisos p ON p.operacion = 'read'
              WHERE r.nombre = 'Analista' ON CONFLICT DO NOTHING;
              INSERT INTO rol_permisos (rol_id, permiso_id)
              SELECT r.id, p.id FROM roles r
              JOIN permisos p ON p.modulo = 'audit' AND p.operacion = 'read'
              WHERE r.nombre = 'Auditor' ON CONFLICT DO NOTHING;
              INSERT INTO rol_permisos (rol_id, permiso_id)
              SELECT r.id, p.id FROM roles r
              JOIN permisos p ON p.modulo IN ('inventory','catalog','integration')
                             AND p.operacion IN ('read','write')
              WHERE r.nombre = 'APIConsumer' ON CONFLICT DO NOTHING;
            stripComments: true
YAML_EOF

    log_ok "iam-service — $V2_FILE generado."
  fi
else
  log "iam-service no encontrado en backend/; omitiendo 00002_seed_roles.yaml."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 6b. Gitea — crear repo de migraciones y hacer push de los changelogs
# ──────────────────────────────────────────────────────────────────────────────
# El repo se crea bajo la org del proyecto en Gitea (VPS_IP:3000).
# Nombre del repo: <PROJECT_NAME>-migrations
# Se ejecuta siempre que se hayan generado changelogs (--bc-tags presentes).
# ──────────────────────────────────────────────────────────────────────────────
if [[ "${#BC_TAGS[@]}" -gt 0 ]]; then
  HEADER "6b. Gitea — creando repo de migraciones (${VPS_IP}:3000)"

  GITEA_API="http://${VPS_IP}:3000/api/v1"
  GITEA_AUTH="gitea_admin:changeme_gitea_admin"
  GITEA_MIGRATIONS_REPO="${PROJECT_NAME}-migrations"
  GITEA_REPO_URL="http://gitea_admin:changeme_gitea_admin@${VPS_IP}:3000/${PROJECT_NAME}/${GITEA_MIGRATIONS_REPO}.git"

  # Verificar disponibilidad de Gitea
  GITEA_READY=0
  for _i in 1 2 3; do
    if curl -sf "http://${VPS_IP}:3000/api/healthz" &>/dev/null; then
      GITEA_READY=1; break
    fi
    sleep 3
  done

  if [[ "$GITEA_READY" -eq 0 ]]; then
    log_warn "Gitea no responde en ${VPS_IP}:3000 — repo de migraciones NO creado."
    log_warn "Ejecuta manualmente cuando Gitea esté disponible:"
    log_warn "  curl -u gitea_admin:changeme_gitea_admin -X POST http://${VPS_IP}:3000/api/v1/orgs/${PROJECT_NAME}/repos \\"
    log_warn "    -H 'Content-Type: application/json' \\"
    log_warn "    -d '{\"name\":\"${GITEA_MIGRATIONS_REPO}\",\"private\":false,\"auto_init\":false}'"
  else
    log_ok "Gitea disponible en ${VPS_IP}:3000"

    # Crear repo en Gitea bajo la org del proyecto (idempotente)
    HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
      -u "$GITEA_AUTH" -X POST "$GITEA_API/orgs/${PROJECT_NAME}/repos" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"${GITEA_MIGRATIONS_REPO}\",\"description\":\"Changelogs Liquibase — ${PROJECT_NAME}\",\"private\":false,\"auto_init\":false}" \
      2>/dev/null || echo "000")

    if [[ "$HTTP_STATUS" == "201" ]]; then
      log_ok "Repo ${PROJECT_NAME}/${GITEA_MIGRATIONS_REPO} creado en Gitea."
    elif [[ "$HTTP_STATUS" == "409" ]]; then
      log "Repo ${PROJECT_NAME}/${GITEA_MIGRATIONS_REPO} ya existe en Gitea — continuando."
    else
      log_warn "No se pudo crear el repo en Gitea (HTTP $HTTP_STATUS) — se omite el push."
      GITEA_READY=0
    fi
  fi

  if [[ "$GITEA_READY" -eq 1 ]]; then
    mkdir -p "$MIGRATIONS_REPO_DIR"

    if [[ ! -d "$MIGRATIONS_REPO_DIR/.git" ]]; then
      git -C "$MIGRATIONS_REPO_DIR" init -b main
      log_ok "git init en $MIGRATIONS_REPO_DIR"
    fi

    git -C "$MIGRATIONS_REPO_DIR" add .
    if ! git -C "$MIGRATIONS_REPO_DIR" diff --cached --quiet 2>/dev/null; then
      git -C "$MIGRATIONS_REPO_DIR" \
        -c user.email="scaffold@${PROJECT_NAME}" \
        -c user.name="scaffold" \
        commit -m "feat: initial schema — ${PROJECT_NAME}

Changelogs Liquibase generados por scaffold-all-services.sh"
      log_ok "Commit inicial creado."
    fi

    # Agregar o actualizar remote origin
    if git -C "$MIGRATIONS_REPO_DIR" remote get-url origin &>/dev/null; then
      git -C "$MIGRATIONS_REPO_DIR" remote set-url origin "$GITEA_REPO_URL"
    else
      git -C "$MIGRATIONS_REPO_DIR" remote add origin "$GITEA_REPO_URL"
    fi

    if git -C "$MIGRATIONS_REPO_DIR" push -u origin main 2>&1; then
      log_ok "Changelogs publicados en http://${VPS_IP}:3000/${PROJECT_NAME}/${GITEA_MIGRATIONS_REPO}"
    else
      log_warn "Push falló — verifica credenciales Gitea o conectividad al VPS."
    fi
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 7. Checklist de verificación
# ──────────────────────────────────────────────────────────────────────────────
HEADER "7. Checklist de verificación"

PASS="✓"
FAIL="✗"
checklist_ok=0

check_item() {
  local desc="$1" result="$2"
  if [[ "$result" -eq 0 ]]; then
    echo -e "  ${PASS} $desc"
  else
    echo -e "  ${FAIL} $desc"
    checklist_ok=1
  fi
}

# Verificar cada microservicio backend
for svc_spec in "${BACKEND_SERVICES[@]}"; do
  IFS=':' read -r name db messaging port <<< "$svc_spec"
  POM="$BACKEND_DIR/$name/pom.xml"
  [[ -f "$POM" ]] && check_item "$name — pom.xml existe" 0 \
                    || check_item "$name — pom.xml existe" 1
done

# Verificar frontend
if [[ "$HAS_FRONTEND" -eq 1 ]]; then
  PACKAGE_JSON="$FRONTEND_DIR/$FRONTEND_NAME/package.json"
  [[ -f "$PACKAGE_JSON" ]] && check_item "$FRONTEND_NAME — package.json existe" 0 \
                              || check_item "$FRONTEND_NAME — package.json existe" 1
fi

# Verificar changelogs Liquibase iniciales
if [[ "${#BC_TAGS[@]}" -gt 0 ]]; then
  for SERVICE in "${!BC_TAGS[@]}"; do
    CL="$MIGRATIONS_REPO_DIR/$SERVICE/changelog/00001_initial_schema.yaml"
    PROPS="$MIGRATIONS_REPO_DIR/$SERVICE/liquibase.properties"
    [[ -f "$CL" ]]    && check_item "$SERVICE — db/$SERVICE/changelog/00001_initial_schema.yaml existe" 0 \
                       || check_item "$SERVICE — db/$SERVICE/changelog/00001_initial_schema.yaml existe" 1
    [[ -f "$PROPS" ]] && check_item "$SERVICE — db/$SERVICE/liquibase.properties existe" 0 \
                       || check_item "$SERVICE — db/$SERVICE/liquibase.properties existe" 1
  done
fi

# Verificar 00002_seed_roles.yaml de iam-service
if [[ -d "$BACKEND_DIR/iam-service" ]]; then
  V2="$MIGRATIONS_REPO_DIR/iam-service/changelog/00002_seed_roles.yaml"
  [[ -f "$V2" ]] && check_item "iam-service — db/iam-service/changelog/00002_seed_roles.yaml existe" 0 \
                  || check_item "iam-service — db/iam-service/changelog/00002_seed_roles.yaml existe" 1
fi

echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 8. Resumen
# ──────────────────────────────────────────────────────────────────────────────
HEADER "Resumen"

GENERATED_COUNT=$(find "$BACKEND_DIR" -maxdepth 1 -mindepth 1 -type d -name "*-service" 2>/dev/null | wc -l)
echo ""
printf "  %-35s %s\n" "Microservicios backend" "${GENERATED_COUNT} generados"
if [[ "$HAS_FRONTEND" -eq 1 ]]; then
  printf "  %-35s %s\n" "Frontend" "$([[ -d "$FRONTEND_DIR/$FRONTEND_NAME" ]] && echo "$FRONTEND_NAME" || echo "NO generado")"
else
  printf "  %-35s %s\n" "Frontend" "omitido"
fi
if [[ "${#BC_TAGS[@]}" -gt 0 ]]; then
  printf "  %-35s %s\n" "Changelogs Liquibase (00001)" "${#BC_TAGS[@]} servicios en $MIGRATIONS_REPO_DIR"
else
  printf "  %-35s %s\n" "Changelogs Liquibase (00001)" "omitidos (sin --bc-tags)"
fi
echo "  El esquema lo aplica Liquibase standalone (run-liquibase-migrations.sh) previo al despliegue."
echo ""

if [[ $checklist_ok -ne 0 ]] || [[ $FRONTEND_FAILED -ne 0 ]] || [[ ${#BACKEND_FAILED[@]} -gt 0 ]]; then
  if [[ ${#BACKEND_FAILED[@]} -gt 0 ]]; then
    log_err "Servicios backend fallidos: ${BACKEND_FAILED[*]}"
  fi
  if [[ $FRONTEND_FAILED -ne 0 ]]; then
    log_err "Frontend fallido: $FRONTEND_NAME"
  fi
  exit 1
fi

log_ok "Scaffolding completado exitosamente."

# ──────────────────────────────────────────────────────────────────────────────
# 9. Compilación backend
# ──────────────────────────────────────────────────────────────────────────────
HEADER "9. Compilación backend"

log "Ejecutando compile-services.sh..."
if bash "$SCRIPT_DIR/compile-services.sh"; then
  log_ok "Compilación backend completada."
else
  log_err "Compilación backend falló."
  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# 10. Verificación frontend
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$HAS_FRONTEND" -eq 1 ]]; then
  HEADER "10. Verificación frontend"

  log "Ejecutando verify-frontend.sh..."
  if bash "$SCRIPT_DIR/verify-frontend.sh"; then
    log_ok "Verificación frontend completada."
  else
    log_err "Verificación frontend falló."
    exit 1
  fi
else
  HEADER "10. Verificación frontend omitida"
  log "No se especificó --frontend; sin frontend que verificar."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 11. Secrets en HashiCorp Vault
# ──────────────────────────────────────────────────────────────────────────────
HEADER "11. Secrets en HashiCorp Vault"

log "Ejecutando create-all-secrets-vault.sh (Vault en K3s)..."
if bash "$SCRIPT_DIR/create-all-secrets-vault.sh" \
     -P "$PROJECT_NAME" \
     --vm-ip "$VPS_IP" \
     --pg-prefix "$PG_DB_NAME" \
     --mongo-prefix "$MONGO_DB_NAME" \
     --env local; then
  log_ok "Secrets creados en Vault."
else
  log_err "Creacion de secrets en Vault fallo."
  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# 12. Terraform — verificar estado de la infraestructura K3s
# ──────────────────────────────────────────────────────────────────────────────
HEADER "12. Verificacion Terraform (K3s)"

TERRAFORM_DIR="$REPO_ROOT/terraform"

if [[ ! -d "$TERRAFORM_DIR" ]]; then
  log_warn "Directorio Terraform no encontrado: $TERRAFORM_DIR"
else
  log "Verificando estado de Terraform..."
  if (cd "$TERRAFORM_DIR" && terraform show &>/dev/null); then
    log_ok "Terraform state valido."
  else
    log_warn "Terraform state no disponible — ejecutar terraform apply manualmente."
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 13. Verificacion — Gitea repos y package registry
# ──────────────────────────────────────────────────────────────────────────────
HEADER "13. Verificacion Gitea (VPS)"

log "Verificando acceso a Gitea ($VPS_IP:3000)..."
if curl -sf "http://${VPS_IP}:3000/api/healthz" &>/dev/null; then
  log_ok "Gitea accesible en http://$VPS_IP:3000"
else
  log_warn "Gitea no responde en $VPS_IP:3000 — verificar que el servicio esta activo."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 14. Verificacion — secrets en Vault
# ──────────────────────────────────────────────────────────────────────────────
HEADER "14. Verificacion de secrets en Vault"

KUBECONFIG_FILE="$HOME/.kube/config-${PROJECT_NAME}-${ENV:-local}"
[[ -f "$KUBECONFIG_FILE" ]] && export KUBECONFIG="$KUBECONFIG_FILE"

VAULT_POD=$(kubectl get pod -n secrets -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$VAULT_POD" ]]; then
  log "Vault pod: $VAULT_POD"
  kubectl exec -n secrets "$VAULT_POD" -- vault kv list "secret/${PROJECT_NAME}/local" 2>/dev/null && \
    log_ok "Secrets verificados en Vault." || \
    log_warn "No se pudieron listar los secrets en Vault."
else
  log_warn "Pod Vault no encontrado en namespace 'secrets'."
fi

log_ok "Pipeline post-scaffolding completado exitosamente."