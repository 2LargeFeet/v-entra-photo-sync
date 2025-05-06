# v-entra-photo-sync
Sync photos from Entra ID to Verkada

# To Use
./photoSync.ps1 -tenantId "Azure Tenant ID" -clientId "Azure Client ID" -clientSecret "Azure App Registration Secret" -verkadaApiKey "Verkada Api Key"

# To build and run as a docker container

docker build -t v-entra-photo-sync -f docker/Dockerfile .
docker run -e $tenantId="your tenant ID" -e $clientId="your client ID" -e $clientSecret="your secret value" -e $verkadaApiKey="your Verkada Api Key" v-entra-photo-sync
