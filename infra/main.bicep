// G4IT — Azure containerized deployment (resource-group scoped).
// Implements the managed-service mapping from docs/azure-deployment-plan.md and the ADRs in
// docs/architecture/adr. Deploy with: az deployment group create -g <rg> -f main.bicep -p params/<env>.bicepparam
//
// ADR-001 ACA · ADR-002 Bicep · ADR-003 Postgres Flexible · ADR-004 Blob · ADR-005 ACR
// ADR-006 Log Analytics/App Insights · ADR-007 Key Vault + Managed Identity
// ADR-008 Keycloak · ADR-009 VNet + private endpoints · ADR-011 domains/CSP

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Short product prefix used in resource names.')
param namePrefix string = 'g4it'

@description('Environment label (dev/test/prod) used in resource names and tags.')
param environmentName string = 'dev'

@description('Common tags applied to every resource.')
param tags object = {
  product: 'g4it'
  environment: environmentName
  managedBy: 'bicep'
}

// Globally-unique resource names (override per environment if desired).
param acrName string = take(toLower('${namePrefix}${environmentName}acr${uniqueString(resourceGroup().id)}'), 50)
param keyVaultName string = take('${namePrefix}${environmentName}kv${uniqueString(resourceGroup().id)}', 24)
param storageAccountName string = take(toLower('${namePrefix}${environmentName}st${uniqueString(resourceGroup().id)}'), 24)
param postgresServerName string = '${namePrefix}-${environmentName}-pg-${uniqueString(resourceGroup().id)}'

// Database
@description('Postgres administrator login.')
param postgresAdminLogin string = 'g4itadmin'
@secure()
@description('Postgres administrator password.')
param postgresAdminPassword string
param postgresSkuName string = 'Standard_B1ms'
@allowed([ 'Burstable', 'GeneralPurpose', 'MemoryOptimized' ])
param postgresSkuTier string = 'Burstable'
param postgresStorageSizeGB int = 32
param postgresHighAvailability bool = false

// Keycloak
@secure()
@description('Keycloak bootstrap admin password (replaces the compose default admin/password).')
param keycloakAdminPassword string

// Blob / organization
@description('Default organization name; used as the Key Vault secret holding the storage connection string (uppercased, "_"->"-").')
param organizationName string = 'DEMO'
@description('Blob container name (must start with "g4it").')
param blobContainerName string = 'g4it'

// Networking (ADR-009)
@allowed([ 'Enabled', 'Disabled' ])
param dataPlanePublicAccess string = 'Disabled'

// Images (ADR-005). All pulled from ACR after import.
param imageTag string = 'latest'
param backendImageRepository string = 'g4it/backend'
param frontendImageRepository string = 'g4it/frontend'
param keycloakImageRepository string = 'g4it/keycloak'
param numEcoEvalRepositoryPrefix string = 'numecoeval'
// Pinned in lock-step with the backend's org.mte.numecoeval:calculs version (ADR-012);
// imported into ACR by infra/scripts/import-external-images.sh.
param numEcoEvalTag string = '2-2-0'
param boaviztaImageRepository string = 'boavizta/boaviztapi'
param boaviztaImageTag string = '1.3.10'
param ecomindImageRepository string = 'ecomind/ecomindai'
param ecomindImageTag string = '1.1.0'
param deployEcomind bool = false

// Public FQDNs (ADR-011). Leave empty to use the ACA environment default domain.
param frontendCustomFqdn string = ''
param backendCustomFqdn string = ''
param keycloakCustomFqdn string = ''

// ---------------------------------------------------------------------------
// Platform modules
// ---------------------------------------------------------------------------

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    namePrefix: '${namePrefix}-${environmentName}'
    location: location
    tags: tags
  }
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    namePrefix: '${namePrefix}-${environmentName}'
    location: location
    tags: tags
  }
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    namePrefix: '${namePrefix}-${environmentName}'
    location: location
    tags: tags
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  params: {
    name: acrName
    location: location
    tags: tags
    pullPrincipalId: identity.outputs.principalId
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: storageAccountName
    location: location
    tags: tags
    containerName: blobContainerName
    blobContributorPrincipalId: identity.outputs.principalId
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    dnsZoneId: network.outputs.blobDnsZoneId
    publicNetworkAccess: dataPlanePublicAccess
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    vaultUserPrincipalId: identity.outputs.principalId
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    dnsZoneId: network.outputs.keyVaultDnsZoneId
    publicNetworkAccess: dataPlanePublicAccess
    dbPassword: postgresAdminPassword
    keycloakAdminPassword: keycloakAdminPassword
    organizationName: organizationName
    storageAccountName: storage.outputs.name
  }
}

