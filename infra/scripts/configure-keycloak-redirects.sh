#!/usr/bin/env bash
#
# configure-keycloak-redirects.sh — register an environment's public frontend URL with the
# Keycloak `g4it` realm's browser client(s).
#
# The shared realm export (services/keycloak/imports/g4it-realm-export.json) ships with
# localhost-only redirect URIs, and Keycloak imports with IGNORE_EXISTING (so editing the
# export won't update an already-imported realm). On a real deployment the browser logs in
# from the environment's frontend FQDN, so that origin must be added to the client's
# Valid Redirect URIs / Web Origins or login fails with `invalid redirect_uri` (ADR-008/011).
#
# This is the per-environment, repeatable post-deploy step. It targets every g4it client that
# still has a localhost redirect (the public/browser clients) and adds the frontend origin.
#
# Usage:
#   ./configure-keycloak-redirects.sh <resource-group> <keycloak-app-name> <frontend-url>
# Example:
#   ./configure-keycloak-redirects.sh rg-g4it-dev keycloak https://g4it-frontend.<env>.azurecontainerapps.io
#
# Requires: az CLI (logged in), python3. Reads the Keycloak admin password from the
# keycloak container app's ACA secret — no password on the command line.

set -euo pipefail

RG="${1:?resource group required}"
KC_APP="${2:?keycloak container app name required}"
FRONTEND_URL="${3:?frontend base url required (e.g. https://app.example)}"
REALM="${KEYCLOAK_REALM:-g4it}"
FRONTEND_URL="${FRONTEND_URL%/}"   # strip trailing slash

KC_FQDN=$(az containerapp show -g "$RG" -n "$KC_APP" --query "properties.configuration.ingress.fqdn" -o tsv | tr -d '\r')
KC_BASE="https://${KC_FQDN}/auth"
ADMIN_PW=$(az containerapp secret show -g "$RG" -n "$KC_APP" --secret-name keycloak-admin-password --query value -o tsv | tr -d '\r')

echo "Keycloak: ${KC_BASE} | realm: ${REALM} | adding redirect for: ${FRONTEND_URL}"

python3 - "$KC_BASE" "$REALM" "$ADMIN_PW" "$FRONTEND_URL" <<'PY'
import json, sys, urllib.request, urllib.parse, urllib.error

base, realm, pw, frontend = sys.argv[1:5]

def call(method, url, data=None, token=None, form=False):
    headers = {}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    body = None
    if data is not None:
        if form:
            body = urllib.parse.urlencode(data).encode()
            headers['Content-Type'] = 'application/x-www-form-urlencoded'
        else:
            body = json.dumps(data).encode()
            headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else None

try:
    token = call('POST', f'{base}/realms/master/protocol/openid-connect/token',
                 data={'client_id': 'admin-cli', 'username': 'admin',
                       'password': pw, 'grant_type': 'password'}, form=True)['access_token']
except urllib.error.HTTPError as e:
    sys.exit(f'failed to get admin token ({e.code}): {e.read().decode()[:200]}')

clients = call('GET', f'{base}/admin/realms/{realm}/clients', token=token)
redirect = f'{frontend}/*'
changed = []
for c in clients:
    ru = c.get('redirectUris') or []
    if not any('localhost' in u for u in ru):
        continue  # only the browser/public clients that still point at localhost
    new_ru = ru if redirect in ru else ru + [redirect]
    wo = c.get('webOrigins') or []
    new_wo = wo if ('*' in wo or frontend in wo) else wo + [frontend]
    if new_ru == ru and new_wo == wo:
        continue
    c['redirectUris'] = new_ru
    c['webOrigins'] = new_wo
    call('PUT', f'{base}/admin/realms/{realm}/clients/{c["id"]}', data=c, token=token)
    changed.append(c.get('clientId'))

print('updated clients:', ', '.join(changed) if changed else 'none (nothing to change)')
PY
