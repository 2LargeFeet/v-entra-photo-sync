# === CONFIGURATION ===

### This application requires an App registration in Azure with the following permissions
### - User.Read (delegated)
### - User.ReadAll
### - User.ReadBasic.All

param(
    [string]$tenantId,
    [string]$clientId,
    [string]$clientSecret,
    [string]$verkadaApiKey
)

$graphScope = "https://graph.microsoft.com/.default"
$verkadaBaseUrl = "https://api.verkada.com"

$tempPhotoPath = "entra_photos"
New-Item -ItemType Directory -Force -Path $tempPhotoPath | Out-Null

$maxIterations = 1000
$iterationCount = 0

# === FUNCTIONS ===
function Write-Log {
    param (
        [string]$Message,
        [string]$LogPath = "photoSyncLog.txt"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "[$Timestamp] $Message"
}

function Get-VerkadaApiToken {
    param ([string]$ApiKey)
    $response = Invoke-RestMethod -Method Post -Uri "$verkadaBaseUrl/token" -Headers @{
        "x-api-key" = $ApiKey
    }
    return $response.token
}

function Get-VerkadaHeaders {
    return @{
        "x-verkada-auth" = "$verkadaApiToken"
    }
}

function Get-EntraToken {
    Write-Host "Authenticating to Microsoft Graph..."
    $graphTokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
    $graphTokenResponse = Invoke-RestMethod -Method Post -Uri $graphTokenUrl -Body @{
        client_id     = $clientId
        scope         = $graphScope
        client_secret = $clientSecret
        grant_type    = "client_credentials"
    }
   $entraToken = $graphTokenResponse.access_token
   return $entraToken
}
$graphToken = Get-EntraToken

# Authenticate to Verkada
Write-Host "Authenticating to Verkada API..."
$verkadaApiToken = Get-VerkadaApiToken -ApiKey $verkadaApiKey
$verkadaHeaders = Get-VerkadaHeaders

Write-Host "Retrieving users from Verkada..."
$verkadaUsersUrl = "$verkadaBaseUrl/access/v1/access_users"
$verkadaUsersResponse = Invoke-RestMethod -Uri $verkadaUsersUrl -Method GET -Headers $verkadaHeaders -StatusCodeVariable "getUsersStatus"
$verkadaUsers = $verkadaUsersResponse.access_members

if (-not $verkadaUsers) {
    Write-Log -Message "No users found in Verkada Access Control | Get Users code : $getUsersStatus"
    exit
}

foreach ($user in $verkadaUsers) {
    if ($iterationCount -ge $maxIterations) {
        Write-Host "Threshold reached ($iterationCount iterations, $($stopwatch.Elapsed.Minutes) mins). Re-authenticating..." -ForegroundColor Yellow

        $graphToken = Get-EntraToken

        $iterationCount = 0
    }

    if (-not $user.email) {
        Write-Log -Message "User $($user.full_name) has no email. Skipping"
        continue
    }

    $email = $user.email
    Write-Host "Processing $email..."

    # Look up Entra ID user by email
    $entraUserUrl = "https://graph.microsoft.com/v1.0/users/$email"
    try {
        $entraUser = Invoke-RestMethod -Uri $entraUserUrl -StatusCodeVariable "emailStatus" -Headers @{
            Authorization = "Bearer $graphToken"
        }
        Write-Log -Message "$email email found in Entra ID | Email Status Code : $emailStatus"
    }
    catch {
        Write-Log -Message "$email email not found in Entra ID | Email Status Code : $emailStatus"
        continue
    }

    # Download user photo
    $photoUrl = "https://graph.microsoft.com/v1.0/users/$($entraUser.id)/photo/`$value"
    $photoPath = Join-Path $tempPhotoPath "$email.jpg"

    try {
        Invoke-RestMethod -Uri $photoUrl -Headers @{ Authorization = "Bearer $graphToken" } -OutFile $photoPath -StatusCodeVariable "downloadStatus"
        Write-Log -Message "$email photo found and downloaded | Download Status Code : $downloadStatus"
    }
    catch {
        Write-Log -Message "$email photo not found | Download Status Code : $downloadStatus"
        continue
    }

    # Upload photo to Verkada
    $uploadUrl = "$verkadaBaseUrl/access/v1/access_users/user/profile_photo?user_id=$($user.user_id)&overwrite=true"
    $formFields = @{
        file = Get-Item $photoPath
    }

    try {
        Invoke-RestMethod -Method Put -Uri $uploadUrl -Headers $verkadaHeaders -Form $formFields -ContentType "multipart/form-data" -StatusCodeVariable "uploadStatus" 
        Write-Log -Message "$email photo uploaded successfully | Upload Status Code : $uploadStatus"
    }
    catch {
        Write-Log -Message "$email photo failed to upload | Upload Status Code : $uploadStatus"
    }
    $iterationCount++
}

#Clean Up
Remove-Item -Recurse -Force $tempPhotoPath
Write-Log -Message "Finished processing photos"
