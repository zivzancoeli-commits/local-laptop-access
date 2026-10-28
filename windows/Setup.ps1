# First-time setup for a Windows laptop. Asks for the Wi-Fi name, both
# passwords, and the address, then installs Turn On and Turn Off.
$ErrorActionPreference = "Stop"
$HostAddress = "192.168.137.1"

function Test-Admin {
    $current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms

function Ask-Text([string]$Prompt, [string]$Default) {
    $value = [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, "Setup", $Default)
    if ([string]::IsNullOrEmpty($value) -and [string]::IsNullOrEmpty($Default)) {
        throw "Setup was cancelled."
    }
    return $value
}

function Ask-Until([string]$Prompt, [string]$Default, [scriptblock]$Check) {
    $current = $Default
    while ($true) {
        $value = Ask-Text $Prompt $current
        if ([string]::IsNullOrEmpty($value)) { throw "Setup was cancelled." }
        $errorText = & $Check $value
        if ([string]::IsNullOrEmpty($errorText)) { return $value }
        [System.Windows.Forms.MessageBox]::Show($errorText, "Setup") | Out-Null
        $current = $value
    }
}

# Same limits as host-settings.py on the Apple installer.
function Test-Name([string]$Value) {
    if ($Value -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9 -]{0,30}[A-Za-z0-9])?$') {
        return "The Wi-Fi name needs 1 to 32 letters, numbers, spaces, or hyphens, and it cannot start or end with a space or a hyphen."
    }
    return ""
}
function Test-Wifi([string]$Value) {
    if ($Value -notmatch '^[!-~]{8,63}$') {
        return "The Wi-Fi password needs 8 to 63 letters, numbers, or symbols, with no spaces."
    }
    return ""
}
function Test-User([string]$Value) {
    if ($Value -notmatch '^[A-Za-z0-9]{1,32}$') {
        return "The website username needs 1 to 32 letters and numbers."
    }
    return ""
}
function Test-Web([string]$Value) {
    if ($Value -notmatch '^[!-~]{4,64}$') {
        return "The website password needs 4 to 64 letters, numbers, or symbols, with no spaces."
    }
    return ""
}
function Test-Url([string]$Value) {
    if ($Value -notmatch "^http://$([regex]::Escape($HostAddress)):(808[0-9]|809[0-9])(/[A-Za-z0-9-]{1,20})?$") {
        return "Use http://$HostAddress and a port from 8080 to 8099. You can add one short path, such as /play. Example: http://${HostAddress}:8080"
    }
    return ""
}

$here = Split-Path -Parent $PSCommandPath
$zip = Join-Path $here "moonlight-web-windows.zip"
if (-not (Test-Path $zip)) {
    [System.Windows.Forms.MessageBox]::Show("The Windows web program is missing from this folder.", "Setup") | Out-Null
    exit 1
}

$config = Join-Path $env:USERPROFILE ".config\moonlight-web"
$settingsPath = Join-Path $config "host-settings.json"
$settings = $null
New-Item -ItemType Directory -Force -Path $config | Out-Null

if (Test-Path $settingsPath) {
    $old = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $keep = [System.Windows.Forms.MessageBox]::Show(
        "This computer is already set up.`n`nWi-Fi: $($old.internet_name)`nAddress: $($old.url)`nWebsite username: $($old.username)`n`nKeep these?",
        "Setup",
        [System.Windows.Forms.MessageBoxButtons]::YesNo
    )
    if ($keep -eq [System.Windows.Forms.DialogResult]::Yes) {
        $settings = $old
    }
}

if (-not $settings) {
    $name = Ask-Until "Name the Wi-Fi the other computer will join.`n`nUse 1 to 32 letters, numbers, spaces, or hyphens." "host-internet" ${function:Test-Name}
    $wifi = Ask-Until "Choose the Wi-Fi password.`n`nUse 8 to 63 letters, numbers, or symbols. No spaces." "" ${function:Test-Wifi}
    $again = Ask-Text "Type the Wi-Fi password again." ""
    if ($again -ne $wifi) {
        [System.Windows.Forms.MessageBox]::Show("The Wi-Fi passwords did not match. Run Setup again.", "Setup") | Out-Null
        exit 1
    }
    $user = Ask-Until "Choose the website username.`n`nUse 1 to 32 letters and numbers." "user" ${function:Test-User}
    $web = Ask-Until "Choose the website password.`n`nUse 4 to 64 letters, numbers, or symbols. No spaces." "" ${function:Test-Web}
    $again = Ask-Text "Type the website password again." ""
    if ($again -ne $web) {
        [System.Windows.Forms.MessageBox]::Show("The website passwords did not match. Run Setup again.", "Setup") | Out-Null
        exit 1
    }
    $url = Ask-Until "Choose the address the other computer will open.`n`nIt has to start with http://$HostAddress`nThe port has to be 8080 to 8099.`nYou can add a short path such as /play.`nhttps will not work." "http://${HostAddress}:8080" ${function:Test-Url}
    if ($url -match "^http://$([regex]::Escape($HostAddress)):(\d+)(/[A-Za-z0-9-]{1,20})?$") {
        $port = [int]$Matches[1]
        $path = if ($Matches[2]) { $Matches[2] } else { "" }
    } else {
        throw "That address will not work."
    }
    $settings = [ordered]@{
        internet_name = $name
        internet_password = $wifi
        username = $user
        password = $web
        url = $url
        port = $port
        path = $path
        host = $HostAddress
    }
    ($settings | ConvertTo-Json) | Set-Content -Path $settingsPath -Encoding UTF8
}