module postgres 'modules/postgres.bicep' = {
  name: 'postgres'
  params: {
    name: postgresServerName
    location: location
    tags: tags
    administratorLogin: postgresAdminLogin
    administratorPassword: postgresAdminPassword
    skuName: postgresSkuName
    skuTier: postgresSkuTier
    storageSizeGB: postgresStorageSizeGB
    highAvailability: postgresHighAvailability
    delegatedSubnetId: network.outputs.postgresSubnetId
    privateDnsZoneId: network.outputs.postgresDnsZoneId
    databases: [ 'keycloak' ]
  }
}

module acaEnv 'modules/aca-environment.bicep' = {
  name: 'aca-environment'
  params: {
    name: '${namePrefix}-${environmentName}-env'
    location: location
    tags: tags
    logAnalyticsWorkspaceName: monitoring.outputs.workspaceName
    infrastructureSubnetId: network.outputs.acaSubnetId
    internal: false
  }
}

// ---------------------------------------------------------------------------
// Derived values
// ---------------------------------------------------------------------------

var acrLoginServer = registry.outputs.loginServer
var vaultUri = keyvault.outputs.vaultUri
var pgFqdn = postgres.outputs.fqdn
var defaultDomain = acaEnv.outputs.defaultDomain

var frontendName = '${namePrefix}-frontend'
var backendName = '${namePrefix}-backend'
var keycloakName = 'keycloak'

var frontendFqdn = empty(frontendCustomFqdn) ? '${frontendName}.${defaultDomain}' : frontendCustomFqdn
var backendFqdn = empty(backendCustomFqdn) ? '${backendName}.${defaultDomain}' : backendCustomFqdn
var keycloakFqdn = empty(keycloakCustomFqdn) ? '${keycloakName}.${defaultDomain}' : keycloakCustomFqdn

var jdbcBase = 'jdbc:postgresql://${pgFqdn}:5432'
var jdbcParams = 'sslmode=require&reWriteBatchedInserts=true'
var dbUrlMain = '${jdbcBase}/postgres?${jdbcParams}'

// DB/Keycloak passwords are passed directly as ACA secrets, NOT Key Vault references: the
// vault is private-endpoint-only, and ACA secret-reference resolution can't reach it, timing
// out at app creation (ADR-007). The values come from the secure deploy params and are also
// seeded into Key Vault for reference/rotation; the backend still reads other secrets (the
// per-org storage connection string) from Key Vault at runtime over the private endpoint.
var dbPasswordSecretRef = [
  {
    name: 'db-password'
    value: postgresAdminPassword
  }
]
var keycloakSecretRefs = [
  {
    name: 'db-password'
    value: postgresAdminPassword
  }
  {
    name: 'keycloak-admin-password'
    value: keycloakAdminPassword
  }
]

// Common NumEcoEval datasource env.
var numEcoEvalDbEnv = [
  { name: 'SERVER_PORT', value: '8080' }
  { name: 'MANAGEMENT_SERVER_PORT', value: '8080' }
  { name: 'SPRING_DATASOURCE_URL', value: dbUrlMain }
  { name: 'SPRING_DATASOURCE_USERNAME', value: postgresAdminLogin }
  { name: 'SPRING_DATASOURCE_PASSWORD', secretRef: 'db-password' }
]

// ---------------------------------------------------------------------------
// Internal apps (deployed first; reached by the backend over internal ingress)
// ---------------------------------------------------------------------------

