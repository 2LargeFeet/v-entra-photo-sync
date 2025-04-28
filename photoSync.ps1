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

# === FUNCTIONS ===

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

# === STEP 1: Authenticate ===

# Authenticate to Entra ID (Microsoft Graph)
Write-Host "Authenticating to Microsoft Graph..."
$graphTokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$graphTokenResponse = Invoke-RestMethod -Method Post -Uri $graphTokenUrl -Body @{
    client_id     = $clientId
    scope         = $graphScope
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}
$graphToken = $graphTokenResponse.access_token

# Authenticate to Verkada
Write-Host "Authenticating to Verkada API..."
$verkadaApiToken = Get-VerkadaApiToken -ApiKey $verkadaApiKey
$verkadaHeaders = Get-VerkadaHeaders

# === STEP 2: Get Verkada Users ===

Write-Host "Retrieving users from Verkada..."
$verkadaUsersUrl = "$verkadaBaseUrl/access/v1/access_users"
$verkadaUsersResponse = Invoke-RestMethod -Uri $verkadaUsersUrl -Method GET -Headers $verkadaHeaders
$verkadaUsers = $verkadaUsersResponse.access_members

if (-not $verkadaUsers) {
    Write-Error "No users retrieved from Verkada!"
    exit
}

# === STEP 3: Process Users ===

foreach ($user in $verkadaUsers) {
    if (-not $user.email) {
        Write-Warning "User $($user.full_name) has no email. Skipping."
        continue
    }
    Write-Output "processing $user"

    $email = $user.email
    Write-Host "Processing $email..."

    # Look up Entra ID user by email
    $entraUserUrl = "https://graph.microsoft.com/v1.0/users/$email"
    try {
        $entraUser = Invoke-RestMethod -Uri $entraUserUrl -Headers @{
            Authorization = "Bearer $graphToken"
        }
    }
    catch {
        Write-Warning "Could not find Entra ID user for $email"
        continue
    }

    # Download user photo
    $photoUrl = "https://graph.microsoft.com/v1.0/users/$($entraUser.id)/photo/`$value"
    $photoPath = Join-Path $tempPhotoPath "$email.jpg"

    try {
        Invoke-RestMethod -Uri $photoUrl -Headers @{ Authorization = "Bearer $graphToken" } -OutFile $photoPath
        Write-Host "Downloaded photo for $email"
    }
    catch {
        Write-Warning "No photo for $email"
        continue
    }

    # Upload photo to Verkada
    $uploadUrl = "$verkadaBaseUrl/access/v1/access_users/user/profile_photo?user_id=$($user.user_id)&overwrite=true"
    $formFields = @{
        file = Get-Item $photoPath
    }

    try {
        Invoke-RestMethod -Method Put -Uri $uploadUrl -Headers $verkadaHeaders -Form $formFields -ContentType "multipart/form-data"
        Write-Host "Uploaded photo for $email to Verkada"
    }
    catch {
        Write-Warning "Failed to upload photo for $email to Verkada"
    }
}

# === STEP 4: Cleanup ===

Remove-Item -Recurse -Force $tempPhotoPath
Write-Host "Done. All photos processed."