$expand = Join-Path $env:TEMP "host-internet-web"
if (Test-Path $expand) { Remove-Item -Recurse -Force $expand }
Expand-Archive -Path $zip -DestinationPath $expand
Copy-Item (Join-Path $expand "package\web-server.exe") (Join-Path $config "web-server.exe") -Force
if (Test-Path (Join-Path $config "static")) { Remove-Item -Recurse -Force (Join-Path $config "static") }
Copy-Item (Join-Path $expand "package\static") (Join-Path $config "static") -Recurse -Force
Copy-Item (Join-Path $here "TurnOn.ps1") (Join-Path $config "TurnOn.ps1") -Force
Copy-Item (Join-Path $here "TurnOff.ps1") (Join-Path $config "TurnOff.ps1") -Force

$serverDir = Join-Path $config "server"
New-Item -ItemType Directory -Force -Path $serverDir | Out-Null
$prefix = if ($settings.path) { $settings.path } else { "" }
@"
{
  "data_storage": {"type": "json", "path": "server/data.json"},
  "web_server": {
    "bind_address": "0.0.0.0:$($settings.port)",
    "certificate": null,
    "url_path_prefix": "$prefix",
    "session_cookie_secure": false,
    "first_login_create_admin": true,
    "first_login_assign_global_hosts": true
  },
  "moonlight": {"default_http_port": 47989, "pair_device_name": "host"},
  "log": {"level_filter": "INFO", "file_path": "$($config.Replace('\','\\'))\\logs\\web-server.log"}
}
"@ | Set-Content -Path (Join-Path $serverDir "config.json") -Encoding UTF8

$salt = New-Object byte[] 16
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
$derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($settings.password, $salt, 600000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
$hash = $derive.GetBytes(32)
$saltHex = ([BitConverter]::ToString($salt) -replace "-", "").ToLower()
$hashHex = ([BitConverter]::ToString($hash) -replace "-", "").ToLower()
$dataPath = Join-Path $serverDir "data.json"
if (Test-Path $dataPath) {
    $data = Get-Content $dataPath -Raw | ConvertFrom-Json
} else {
    $data = [pscustomobject]@{ version = "3"; users = [pscustomobject]@{}; hosts = [pscustomobject]@{}; roles = [pscustomobject]@{} }
}
$userObject = [pscustomobject]@{
    role_id = 1000000002
    name = [string]$settings.username
    password = [pscustomobject]@{ salt = $saltHex; hash = $hashHex; iterations = 600000 }
    client_unique_id = [string]$settings.username
}
if (-not $data.users) { $data | Add-Member -NotePropertyName users -NotePropertyValue ([pscustomobject]@{}) }
$data.users | Add-Member -NotePropertyName "1000000001" -NotePropertyValue $userObject -Force
if ($data.roles.PSObject.Properties.Name -notcontains "1000000002") {
    $role = [pscustomobject]@{
        name = "Admin"; ty = "Admin"; default_settings = [pscustomobject]@{}; permissions = [pscustomobject]@{
            allow_add_hosts = $true; maximum_bitrate_kbps = $null; allow_codec_h264 = $true; allow_codec_h265 = $true
            allow_codec_av1 = $true; allow_hdr = $true; allow_transport_webrtc = $true; allow_transport_websockets = $true
        }
    }
    $data.roles | Add-Member -NotePropertyName "1000000002" -NotePropertyValue $role -Force
}
$data | ConvertTo-Json -Depth 8 | Set-Content -Path $dataPath -Encoding UTF8

$desktop = [Environment]::GetFolderPath("Desktop")
Copy-Item (Join-Path $here "TurnOn.bat") (Join-Path $desktop "Turn On.bat") -Force
Copy-Item (Join-Path $here "TurnOff.bat") (Join-Path $desktop "Turn Off.bat") -Force
@"
On the other computer:

1. Join Wi-Fi $($settings.internet_name)
2. Password $($settings.internet_password)
3. Open $($settings.url)
4. Log in
   username $($settings.username)
   password $($settings.password)

That computer can be a Windows laptop or an Apple laptop.
It does not need anything installed.
If the browser says there is no internet, type the address anyway.
"@ | Set-Content -Path (Join-Path $desktop "How to join.txt") -Encoding UTF8

$sunshine = @(
    "$env:ProgramFiles\Sunshine\sunshine.exe",
    "${env:ProgramFiles(x86)}\Sunshine\sunshine.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $sunshine) {
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "ARM64" } else { "AMD64" }
    $msi = Join-Path $env:TEMP "Sunshine-$arch.msi"
    $url = "https://github.com/LizardByte/Sunshine/releases/download/v2026.914.233613/Sunshine-Windows-$arch-installer.msi"
    [System.Windows.Forms.MessageBox]::Show("Setup will download Sunshine from its official release. This computer needs internet for that.", "Setup") | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $msi
    $install = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
    if ($install.ExitCode -ne 0 -and $install.ExitCode -ne 3010) {
        [System.Windows.Forms.MessageBox]::Show("Sunshine did not install (code $($install.ExitCode)).", "Setup") | Out-Null
        exit 1
    }
}
[System.Windows.Forms.MessageBox]::Show("Setup is done.`n`nPlug the phone in, turn on its Personal Hotspot, then double-click Turn On on the desktop.`n`nHow to join.txt is on the desktop.", "Setup") | Out-Null
