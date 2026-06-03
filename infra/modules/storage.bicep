// ADR-004: Storage account + a 'g4it'-prefixed blob container for backend file storage.
// The shared managed identity is granted "Storage Blob Data Contributor"; the account is
// reached over a private endpoint (ADR-009). The connection string is stored in Key Vault
// (see keyvault.bicep) because the backend resolves it per organization at runtime.

@description('Globally-unique storage account name (3-24 lowercase alphanumeric).')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Blob container name. Must start with "g4it" (AzureFileSystem container prefix).')
param containerName string = 'g4it'

@description('Principal id of the managed identity granted Storage Blob Data Contributor.')
param blobContributorPrincipalId string

@description('Private endpoint subnet id.')
param privateEndpointSubnetId string

@description('Private DNS zone id for blob.')
param dnsZoneId string

@allowed([
  'Enabled'
  'Disabled'
])
@description('Public network access. Disabled keeps the account private (ADR-009).')
param publicNetworkAccess string = 'Disabled'

// Built-in role: Storage Blob Data Contributor
var blobContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: publicNetworkAccess == 'Enabled' ? 'Allow' : 'Deny'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

resource blobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, blobContributorPrincipalId, blobContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobContributorRoleId)
    principalId: blobContributorPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${name}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-plsc'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: dnsZoneId
        }
      }
    ]
  }
}

output name string = storageAccount.name
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
