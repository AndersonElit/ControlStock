#!/usr/bin/env bash
# run-liquibase-migrations.sh — Aplica migraciones Liquibase standalone para un microservicio
#
# Flujo:
#   1. Clona el repo <project>-migrations desde Gitea del VPS
#   2. Construye imagen Liquibase con el changelog del servicio
#   3. Ejecuta como Job K8s (o docker run en modo local) contra la BD del servicio
#
# Convención de rutas en el repo de migraciones:
#   <service-slug>/
#     changelog.yaml           — master changelog (incluye los archivos numerados)
#     00001_initial_schema.yaml
#     00002_*.yaml
#     ...
#
# Uso: ./run-liquibase-migrations.sh [OPCIONES]
#
# Opciones:
#   --vm-ip       IP       IP del VPS                              (requerido)
#   --project     NAME     Nombre del proyecto                     (requerido)
#   --service     NAME     Microservicio a migrar                  (requerido)
#   --pg-prefix   PREFIX   Prefijo BD PostgreSQL                   (requerido)
#   --env         ENV      local | prod                            (default: local)
#   --gitea-user  USER     Usuario Gitea                           (default: gitea_admin)
#   --gitea-pass  PASS     Password Gitea                          (default: changeme_gitea_admin)
#   --ssh-user    USER     Usuario SSH VPS                         (default: ubuntu)
#   --ssh-key     FILE     Clave SSH privada                       (default: ~/.ssh/id_ed25519)
#   --pg-pass     PASS     Password admin PostgreSQL               (default: changeme_pg_admin)
#   --tag         TAG      Tag changelog a ejecutar (default: empty = todos)
#   --rollback    COUNT    Rollback N changesets en vez de update
#   --db-name     NAME     Nombre de BD destino (override; si el slug != BD real)
#   --db-user     USER     Usuario BD (override; default: <db-name>_user)
#   --db-pass     PASS     Password BD (override; default: changeme_<slug>)
#   --dry-run              Muestra comandos sin ejecutar
#   --gitea-clone          Clonar desde Gitea (default). Si se omite usa directorio local.
#
# Ejemplos:
#   # Migrar un servicio desde Gitea:
#   ./run-liquibase-migrations.sh --vm-ip 192.168.122.50 --project myapp \
#     --service clientes-service --pg-prefix myapp --gitea-clone
#
#   # Rollback 1 changeset:
#   ./run-liquibase-migrations.sh --vm-ip 192.168.122.50 --project myapp \
#     --service clientes-service --pg-prefix myapp --rollback 1

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()   { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()     { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()   { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
header() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }
die()    { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

VM_IP=""
PROJECT=""
SERVICE=""
PG_PREFIX=""
ENV="local"
GITEA_USER="gitea_admin"
GITEA_PASS="changeme_gitea_admin"
SSH_USER="ubuntu"
SSH_KEY="$HOME/.ssh/id_ed25519"
PG_PASS="changeme_pg_admin"
CHANGELOG_TAG=""
ROLLBACK_COUNT=""
DRY_RUN=false
GITEA_CLONE=false
DB_NAME_OVERRIDE=""
DB_USER_OVERRIDE=""
DB_PASS_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vm-ip)      VM_IP="$2";       shift 2 ;;
    --project)    PROJECT="$2";     shift 2 ;;
    --service)    SERVICE="$2";     shift 2 ;;
    --pg-prefix)  PG_PREFIX="$2";   shift 2 ;;
    --env)        ENV="$2";         shift 2 ;;
    --gitea-user) GITEA_USER="$2";  shift 2 ;;
    --gitea-pass) GITEA_PASS="$2";  shift 2 ;;
    --ssh-user)   SSH_USER="$2";    shift 2 ;;
    --ssh-key)    SSH_KEY="$2";     shift 2 ;;
    --pg-pass)    PG_PASS="$2";     shift 2 ;;
    --tag)        CHANGELOG_TAG="$2"; shift 2 ;;
    --rollback)   ROLLBACK_COUNT="$2"; shift 2 ;;
    --db-name)    DB_NAME_OVERRIDE="$2"; shift 2 ;;
    --db-user)    DB_USER_OVERRIDE="$2"; shift 2 ;;
    --db-pass)    DB_PASS_OVERRIDE="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true;     shift ;;
    --gitea-clone) GITEA_CLONE=true; shift ;;
    *) die "Opción desconocida: $1" ;;
  esac
done

[[ -z "$VM_IP" ]]     && die "--vm-ip es requerido"
[[ -z "$PROJECT" ]]   && die "--project es requerido"
[[ -z "$SERVICE" ]]   && die "--service es requerido"
[[ -z "$PG_PREFIX" ]] && die "--pg-prefix es requerido"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -i $SSH_KEY"
ssh_run() { ssh $SSH_OPTS "${SSH_USER}@${VM_IP}" "$@"; }

slugify() { echo "$1" | tr '-' '_' | tr '[:upper:]' '[:lower:]' | sed 's/_service$//'; }

SERVICE_SLUG=$(slugify "$SERVICE")
DB_NAME="${PG_PREFIX}_${SERVICE_SLUG}"
# Override del nombre de BD cuando el slug del servicio no coincide con la BD real
# (ej. report-etl-service cuyo DDL de reporting vive en controlstock_reporting)
[[ -n "$DB_NAME_OVERRIDE" ]] && DB_NAME="$DB_NAME_OVERRIDE"
MIGRATIONS_REPO="${PROJECT}-migrations"
GITEA_URL="http://${VM_IP}:3000"

