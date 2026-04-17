#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  generate-sealed-secrets.sh
#
#  Run this ONCE after the sealed-secrets controller is installed in the cluster.
#  It overwrites the placeholder files:
#    sealed-secrets/backend-common-secrets.yaml
#    sealed-secrets/mongodb-secrets.yaml
#  with real encrypted SealedSecret manifests using kubeseal.
#
#  Prerequisites:
#    - kubectl configured and pointing at your cluster
#    - kubeseal CLI installed
#    - sealed-secrets-controller running in kube-system
#
#  Usage:
#    export JWT_SECRET="your-jwt-secret"
#    export GEMINI_API_KEY="your-gemini-key"
#    export MONGO_ROOT_PASSWORD="your-mongo-root-password"
#    export AUTH_PASS="auth_password"
#    export CART_PASS="cart_password"
#    export CATALOG_PASS="catalog_password"
#    export ORDER_PASS="order_password"
#    export PAYMENT_PASS="payment_password"
#    export NOTIFICATION_PASS="notification_password"
#    export ANALYTICS_PASS="analytics_password"
#    bash generate-sealed-secrets.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Validate required env vars ────────────────────────────────────────────────
required_vars=(
  JWT_SECRET GEMINI_API_KEY MONGO_ROOT_PASSWORD
  AUTH_PASS CART_PASS CATALOG_PASS ORDER_PASS
  PAYMENT_PASS NOTIFICATION_PASS ANALYTICS_PASS
)
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: env var $var is not set."
    exit 1
  fi
done

echo "Fetching sealed-secrets controller public key..."
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  > "$SCRIPT_DIR/pub-cert.pem"
echo "  ✔ pub-cert.pem saved (do not commit this file)"

seal() {
  local raw_yaml="$1"
  echo "$raw_yaml" | kubeseal --cert "$SCRIPT_DIR/pub-cert.pem" --format yaml
}

# ── 1. backend-common secrets (hipster-backend) ───────────────────────────────
echo ""
echo "Generating backend-common-secrets.yaml..."

APP_SECRETS=$(kubectl create secret generic app-secrets \
  --namespace=hipster-backend \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=GEMINI_API_KEY="$GEMINI_API_KEY" \
  --dry-run=client -o yaml)

MONGO_ROOT_BACKEND=$(kubectl create secret generic mongodb-root \
  --namespace=hipster-backend \
  --from-literal=MONGO_ROOT_USERNAME="admin" \
  --from-literal=MONGO_ROOT_PASSWORD="$MONGO_ROOT_PASSWORD" \
  --dry-run=client -o yaml)

MONGO_USERS_BACKEND=$(kubectl create secret generic mongodb-users \
  --namespace=hipster-backend \
  --from-literal=AUTH_MONGO_USERNAME="auth_user"         --from-literal=AUTH_MONGO_PASSWORD="$AUTH_PASS" \
  --from-literal=CART_MONGO_USERNAME="cart_user"         --from-literal=CART_MONGO_PASSWORD="$CART_PASS" \
  --from-literal=CATALOG_MONGO_USERNAME="catalog_user"   --from-literal=CATALOG_MONGO_PASSWORD="$CATALOG_PASS" \
  --from-literal=ORDER_MONGO_USERNAME="order_user"       --from-literal=ORDER_MONGO_PASSWORD="$ORDER_PASS" \
  --from-literal=PAYMENT_MONGO_USERNAME="payment_user"   --from-literal=PAYMENT_MONGO_PASSWORD="$PAYMENT_PASS" \
  --from-literal=NOTIFICATION_MONGO_USERNAME="notification_user" --from-literal=NOTIFICATION_MONGO_PASSWORD="$NOTIFICATION_PASS" \
  --from-literal=ANALYTICS_MONGO_USERNAME="analytics_user"      --from-literal=ANALYTICS_MONGO_PASSWORD="$ANALYTICS_PASS" \
  --dry-run=client -o yaml)

{ seal "$APP_SECRETS"; echo "---"; seal "$MONGO_ROOT_BACKEND"; echo "---"; seal "$MONGO_USERS_BACKEND"; } \
  > "$SCRIPT_DIR/backend-common-secrets.yaml"
echo "  ✔ backend-common-secrets.yaml"

# ── 2. mongodb secrets (hipster-database) ────────────────────────────────────
echo ""
echo "Generating mongodb-secrets.yaml..."

MONGO_ROOT_DB=$(kubectl create secret generic mongodb-root \
  --namespace=hipster-database \
  --from-literal=MONGO_ROOT_USERNAME="admin" \
  --from-literal=MONGO_ROOT_PASSWORD="$MONGO_ROOT_PASSWORD" \
  --dry-run=client -o yaml)

MONGO_USERS_DB=$(kubectl create secret generic mongodb-users \
  --namespace=hipster-database \
  --from-literal=AUTH_MONGO_USERNAME="auth_user"         --from-literal=AUTH_MONGO_PASSWORD="$AUTH_PASS" \
  --from-literal=CART_MONGO_USERNAME="cart_user"         --from-literal=CART_MONGO_PASSWORD="$CART_PASS" \
  --from-literal=CATALOG_MONGO_USERNAME="catalog_user"   --from-literal=CATALOG_MONGO_PASSWORD="$CATALOG_PASS" \
  --from-literal=ORDER_MONGO_USERNAME="order_user"       --from-literal=ORDER_MONGO_PASSWORD="$ORDER_PASS" \
  --from-literal=PAYMENT_MONGO_USERNAME="payment_user"   --from-literal=PAYMENT_MONGO_PASSWORD="$PAYMENT_PASS" \
  --from-literal=NOTIFICATION_MONGO_USERNAME="notification_user" --from-literal=NOTIFICATION_MONGO_PASSWORD="$NOTIFICATION_PASS" \
  --from-literal=ANALYTICS_MONGO_USERNAME="analytics_user"      --from-literal=ANALYTICS_MONGO_PASSWORD="$ANALYTICS_PASS" \
  --dry-run=client -o yaml)

{ seal "$MONGO_ROOT_DB"; echo "---"; seal "$MONGO_USERS_DB"; } \
  > "$SCRIPT_DIR/mongodb-secrets.yaml"
echo "  ✔ mongodb-secrets.yaml"

echo ""
echo "Done. Commit these two files — they are encrypted and safe to push:"
echo "  sealed-secrets/backend-common-secrets.yaml"
echo "  sealed-secrets/mongodb-secrets.yaml"
echo ""
echo "DO NOT commit pub-cert.pem"
