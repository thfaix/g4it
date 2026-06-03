// ADR-003: Azure Database for PostgreSQL Flexible Server (VNet-integrated, ADR-009).
// Hosts the 'postgres' database (g4it + numecoeval) — created automatically — and a
// 'keycloak' database. PostgreSQL 15 matches the compose image and the Liquibase changelogs.

@description('Flexible server name (globally-unique within the region).')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('PostgreSQL major version.')
param version string = '15'

@description('Administrator login.')
param administratorLogin string

@secure()
@description('Administrator password.')
param administratorPassword string

@description('Compute SKU, e.g. Standard_B1ms (dev) / Standard_D2ds_v5 (prod).')
param skuName string = 'Standard_B1ms'

@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param skuTier string = 'Burstable'

@description('Storage size in GB.')
param storageSizeGB int = 32

@description('Delegated subnet id for VNet integration.')
param delegatedSubnetId string

@description('Private DNS zone id for postgres.database.azure.com.')
param privateDnsZoneId string

@description('Enable zone-redundant HA (prod). Burstable tier does not support HA.')
param highAvailability bool = false

@description('Databases to create in addition to the default "postgres" database.')
param databases array = [
  'keycloak'
]

@description('max_connections (static parameter — applied on server restart). B1ms default is 50.')
param maxConnections int = 100

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: version
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    storage: {
      storageSizeGB: storageSizeGB
    }
    network: {
      delegatedSubnetResourceId: delegatedSubnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
      publicNetworkAccess: 'Disabled'
    }
    highAvailability: {
      mode: highAvailability ? 'ZoneRedundant' : 'Disabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
  }
}

resource db 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = [
  for dbName in databases: {
    parent: server
    name: dbName
    properties: {
      charset: 'UTF8'
      collation: 'en_US.utf8'
    }
  }
]

// Raise max_connections for the shared dev DB. Static parameter — takes effect on restart.
// dependsOn the databases so the change isn't applied concurrently with other server ops.
resource maxConnectionsConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: server
  name: 'max_connections'
  properties: {
    value: string(maxConnections)
    source: 'user-override'
  }
  dependsOn: [db]
}

output fqdn string = server.properties.fullyQualifiedDomainName
output name string = server.name
