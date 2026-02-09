#!/usr/bin/env bash
# =============================================================================
# Keycloak Redirect URI Manager
# =============================================================================
# Add or remove redirect URIs (and web origins) from a Keycloak client.
#
# Required env vars:
#   KC_BASE_URL            - Keycloak base URL (e.g. https://auth.example.com)
#   KC_REALM               - Target realm
#   KC_CLIENT_ID           - Client UUID to modify
#   KC_ADMIN_CLIENT_ID     - Admin client for token grant
#   KC_ADMIN_CLIENT_SECRET - Admin client secret
#
# Usage:
#   kc-redirect-uri add <url>
#   kc-redirect-uri remove <url>

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}ℹ  $1${NC}"; }
success() { echo -e "${GREEN}✔  $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠  $1${NC}"; }
error()   { echo -e "${RED}✖  $1${NC}" >&2; }

# -----------------------------------------------------------------------------
# Validate dependencies & env
# -----------------------------------------------------------------------------
for cmd in curl jq; do
  command -v "$cmd" &>/dev/null || { error "$cmd is required but not installed"; exit 1; }
done

REQUIRED_VARS=(KC_BASE_URL KC_REALM KC_CLIENT_ID KC_ADMIN_CLIENT_ID KC_ADMIN_CLIENT_SECRET)
for var in "${REQUIRED_VARS[@]}"; do
  [[ -z "${!var:-}" ]] && { error "Missing env var: $var"; exit 1; }
done

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
usage() {
  echo "Usage: $(basename "$0") <add|remove> <url>"
  exit 1
}

[[ $# -ne 2 ]] && usage

ACTION="$1"
URL="$2"

[[ "$ACTION" != "add" && "$ACTION" != "remove" ]] && { error "Action must be 'add' or 'remove'"; usage; }
[[ -z "$URL" ]] && { error "URL cannot be empty"; usage; }

# -----------------------------------------------------------------------------
# 1. Obtain access token (client_credentials)
# -----------------------------------------------------------------------------
info "Requesting access token..."

TOKEN_RESPONSE=$(curl -sf \
  "${KC_BASE_URL}/realms/${KC_REALM}/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=${KC_ADMIN_CLIENT_ID}" \
  -d "client_secret=${KC_ADMIN_CLIENT_SECRET}" \
) || { error "Failed to obtain access token"; exit 1; }

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
[[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]] && { error "Access token is empty/null"; exit 1; }

success "Access token obtained"

# -----------------------------------------------------------------------------
# 2. Get client details
# -----------------------------------------------------------------------------
API_BASE="${KC_BASE_URL}/admin/realms/${KC_REALM}/clients/${KC_CLIENT_ID}"

info "Fetching client details..."

CLIENT_JSON=$(curl -sf \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${API_BASE}" \
) || { error "Failed to fetch client (check KC_CLIENT_ID)"; exit 1; }

CLIENT_NAME=$(echo "$CLIENT_JSON" | jq -r '.clientId // "unknown"')
success "Client found: ${CLIENT_NAME}"

# -----------------------------------------------------------------------------
# 3. Modify redirectUris and webOrigins
# -----------------------------------------------------------------------------
CURRENT_REDIRECTS=$(echo "$CLIENT_JSON" | jq -c '.redirectUris // []')
CURRENT_ORIGINS=$(echo "$CLIENT_JSON" | jq -c '.webOrigins // []')

# Normalize: redirectUri gets /* suffix, origin is scheme+host
REDIRECT_URL="${URL%/\*}/*"
ORIGIN=$(echo "$URL" | sed -E 's|(https?://[^/]+).*|\1|')

if [[ "$ACTION" == "add" ]]; then
  if echo "$CURRENT_REDIRECTS" | jq -e --arg u "$REDIRECT_URL" 'index($u) != null' &>/dev/null; then
    warn "URL already in redirectUris: ${REDIRECT_URL}"
    exit 0
  fi

  NEW_REDIRECTS=$(echo "$CURRENT_REDIRECTS" | jq -c --arg u "$REDIRECT_URL" '. + [$u]')

  if echo "$CURRENT_ORIGINS" | jq -e --arg o "$ORIGIN" 'index($o) != null' &>/dev/null; then
    NEW_ORIGINS="$CURRENT_ORIGINS"
  else
    NEW_ORIGINS=$(echo "$CURRENT_ORIGINS" | jq -c --arg o "$ORIGIN" '. + [$o]')
  fi

  info "Adding redirectUri: ${REDIRECT_URL}"
  info "Adding webOrigin:   ${ORIGIN}"

elif [[ "$ACTION" == "remove" ]]; then
  if echo "$CURRENT_REDIRECTS" | jq -e --arg u "$REDIRECT_URL" 'index($u) == null' &>/dev/null; then
    warn "URL not found in redirectUris: ${REDIRECT_URL}"
    exit 0
  fi

  NEW_REDIRECTS=$(echo "$CURRENT_REDIRECTS" | jq -c --arg u "$REDIRECT_URL" 'map(select(. != $u))')

  # Only remove origin if no other redirectUris share it
  REMAINING_WITH_ORIGIN=$(echo "$NEW_REDIRECTS" | jq --arg o "$ORIGIN" '[.[] | select(startswith($o))] | length')
  if [[ "$REMAINING_WITH_ORIGIN" -eq 0 ]]; then
    NEW_ORIGINS=$(echo "$CURRENT_ORIGINS" | jq -c --arg o "$ORIGIN" 'map(select(. != $o))')
    info "Removing webOrigin: ${ORIGIN}"
  else
    NEW_ORIGINS="$CURRENT_ORIGINS"
    info "Keeping webOrigin (other redirectUris still use it): ${ORIGIN}"
  fi

  info "Removing redirectUri: ${REDIRECT_URL}"
fi

# Build the updated payload
UPDATED_CLIENT=$(echo "$CLIENT_JSON" | jq -c \
  --argjson r "$NEW_REDIRECTS" \
  --argjson o "$NEW_ORIGINS" \
  '.redirectUris = $r | .webOrigins = $o')

# -----------------------------------------------------------------------------
# 4. PUT updated client
# -----------------------------------------------------------------------------
info "Updating client..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$UPDATED_CLIENT" \
  "${API_BASE}" \
) || { error "Failed to update client"; exit 1; }

REDIRECT_COUNT=$(echo "$NEW_REDIRECTS" | jq 'length')
ORIGIN_COUNT=$(echo "$NEW_ORIGINS" | jq 'length')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  success "Client '${CLIENT_NAME}' updated successfully"
  echo ""
  if [[ "$ACTION" == "add" ]]; then
    echo -e "  ${GREEN}+${NC} redirectUri: ${REDIRECT_URL}"
    echo -e "  ${GREEN}+${NC} webOrigin:   ${ORIGIN}"
  else
    echo -e "  ${RED}-${NC} redirectUri: ${REDIRECT_URL}"
    [[ "$NEW_ORIGINS" != "$CURRENT_ORIGINS" ]] && echo -e "  ${RED}-${NC} webOrigin:   ${ORIGIN}"
  fi
  echo ""
  echo "  Total: ${REDIRECT_COUNT} redirectUris, ${ORIGIN_COUNT} webOrigins"
else
  error "Update failed with HTTP ${HTTP_CODE}"
  exit 1
fi
