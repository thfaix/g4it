#!/usr/bin/env sh
ME=$(basename $0)

# Default env vars
if ! printenv | grep -q "KEYCLOAK_ENABLED";then
  export KEYCLOAK_ENABLED="true"
fi

export EXISTING_VARS=$(printenv | awk -F= '{print $1}' | sed 's/^/\$/g' | paste -sd,);
FILES=$(ls $JSFOLDER/*.js $JSFOLDER/*.html);

echo "$ME: info: injecting $EXISTING_VARS"
for file in $FILES;
do
  cp $file /tmp/tmpfile
  envsubst $EXISTING_VARS < /tmp/tmpfile > $file
done

# ADR-013: render the Content-Security-Policy for the cross-origin backend/Keycloak calls.
# The browser calls the backend (URL_INVENTORY) and Keycloak (KEYCLOAK_URL) at their public
# origins, which differ per environment. Derive each scheme://host origin and inject it into
# the nginx CSP: connect-src (XHR/fetch to both) and frame-src (Keycloak silent-SSO iframe).
NGINX_CONF=/etc/nginx/nginx.conf

origin_of() {
  # Keep scheme://host[:port]; drop any path/query. Empty input -> empty output.
  printf '%s' "$1" | sed -n -E 's#^([a-zA-Z][a-zA-Z0-9+.-]*://[^/]+).*#\1#p'
}

BACKEND_ORIGIN=$(origin_of "$URL_INVENTORY")
KEYCLOAK_ORIGIN=$(origin_of "$KEYCLOAK_URL")

# 'self' stays in nginx.conf; substitute only the extra origins (exact scheme+host, no wildcards).
CSP_CONNECT_SRC=$(echo "$BACKEND_ORIGIN $KEYCLOAK_ORIGIN" | xargs)
CSP_FRAME_SRC="$KEYCLOAK_ORIGIN"
export CSP_CONNECT_SRC CSP_FRAME_SRC

echo "$ME: info: CSP connect-src='$CSP_CONNECT_SRC' frame-src='$CSP_FRAME_SRC'"

cp "$NGINX_CONF" /tmp/nginx.conf.tmpl
# Restrict envsubst to the CSP placeholders so nginx's own $variables are preserved.
envsubst '$CSP_CONNECT_SRC $CSP_FRAME_SRC' < /tmp/nginx.conf.tmpl > "$NGINX_CONF"

# Fail fast on an invalid rendered config rather than serving a broken policy.
if ! nginx -t; then
  echo "$ME: error: rendered $NGINX_CONF failed validation" >&2
  exit 1
fi

exit 0