module apiReferentiel 'modules/container-app.bicep' = {
  name: 'api-referentiel'
  params: {
    name: 'api-referentiel'
    location: location
    tags: tags
    environmentId: acaEnv.outputs.id
    identityId: identity.outputs.id
    acrLoginServer: acrLoginServer
    image: '${acrLoginServer}/${numEcoEvalRepositoryPrefix}/api-referentiel:${numEcoEvalTag}'
    ingressEnabled: true
    external: false
    targetPort: 8080
    cpu: '0.5'
    memory: '1Gi'
    minReplicas: 1
    maxReplicas: 2
    secrets: dbPasswordSecretRef
    env: concat(numEcoEvalDbEnv, [
      { name: 'SPRING_JPA_HIBERNATE_DDLAUTO', value: 'update' }
      { name: 'SPRING_JPA_PROPERTIES_HIBERNATE_JDBC_BATCHSIZE', value: '1000' }
      { name: 'SPRING_JPA_PROPERTIES_HIBERNATE_ORDERINSERTS', value: 'true' }
      { name: 'NUMECOEVAL_URLS_ALLOWED', value: 'http://localhost,http://api-referentiel' }
      { name: 'JAVA_OPTS', value: '-Xms256m -Xmx512m' }
    ])
  }
}

module apiExposition 'modules/container-app.bicep' = {
  name: 'api-expositiondonneesentrees'
  params: {
    name: 'api-expositiondonneesentrees'
    location: location
    tags: tags
    environmentId: acaEnv.outputs.id
    identityId: identity.outputs.id
    acrLoginServer: acrLoginServer
    image: '${acrLoginServer}/${numEcoEvalRepositoryPrefix}/api-expositiondonneesentrees:${numEcoEvalTag}'
    ingressEnabled: true
    external: false
    targetPort: 8080
    cpu: '0.5'
    memory: '1Gi'
    minReplicas: 0
    maxReplicas: 2
    secrets: dbPasswordSecretRef
    env: concat(numEcoEvalDbEnv, [
      { name: 'NUMECOEVAL_REFERENTIEL_SERVER_URL', value: 'http://api-referentiel' }
      { name: 'NUMECOEVAL_CALCULS_SERVER_URL', value: 'http://api-event-calculs' }
      { name: 'SPRING_JPA_PROPERTIES_HIBERNATE_JDBC_BATCHSIZE', value: '1000' }
      { name: 'SPRING_JPA_PROPERTIES_HIBERNATE_ORDERINSERTS', value: 'true' }
      { name: 'NUMECOEVAL_URLS_ALLOWED', value: 'http://localhost,http://api-expositiondonneesentrees' }
      { name: 'REGLEPARDEFAUTDUREEUSAGE', value: 'REEL' }
      { name: 'JAVA_OPTS', value: '-Xms256m -Xmx512m' }
    ])
  }
}

module apiEventDonnees 'modules/container-app.bicep' = {
  name: 'api-event-donneesentrees'
  params: {
    name: 'api-event-donneesentrees'
    location: location
    tags: tags
    environmentId: acaEnv.outputs.id
    identityId: identity.outputs.id
    acrLoginServer: acrLoginServer
    image: '${acrLoginServer}/${numEcoEvalRepositoryPrefix}/api-event-donneesentrees:${numEcoEvalTag}'
    ingressEnabled: true
    external: false
    targetPort: 8080
    cpu: '0.25'
    memory: '0.5Gi'
    minReplicas: 0
    maxReplicas: 1
    secrets: dbPasswordSecretRef
    env: concat(numEcoEvalDbEnv, [
      { name: 'JAVA_OPTS', value: '-Xms90m -Xmx256m' }
    ])
  }
}

module apiEventCalculs 'modules/container-app.bicep' = {
  name: 'api-event-calculs'
  params: {
    name: 'api-event-calculs'
    location: location
    tags: tags
    environmentId: acaEnv.outputs.id
    identityId: identity.outputs.id
    acrLoginServer: acrLoginServer
    image: '${acrLoginServer}/${numEcoEvalRepositoryPrefix}/api-event-calculs:${numEcoEvalTag}'
    ingressEnabled: true
    external: false
    targetPort: 8080
    cpu: '0.25'
    memory: '0.5Gi'
    minReplicas: 0
    maxReplicas: 2
    secrets: dbPasswordSecretRef
    env: concat(numEcoEvalDbEnv, [
      { name: 'NUMECOEVAL_REFERENTIELS_URL', value: 'http://api-referentiel' }
      { name: 'NUMECOEVAL_URLS_ALLOWED', value: 'http://localhost,http://api-event-calculs' }
      { name: 'JAVA_OPTS', value: '-Xms140m -Xmx320m' }
    ])
  }
}

