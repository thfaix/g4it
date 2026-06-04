// Subscription-scoped entrypoint: creates a NEW resource group and deploys the full G4IT
// stack into it (main.bicep). Use this when you want the resource group created as part of
// the deployment. If the resource group already exists, deploy main.bicep directly instead.
//
//   az deployment sub create -l <region> -f infra/main.subscription.bicep -p infra/params/dev.bicepparam
//
// Note: the params file targets this entrypoint's parameters (resourceGroupName, location, ...).

targetScope = 'subscription'

@description('Name of the resource group to create.')
param resourceGroupName string = 'rg-g4it-dev'

@description('Azure region for the resource group and all resources.')
param location string

@description('Short product prefix used in resource names.')
param namePrefix string = 'g4it'

@description('Environment label (dev/test/prod).')
param environmentName string = 'dev'

@description('Common tags applied to the resource group and every resource.')
param tags object = {
  product: 'g4it'
  environment: environmentName
  managedBy: 'bicep'
}

@secure()
@description('Postgres administrator password.')
param postgresAdminPassword string

@secure()
@description('Keycloak bootstrap admin password.')
param keycloakAdminPassword string

@description('Default organization name (Key Vault secret holding the storage connection string).')
param organizationName string = 'DEMO'

@allowed([ 'Enabled', 'Disabled' ])
param dataPlanePublicAccess string = 'Disabled'

param imageTag string = 'latest'
param numEcoEvalTag string = '2-2-0'
param deployEcomind bool = false

param frontendCustomFqdn string = ''
param backendCustomFqdn string = ''
param keycloakCustomFqdn string = ''

param postgresSkuName string = 'Standard_B1ms'
@allowed([ 'Burstable', 'GeneralPurpose', 'MemoryOptimized' ])
param postgresSkuTier string = 'Burstable'
param postgresHighAvailability bool = false

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module stack 'main.bicep' = {
  name: 'g4it-stack'
  scope: resourceGroup
  params: {
    location: location
    namePrefix: namePrefix
    environmentName: environmentName
    tags: tags
    postgresAdminPassword: postgresAdminPassword
    keycloakAdminPassword: keycloakAdminPassword
    organizationName: organizationName
    dataPlanePublicAccess: dataPlanePublicAccess
    imageTag: imageTag
    numEcoEvalTag: numEcoEvalTag
    deployEcomind: deployEcomind
    frontendCustomFqdn: frontendCustomFqdn
    backendCustomFqdn: backendCustomFqdn
    keycloakCustomFqdn: keycloakCustomFqdn
    postgresSkuName: postgresSkuName
    postgresSkuTier: postgresSkuTier
    postgresHighAvailability: postgresHighAvailability
  }
}

output resourceGroupName string = resourceGroup.name
output frontendUrl string = stack.outputs.frontendUrl
output backendUrl string = stack.outputs.backendUrl
output keycloakUrl string = stack.outputs.keycloakUrl
output acrLoginServer string = stack.outputs.acrLoginServer
