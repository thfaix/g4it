// ADR-007: Key Vault (RBAC mode) holding the secrets the apps consume. The shared managed
// identity is granted "Key Vault Secrets User". Reached over a private endpoint (ADR-009).
//
// Seeded secrets:
//   - db-password               : Postgres admin password (backend + keycloak)
//   - keycloak-admin-password   : Keycloak bootstrap admin password
//   - <ORGANIZATION>            : storage connection string for the default organization.
//     The backend's AzureFileSystem fetches this by organization name (uppercased, '_'->'-')
//     and then lists the 'g4it'-prefixed blob container (see VaultAccessClient).

@description('Globally-unique Key Vault name (3-24 chars).')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Principal id of the managed identity granted Key Vault Secrets User.')
param vaultUserPrincipalId string

@description('Private endpoint subnet id.')
param privateEndpointSubnetId string

@description('Private DNS zone id for vaultcore.')
param dnsZoneId string

@description('Public network access. Disabled keeps the vault private (ADR-009).')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@secure()
@description('Postgres admin password.')
param dbPassword string

@secure()
@description('Keycloak bootstrap admin password.')
param keycloakAdminPassword string

@description('Default organization name; used as the secret name (uppercased, "_"->"-").')
param organizationName string

@description('Name of the storage account whose connection string is stored for the org.')
param storageAccountName string

// Built-in role: Key Vault Secrets User
var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var organizationSecretName = toUpper(replace(organizationName, '_', '-'))

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: publicNetworkAccess == 'Enabled' ? 'Allow' : 'Deny'
    }
  }
}

resource secretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, vaultUserPrincipalId, secretsUserRoleId)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsUserRoleId)
    principalId: vaultUserPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource dbPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'db-password'
  properties: {
    value: dbPassword
  }
}

resource keycloakAdminSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'keycloak-admin-password'
  properties: {
    value: keycloakAdminPassword
  }
}

resource organizationConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: organizationSecretName
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
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
          privateLinkServiceId: vault.id
          groupIds: [
            'vault'
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
        name: 'vaultcore'
        properties: {
          privateDnsZoneId: dnsZoneId
        }
      }
    ]
  }
}

output vaultUri string = vault.properties.vaultUri
output name string = vault.name
