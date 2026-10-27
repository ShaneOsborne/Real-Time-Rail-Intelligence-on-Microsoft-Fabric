// Lab 11b: Azure Maps account (Gen2) for the Rayfin app's basemap (road, grayscale, night and satellite styles).
// Also creates the user-assigned managed identity that SAS tokens are issued for. The data-role assignment for that
// identity is done by scripts/create-azure-maps.* (by role name), so this file needs no role GUIDs.
@description('Region for the Maps account and its identity (must be the same). Check Microsoft.Maps availability.')
param location string
@description('Prefix used for resource names (NAME_PREFIX in .env).')
param namePrefix string = 'railrti'
@description('Browser origins allowed to call Azure Maps (CORS). Your Rayfin static hosting URL and http://localhost:5173.')
param allowedOrigins array = []

var suffix = uniqueString(resourceGroup().id)
var mapsName = '${namePrefix}-maps-${suffix}'

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-maps-sas-id'
  location: location
}

resource maps 'Microsoft.Maps/accounts@2023-06-01' = {
  name: mapsName
  location: location
  sku: { name: 'G2' }
  kind: 'Gen2'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    disableLocalAuth: false // SAS tokens need local auth
    cors: empty(allowedOrigins) ? null : { corsRules: [ { allowedOrigins: allowedOrigins } ] }
  }
}

output mapsAccountName string = maps.name
output mapsAccountId string = maps.id
output identityPrincipalId string = identity.properties.principalId
output identityName string = identity.name