module boavizta 'modules/container-app.bicep' = {
  name: 'boaviztapi'
  params: {
    name: 'boaviztapi'
    location: location
    tags: tags
    environmentId: acaEnv.outputs.id
    identityId: identity.outputs.id
    acrLoginServer: acrLoginServer
    image: '${acrLoginServer}/${boaviztaImageRepository}:${boaviztaImageTag}'
    ingressEnabled: true
    external: false
    targetPort: 5000
    cpu: '0.25'
    memory: '0.5Gi'
    minReplicas: 0
    maxReplicas: 1
    env: []
    secrets: []
  }
}

module ecomind 'modules/container-app.bicep' = if (deployEcomind) {
  name: 'ecomind-api'
  params: {
    name: 'ecomind-api'
    location: location
    tags: tags
    environmentId: acaEnv.outputs.id
    identityId: identity.outputs.id
    acrLoginServer: acrLoginServer
    image: '${acrLoginServer}/${ecomindImageRepository}:${ecomindImageTag}'
    ingressEnabled: true
    external: false
    targetPort: 8000
    cpu: '0.25'
    memory: '0.5Gi'
    minReplicas: 0
    maxReplicas: 1
    env: []
    secrets: []
  }
}

// ---------------------------------------------------------------------------
// Public apps (ADR-008, ADR-011)
// ---------------------------------------------------------------------------

module keycloak 'modules/container-app.bicep' = {
  name: keycloakName
  params: {
    name: keycloakName
    location: location
    tags: tags
    environmentId: acaEnv.outputs.id
    identityId: identity.outputs.id
    acrLoginServer: acrLoginServer
    image: '${acrLoginServer}/${keycloakImageRepository}:${imageTag}'
    ingressEnabled: true
    external: true
    targetPort: 8180
    cpu: '0.5'
    memory: '1Gi'
    minReplicas: 1
    maxReplicas: 1
    secrets: keycloakSecretRefs
    env: [
      { name: 'KEYCLOAK_DATABASE_HOST', value: pgFqdn }
      { name: 'KEYCLOAK_DATABASE_PORT', value: '5432' }
      { name: 'KEYCLOAK_DATABASE_NAME', value: 'keycloak' }
      { name: 'KEYCLOAK_DATABASE_USER', value: postgresAdminLogin }
      { name: 'KEYCLOAK_DATABASE_PASSWORD', secretRef: 'db-password' }
      { name: 'KEYCLOAK_JDBC_PARAMS', value: 'sslmode=require' }
      { name: 'KEYCLOAK_HTTP_RELATIVE_PATH', value: '/auth/' }
      { name: 'KEYCLOAK_HTTP_PORT', value: '8180' }
      { name: 'KEYCLOAK_BIND_ADDRESS', value: '0.0.0.0' }
      { name: 'KEYCLOAK_ADMIN', value: 'admin' }
      { name: 'KEYCLOAK_ADMIN_PASSWORD', secretRef: 'keycloak-admin-password' }
      { name: 'KEYCLOAK_PRODUCTION', value: 'true' }
      { name: 'KEYCLOAK_PROXY', value: 'edge' }
      { name: 'KEYCLOAK_HOSTNAME', value: 'https://${keycloakFqdn}/auth' }
      { name: 'KEYCLOAK_EXTRA_ARGS', value: '--import-realm --spi-theme-static-max-age=-1 --spi-theme-cache-themes=false --spi-theme-cache-templates=false' }
      { name: 'JAVA_OPTS_APPEND', value: '-Xms512m -Xmx512m' }
    ]
  }
}

