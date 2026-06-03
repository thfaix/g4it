// ADR-005: Azure Container Registry — single registry for the 3 built images and the
// 6 imported external images. The shared managed identity is granted AcrPull.

@description('Globally-unique ACR name (alphanumeric, 5-50 chars).')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@allowed([
  'Basic'
  'Standard'
  'Premium'
])
@description('ACR SKU. Premium is required for private endpoints / geo-replication.')
param sku string = 'Standard'

@description('Principal id of the managed identity that pulls images.')
param pullPrincipalId string

// Built-in role: AcrPull
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: false
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, pullPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: pullPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output loginServer string = registry.properties.loginServer
output name string = registry.name