# Detectar kubeconfig automáticamente
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-${PROJECT}-${ENV}}"
[[ -f "$KUBECONFIG" ]] || export KUBECONFIG="$HOME/.kube/config-controlstock-${ENV}"
[[ -f "$KUBECONFIG" ]] || export KUBECONFIG="$HOME/.kube/config-${PROJECT}-${ENV}"

# ─── clonar repo de migraciones desde Gitea ──────────────────────────────────
clone_migrations_repo() {
  header "Clonando repo de migraciones: $MIGRATIONS_REPO"

  local clone_url="http://${GITEA_USER}:${GITEA_PASS}@${VM_IP}:3000/${PROJECT}/${MIGRATIONS_REPO}.git"
  local tmp_dir="/tmp/${MIGRATIONS_REPO}"

  if [[ -d "$tmp_dir/.git" ]]; then
    info "Actualizando repo existente..."
    git -C "$tmp_dir" pull --rebase origin main 2>/dev/null || true
  else
    info "Clonando..."
    git clone "$clone_url" "$tmp_dir" 2>/dev/null || {
      warn "No se pudo clonar desde Gitea. Usando changelogs locales en db/"
      return 1
    }
  fi
  ok "Repo listo: $tmp_dir"
}

# ─── ejecutar Liquibase como Job K8s via ConfigMap ────────────────────────────
run_liquibase_job() {
  header "Ejecutando Liquibase: $SERVICE → $DB_NAME"

  local lb_command="update"
  local extra_args=""

  if [[ -n "$ROLLBACK_COUNT" ]]; then
    lb_command="rollbackCount"
    extra_args="$ROLLBACK_COUNT"
  elif [[ -n "$CHANGELOG_TAG" ]]; then
    lb_command="updateToTag"
    extra_args="$CHANGELOG_TAG"
  fi

  local changelog_file="root.yaml"
  local changelog_mount="/liquibase/changelog"
  local pg_host="postgresql.data.svc.cluster.local"
  local jdbc_url="jdbc:postgresql://${pg_host}:5432/${DB_NAME}"
  local configmap_name="liquibase-${SERVICE_SLUG}"
  local job_name="liquibase-${SERVICE_SLUG}-$(date +%s)"
  local db_user="${DB_USER_OVERRIDE:-${DB_NAME}_user}"
  local db_pass="${DB_PASS_OVERRIDE:-changeme_${SERVICE_SLUG}}"

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}[DRY-RUN]${RESET}  Liquibase $lb_command → $DB_NAME"
    return
  fi

  # Usar changelogs locales (db/<servicio>/changelog/) o clonados
  local changelog_dir=""
  if [[ -d "db/${SERVICE}/changelog" ]]; then
    changelog_dir="$(pwd)/db/${SERVICE}/changelog"
  elif [[ -d "/tmp/${MIGRATIONS_REPO}/${SERVICE}/changelog" ]]; then
    changelog_dir="/tmp/${MIGRATIONS_REPO}/${SERVICE}/changelog"
  elif [[ -d "/tmp/${MIGRATIONS_REPO}/${SERVICE_SLUG}/changelog" ]]; then
    changelog_dir="/tmp/${MIGRATIONS_REPO}/${SERVICE_SLUG}/changelog"
  else
    die "No se encontraron changelogs para $SERVICE en db/${SERVICE}/changelog/ ni en Gitea"
  fi

  info "Changelogs desde: $changelog_dir"

  # Crear ConfigMap con los changelogs
  kubectl create configmap "$configmap_name" \
    --from-file="$changelog_dir" \
    -n data --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

  # Ejecutar Job de Liquibase
  kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: data
spec:
  ttlSecondsAfterFinished: 120
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: liquibase
          image: liquibase/liquibase:4.27
          args:
            # searchPath + changeLogFile relativo: Liquibase 4.x resuelve la ruta
            # contra el searchPath; una ruta absoluta provoca "root.yaml does not exist"
            - "--searchPath=${changelog_mount}"
            - "--url=${jdbc_url}"
            - "--username=${db_user}"
            - "--password=${db_pass}"
            - "--changeLogFile=${changelog_file}"
            - "--logLevel=info"
            - "${lb_command}"
          volumeMounts:
            - name: changelogs
              mountPath: /liquibase/changelog
      volumes:
        - name: changelogs
          configMap:
            name: ${configmap_name}
EOF

  info "Job creado: $job_name — esperando..."
  if kubectl wait "job/${job_name}" -n data --for=condition=complete --timeout=3m 2>/dev/null; then
    kubectl logs -n data "job/${job_name}" --tail=10 2>/dev/null
    ok "Migraciones aplicadas: $DB_NAME"
  else
    warn "Job falló o timeout. Últimos logs:"
    kubectl logs -n data "job/${job_name}" --tail=30 2>/dev/null || true
    die "Migraciones fallaron para $SERVICE"
  fi

  # Limpiar ConfigMap
  kubectl delete configmap "$configmap_name" -n data --ignore-not-found 2>/dev/null
}

# ─── main ─────────────────────────────────────────────────────────────────────
main() {
  header "run-liquibase-migrations — service=$SERVICE  db=$DB_NAME  env=$ENV"
  [[ "$DRY_RUN" == true ]] && warn "Modo DRY-RUN activo"

  # Intentar clonar desde Gitea si se solicita; si falla, usar changelogs locales
  if [[ "$GITEA_CLONE" == true ]]; then
    clone_migrations_repo || warn "Usando changelogs locales en db/${SERVICE}/changelog/"
  fi
  run_liquibase_job

  ok "Migraciones completadas para $SERVICE ($DB_NAME)"
}

main
