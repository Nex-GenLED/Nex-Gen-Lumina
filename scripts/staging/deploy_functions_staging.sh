#!/usr/bin/env bash
# Deploy ONLY the eight dealer-tools functions to a STAGING Firebase project.
#
#   scripts/staging/deploy_functions_staging.sh --project <staging-id>          # plan only
#   scripts/staging/deploy_functions_staging.sh --project <staging-id> --yes    # deploy
#
# Without --yes it runs every check and prints the exact deploy command, then
# exits without deploying. It never targets the production project, never runs
# `firebase use`, and passes --project explicitly on every firebase call.
#
# Preconditions it checks (read-only gcloud calls against the target project):
#   • the target is not the production project id;
#   • the working tree is clean apart from functions/lib (a build output);
#   • functions/.env does NOT exist (firebase-tools merges it into EVERY
#     project's deploy, and locally it holds the production credentials);
#   • functions/.env.<project> exists and names every param the codebase
#     declares (empty values are fine — the CLI resolves params codebase-wide,
#     not per --only, and fails non-interactively on any missing key);
#   • no outbound-messaging credential (Resend / Twilio) is non-empty in it,
#     unless --allow-outbound is passed;
#   • the APIs a 2nd-gen deploy with Firestore + scheduler triggers needs are
#     enabled;
#   • the GOOGLE_MAPS_API_KEY secret exists (declared by backfillUserLocations,
#     which is NOT deployed here, but the CLI still checks it codebase-wide).
set -euo pipefail

PRODUCTION_PROJECT="icrt6menwsv2d8all8oijs021b06s5"

FUNCTIONS=(
  mintStaffToken
  createCustomerAccount
  claimCustomerByEmail
  onSalesJobStatusChanged
  notifyDay2Team
  sendInstallReminders
  setAccountProfile
  healUserProfile
)

REQUIRED_APIS=(
  cloudfunctions.googleapis.com
  run.googleapis.com
  cloudbuild.googleapis.com
  artifactregistry.googleapis.com
  eventarc.googleapis.com
  pubsub.googleapis.com
  cloudscheduler.googleapis.com
  secretmanager.googleapis.com
  firestore.googleapis.com
  identitytoolkit.googleapis.com
)

OUTBOUND_KEYS=(RESEND_API_KEY TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN)

PROJECT=""
YES=0
ALLOW_OUTBOUND=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --project=*) PROJECT="${1#--project=}"; shift ;;
    --yes) YES=1; shift ;;
    --allow-outbound) ALLOW_OUTBOUND=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

die() { echo "REFUSED: $*" >&2; exit 1; }

[ -n "$PROJECT" ] || die "--project <staging-project-id> is required (no default, no .firebaserc fallback)."
[ "$PROJECT" != "$PRODUCTION_PROJECT" ] || die "$PROJECT is the PRODUCTION project. This script never deploys there."
case "$PROJECT" in *[!a-z0-9-]*) die "project id '$PROJECT' has unexpected characters." ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
echo "repo:    $ROOT"
echo "branch:  $(git rev-parse --abbrev-ref HEAD)  head: $(git rev-parse --short HEAD)"
echo "target:  $PROJECT"

DIRTY="$(git status --porcelain | grep -v ' functions/lib/' || true)"
[ -z "$DIRTY" ] || die "working tree has uncommitted changes outside functions/lib:
$DIRTY"

[ ! -e functions/.env ] || die "functions/.env exists. firebase-tools would merge it into the $PROJECT deploy, and it holds the production credentials. Move it aside first."

for f in "${FUNCTIONS[@]}"; do
  grep -qE "^exports\.${f} = " functions/index.js || die "functions/index.js does not export $f"
done

ENV_FILE="functions/.env.$PROJECT"
[ -f "$ENV_FILE" ] || die "$ENV_FILE is missing. Create it (gitignored) with every key listed below; empty values are allowed."

mapfile -t PARAMS < <(grep -rhoE 'defineString\(\s*"[A-Z0-9_]+"' functions/index.js functions/src \
  | sed -E 's/.*"([A-Z0-9_]+)"/\1/' | sort -u)
MISSING=()
for p in "${PARAMS[@]}"; do
  grep -qE "^${p}=" "$ENV_FILE" || MISSING+=("$p")
done
[ "${#MISSING[@]}" -eq 0 ] || die "$ENV_FILE lacks these keys (names only): ${MISSING[*]}"
echo "env:     $ENV_FILE defines all ${#PARAMS[@]} params"

SET_OUTBOUND=()
for k in "${OUTBOUND_KEYS[@]}"; do
  v="$(grep -E "^${k}=" "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"'"'"' \r')"
  [ -z "$v" ] || SET_OUTBOUND+=("$k")
done
if [ "${#SET_OUTBOUND[@]}" -gt 0 ]; then
  if [ "$ALLOW_OUTBOUND" -eq 1 ]; then
    echo "WARNING: outbound credentials are set for staging: ${SET_OUTBOUND[*]} (allowed by --allow-outbound)"
  else
    die "outbound credentials are set in $ENV_FILE: ${SET_OUTBOUND[*]}. Staging should send no email/SMS; clear them or pass --allow-outbound."
  fi
fi

ENABLED="$(gcloud services list --enabled --project "$PROJECT" --format='value(config.name)' | tr -d '\r')"
MISSING_APIS=()
for a in "${REQUIRED_APIS[@]}"; do
  grep -qx "$a" <<<"$ENABLED" || MISSING_APIS+=("$a")
done
[ "${#MISSING_APIS[@]}" -eq 0 ] || die "APIs not enabled on $PROJECT: ${MISSING_APIS[*]}
  enable with: gcloud services enable ${MISSING_APIS[*]} --project $PROJECT"

gcloud secrets describe GOOGLE_MAPS_API_KEY --project "$PROJECT" --format='value(name)' >/dev/null 2>&1 \
  || die "secret GOOGLE_MAPS_API_KEY does not exist on $PROJECT (the CLI checks it even though backfillUserLocations is not deployed). A placeholder value is enough."

ONLY="$(printf 'functions:%s,' "${FUNCTIONS[@]}")"; ONLY="${ONLY%,}"
export FUNCTIONS_DISCOVERY_TIMEOUT=180
CMD=(firebase deploy --only "$ONLY" --project "$PROJECT" --non-interactive)

echo
echo "deploy:  FUNCTIONS_DISCOVERY_TIMEOUT=$FUNCTIONS_DISCOVERY_TIMEOUT ${CMD[*]}"
echo "         (firebase.json predeploy runs 'npm --prefix functions run build', which rewrites"
echo "          tracked functions/lib files; do not commit them.)"
if [ "$YES" -ne 1 ]; then
  echo
  echo "Plan only. Re-run with --yes to deploy."
  exit 0
fi

"${CMD[@]}"
