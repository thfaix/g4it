// ADR-009: VNet for the ACA environment, the Postgres flexible server (VNet-integrated),
// and private endpoints (Key Vault, Blob). Private DNS zones resolve the data-plane PaaS
// resources to their private IPs from inside the VNet.

@description('Base name for the network resources.')
param namePrefix string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('VNet address space.')
param addressPrefix string = '10.40.0.0/24'

@description('Subnet delegated to the ACA managed environment (workload profiles need >= /27).')
param acaSubnetPrefix string = '10.40.0.0/27'

@description('Subnet delegated to the Postgres flexible server.')
param postgresSubnetPrefix string = '10.40.0.32/28'

@description('Subnet hosting private endpoints (Key Vault, Blob).')
param privateEndpointSubnetPrefix string = '10.40.0.64/27'

var blobDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var keyVaultDnsZoneName = 'privatelink.vaultcore.azure.net'
var postgresDnsZoneName = 'privatelink.postgres.database.azure.com'

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: '${namePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-aca'
        properties: {
          addressPrefix: acaSubnetPrefix
          delegations: [
            {
              name: 'aca-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-postgres'
        properties: {
          addressPrefix: postgresSubnetPrefix
          delegations: [
            {
              name: 'postgres-delegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource blobDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: blobDnsZoneName
  location: 'global'
  tags: tags
}

resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: keyVaultDnsZoneName
  location: 'global'
  tags: tags
}

resource postgresDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: postgresDnsZoneName
  location: 'global'
  tags: tags
}

resource blobDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: blobDnsZone
  name: 'link-to-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource keyVaultDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultDnsZone
  name: 'link-to-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource postgresDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: postgresDnsZone
  name: 'link-to-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

output acaSubnetId string = vnet.properties.subnets[0].id
output postgresSubnetId string = vnet.properties.subnets[1].id
output privateEndpointSubnetId string = vnet.properties.subnets[2].id
output blobDnsZoneId string = blobDnsZone.id
output keyVaultDnsZoneId string = keyVaultDnsZone.id
output postgresDnsZoneId string = postgresDnsZone.id
