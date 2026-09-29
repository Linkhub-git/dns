#!/usr/bin/env bash
# Prepara linkhub-dns para que GitHub Actions gestione app.linkhub.ai. Idempotente.
# Lo corre una vez una persona Owner de linkhub-dns (Cloud Shell):
#   GITHUB_REPO_ID=<id> GITHUB_OWNER_ID=<id> ./infra/bootstrap.sh
#
# Crea:
#   - bucket linkhub-dns-tfstate (estado de Terraform, versionado)
#   - dns-plan  : lee la zona y el estado. La usa cualquier PR del repo.
#   - dns-apply : cambia registros de app-linkhub-ai. SOLO push a main (tras la revisión de CODEOWNERS).
#   - pool/proveedor WIF "github", restringido por id numérico del repo y de la organización.
set -euo pipefail
PROYECTO=linkhub-dns
ZONA=app-linkhub-ai
BUCKET=linkhub-dns-tfstate
REGION=southamerica-west1
: "${GITHUB_REPO_ID:?}" "${GITHUB_OWNER_ID:?}"
g() { gcloud --project="$PROYECTO" "$@"; }

g services enable dns.googleapis.com iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com storage.googleapis.com

if ! g storage buckets describe "gs://$BUCKET" >/dev/null 2>&1; then
  g storage buckets create "gs://$BUCKET" --location="$REGION" --uniform-bucket-level-access --public-access-prevention
fi
g storage buckets update "gs://$BUCKET" --versioning >/dev/null

for sa in dns-plan dns-apply; do
  g iam service-accounts describe "$sa@$PROYECTO.iam.gserviceaccount.com" >/dev/null 2>&1 \
    || g iam service-accounts create "$sa" --display-name="GitHub Linkhub-git/dns ($sa)"
done
PLAN="serviceAccount:dns-plan@$PROYECTO.iam.gserviceaccount.com"
APPLY="serviceAccount:dns-apply@$PROYECTO.iam.gserviceaccount.com"

g projects add-iam-policy-binding "$PROYECTO" --member="$PLAN" --role=roles/dns.reader --condition=None >/dev/null
g storage buckets add-iam-policy-binding "gs://$BUCKET" --member="$PLAN" --role=roles/storage.objectViewer >/dev/null
# dns-apply: administra solo la zona app-linkhub-ai (no puede crear ni borrar zonas).
# (gcloud no tiene add-iam-policy-binding para zonas: se lee la política, se añade y se escribe.)
POL=$(mktemp)
g dns managed-zones get-iam-policy "$ZONA" --format=json >"$POL"
python3 - "$POL" "$APPLY" <<'PY'
import json, sys
ruta, miembro, rol = sys.argv[1], sys.argv[2], "roles/dns.admin"
p = json.load(open(ruta))
b = [x for x in p.setdefault("bindings", []) if x["role"] == rol]
if not b:
    p["bindings"].append({"role": rol, "members": [miembro]})
elif miembro not in b[0]["members"]:
    b[0]["members"].append(miembro)
json.dump(p, open(ruta, "w"))
PY
g dns managed-zones set-iam-policy "$ZONA" --policy-file="$POL" >/dev/null
rm -f "$POL"
g projects add-iam-policy-binding "$PROYECTO" --member="$APPLY" --role=roles/dns.reader --condition=None >/dev/null
g storage buckets add-iam-policy-binding "gs://$BUCKET" --member="$APPLY" --role=roles/storage.objectAdmin >/dev/null

NUM=$(g projects describe "$PROYECTO" --format='value(projectNumber)')
if ! g iam workload-identity-pools describe github --location=global >/dev/null 2>&1; then
  g iam workload-identity-pools create github --location=global --display-name="GitHub"
fi
MAPEO="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.aplicar=(assertion.ref=='refs/heads/main' && assertion.event_name=='push') ? 'si' : 'no'"
COND="assertion.repository_id=='$GITHUB_REPO_ID' && assertion.repository_owner_id=='$GITHUB_OWNER_ID'"
if ! g iam workload-identity-pools providers describe github --location=global --workload-identity-pool=github >/dev/null 2>&1; then
  g iam workload-identity-pools providers create-oidc github --location=global --workload-identity-pool=github \
    --issuer-uri=https://token.actions.githubusercontent.com --attribute-mapping="$MAPEO" --attribute-condition="$COND"
else
  g iam workload-identity-pools providers update-oidc github --location=global --workload-identity-pool=github \
    --attribute-mapping="$MAPEO" --attribute-condition="$COND"
fi
P="principalSet://iam.googleapis.com/projects/$NUM/locations/global/workloadIdentityPools/github"
g iam service-accounts add-iam-policy-binding "dns-plan@$PROYECTO.iam.gserviceaccount.com" \
  --role=roles/iam.workloadIdentityUser --member="$P/attribute.repository_id/$GITHUB_REPO_ID" >/dev/null
g iam service-accounts add-iam-policy-binding "dns-apply@$PROYECTO.iam.gserviceaccount.com" \
  --role=roles/iam.workloadIdentityUser --member="$P/attribute.aplicar/si" >/dev/null

echo
echo "Listo. Variable de GitHub (repo Linkhub-git/dns): PROYECTO_NUMERO=$NUM"
