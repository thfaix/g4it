# A example build step that downloads a JAR file from a URL and adds it to the providers directory
FROM bitnamilegacy/keycloak:26.0.7

# Add the provider JAR file to the providers directory
COPY --chown=keycloak:keycloak extensions/ /opt/bitnami/keycloak/providers/
COPY --chown=keycloak:keycloak themes/ /opt/bitnami/keycloak/themes/
# Bake the realm export into the image so `--import-realm` finds it on platforms without a
# volume mount (e.g. Azure Container Apps). Compose mounts this dir; ACA cannot.
COPY --chown=keycloak:keycloak imports/ /opt/bitnami/keycloak/data/import/

USER keycloak
