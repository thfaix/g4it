// Parameters for creating a NEW resource group and deploying the stack into it:
//   az deployment sub create -l francecentral -f infra/main.subscription.bicep -p infra/params/dev.subscription.bicepparam
// Secrets are read from environment variables at build time (never commit secrets):
//   export G4IT_PG_ADMIN_PASSWORD=...   export G4IT_KEYCLOAK_ADMIN_PASSWORD=...
using '../main.subscription.bicep'

param resourceGroupName = 'rg-g4it-dev'
param location = 'francecentral'
param namePrefix = 'g4it'
param environmentName = 'dev'

param postgresAdminPassword = readEnvironmentVariable('G4IT_PG_ADMIN_PASSWORD')
param keycloakAdminPassword = readEnvironmentVariable('G4IT_KEYCLOAK_ADMIN_PASSWORD')

param organizationNames = [ 'SOPRA-STERIA-GROUP', 'SUBSCRIBER-DEMO' ]
param dataPlanePublicAccess = 'Disabled'

param imageTag = 'latest'
param numEcoEvalTag = 'latest'
param deployEcomind = true

param postgresSkuName = 'Standard_B1ms'
param postgresSkuTier = 'Burstable'
param postgresHighAvailability = false
