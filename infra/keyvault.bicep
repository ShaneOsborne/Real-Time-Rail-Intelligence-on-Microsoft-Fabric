// Shared Key Vault for the labs (Lab 01, step 8).
// Created early so Lab 03 (Fabric notebook) can read the NROD credentials before the bridge exists.
// The name, properties and role-assignment names deliberately MATCH infra/main.bicep, so Lab 05b
// re-uses this vault instead of creating a second one (same resource group + namePrefix).
targetScope = 'resourceGroup'

param location string = resourceGroup().location

@description('Prefix used for resource names. Must match NAME_PREFIX used later in Lab 05b.')
param namePrefix string = 'railrti'

@description('Optional: explicit vault name. Leave empty to use the generated name shared with main.bicep.')
param keyVaultName string = ''

@description('Object ID of the person/pipeline running the deployment; granted Key Vault Secrets Officer (read + write secrets).')
param deployerPrincipalId string = ''

@allowed([ 'User', 'ServicePrincipal', 'Group' ])
param deployerPrincipalType string = 'User'

param tags object = {
  project: 'rail-fabric-rti'
}

var suffix = uniqueString(resourceGroup().id, namePrefix)
var kvName = !empty(keyVaultName) ? keyVaultName : take('${namePrefix}kv${suffix}', 24)
var roleKvSecretsOfficer = 'b86a8fe4-95b2-4a9a-9c4d-7de2ae5e7b32'

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

resource kvSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(kv.id, deployerPrincipalId, roleKvSecretsOfficer)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleKvSecretsOfficer)
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
  }
}

output keyVaultName string = kv.name
output keyVaultUri string = kv.properties.vaultUri