module backend 'modules/container-app.bicep' = {
  name: backendName
  params: {
    name: backendName
    location: location
    tags: tags
    environmentId: acaEnv.outputs.id
    identityId: identity.outputs.id
    acrLoginServer: acrLoginServer
    image: '${acrLoginServer}/${backendImageRepository}:${imageTag}'
    ingressEnabled: true
    external: true
    targetPort: 8080
    cpu: '1.0'
    memory: '2Gi'
    minReplicas: 1
    maxReplicas: 5
    secrets: dbPasswordSecretRef
    env: [
      { name: 'SPRING_PROFILES_ACTIVE', value: 'azure,postgres' }
      { name: 'SPRING_DATASOURCE_URL', value: dbUrlMain }
      { name: 'SPRING_DATASOURCE_USERNAME', value: postgresAdminLogin }
      { name: 'SPRING_DATASOURCE_PASSWORD', secretRef: 'db-password' }
      { name: 'SPRING_DATASOURCE_HIKARI_MINIMUMIDLE', value: '2' }
      { name: 'SPRING_DATASOURCE_HIKARI_MAXIMUMPOOLSIZE', value: '5' }
      { name: 'SPRING_JPA_HIBERNATE_DDLAUTO', value: 'none' }
      { name: 'SPRING_LIQUIBASE_CONTEXTS', value: '!dev' }
      { name: 'SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI', value: 'https://${keycloakFqdn}/auth/realms/g4it' }
      { name: 'CORS_ALLOWED_ORIGINS', value: 'https://${frontendFqdn}' }
      { name: 'NUMECOEVAL_BASEURL', value: 'http://api-expositiondonneesentrees' }
      { name: 'NUMECOEVALREFERENTIAL_BASEURL', value: 'http://api-referentiel' }
      { name: 'BOAVIZTAPI_BASEURL', value: 'http://boaviztapi' }
      { name: 'NUMECOEVAL_IMPORTMAXMEMORY', value: '128' }
      { name: 'FILESYSTEM_UPLOAD_MAXUPLOADSIZE', value: '104857600' }
      { name: 'BATCH_LOCAL_WORKING_FOLDER_BASE_PATH', value: '/tmp' }
      { name: 'LOCAL_WORKING_FOLDER', value: '/tmp/storagetmp' }
      { name: 'G4IT_STORAGE_RETENTION_CRON', value: '0 0 7 * * *' }
      { name: 'G4IT_STORAGE_RETENTION_ONINIT', value: 'false' }
      { name: 'G4IT_STORAGE_RETENTION_DAY_EXPORT', value: '7' }
      { name: 'G4IT_STORAGE_RETENTION_DAY_OUTPUT', value: '90' }
      { name: 'G4IT_DATA_RETENTION_CRON', value: '0 30 7 * * *' }
      { name: 'G4IT_DATA_RETENTION_ONINIT', value: 'false' }
      { name: 'G4IT_DATA_RETENTION_DAY', value: '730' }
      // Azure profile: Key Vault + user-assigned managed identity (ADR-007)
      { name: 'AZURE_SUBSCRIPTION_ID', value: subscription().subscriptionId }
      { name: 'AZURE_TENANT_ID', value: tenant().tenantId }
      { name: 'AZURE_CLIENT_ID', value: identity.outputs.clientId }
      { name: 'SPRING_CLOUD_AZURE_CREDENTIAL_MANAGED_IDENTITY_ENABLED', value: 'true' }
      { name: 'SPRING_CLOUD_AZURE_KEYVAULT_SECRET_ENDPOINT', value: vaultUri }
    ]
  }
}

module frontend 'modules/container-app.bicep' = {
  name: frontendName
  params: {
    name: frontendName
    location: location
    tags: tags
    environmentId: acaEnv.outputs.id
    identityId: identity.outputs.id
    acrLoginServer: acrLoginServer
    image: '${acrLoginServer}/${frontendImageRepository}:${imageTag}'
    ingressEnabled: true
    external: true
    targetPort: 4200
    cpu: '0.25'
    memory: '0.5Gi'
    minReplicas: 1
    maxReplicas: 3
    secrets: []
    env: [
      { name: 'KEYCLOAK_URL', value: 'https://${keycloakFqdn}/auth' }
      { name: 'KEYCLOAK_ENABLED', value: 'true' }
      { name: 'URL_INVENTORY', value: 'https://${backendFqdn}/' }
      { name: 'FRONTEND_URL', value: 'https://${frontendFqdn}' }
      { name: 'SUB_PATH_FRONT', value: '/' }
      { name: 'BASE_HREF', value: '/' }
      { name: 'MATOMO_TAG_MANAGER_URL', value: '' }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output acrLoginServer string = acrLoginServer
output keyVaultUri string = vaultUri
output postgresFqdn string = pgFqdn
output acaEnvironmentDefaultDomain string = defaultDomain
output frontendUrl string = 'https://${frontendFqdn}'
output backendUrl string = 'https://${backendFqdn}'
output keycloakUrl string = 'https://${keycloakFqdn}/auth'
