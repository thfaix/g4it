// ADR-007: user-assigned managed identity shared by the container apps.
// Role assignments (AcrPull, Key Vault Secrets User, Storage Blob Data Contributor)
// live with their scoped resources (registry/keyvault/storage modules).

@description('Base name for the identity.')
param namePrefix string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-id'
  location: location
  tags: tags
}

output id string = identity.id
output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
