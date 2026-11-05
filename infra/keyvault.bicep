// Shared Key Vault for the labs (Solo 1.1, step 8).
// Created early so Solo 1.3 (Fabric notebook) can read the NROD credentials before the bridge exists.
// The name, properties and role-assignment names deliberately MATCH infra/main.bicep, so Solo 1.7
// re-uses this vault instead of creating a second one (same resource group + namePrefix).
targetScope = 'resourceGroup'

param location string = resourceGroup().location

@description('Prefix used for resource names. Must match NAME_PREFIX used later in Solo 1.7.')
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
var roleKvSecretsOfficer = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

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
