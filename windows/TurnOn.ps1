# Turn on the Windows hotspot and the web page. Run as administrator.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms

function Await-Action($Action) {
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq "IAsyncAction"
    } | Select-Object -First 1
    $task = $method.Invoke($null, @($Action))
    $task.Wait()
}

function Await-Operation($Operation) {
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq "IAsyncOperation``1"
    } | Select-Object -First 1
    $generic = $method.MakeGenericMethod($Operation.GetType().GenericTypeArguments)
    $task = $generic.Invoke($null, @($Operation))
    $task.Wait()
    return $task.Result
}

$config = Join-Path $env:USERPROFILE ".config\moonlight-web"
$settings = Get-Content (Join-Path $config "host-settings.json") -Raw | ConvertFrom-Json
$log = Join-Path $config "logs"
New-Item -ItemType Directory -Force -Path $log | Out-Null

$hotspotOk = $false
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
    $null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
    $profile = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
    if (-not $profile) { throw "This computer is not online yet." }
    $manager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)
    $access = $manager.GetCurrentAccessPointConfiguration()
    $access.Ssid = [string]$settings.internet_name
    $access.Passphrase = [string]$settings.internet_password
    Await-Action $manager.ConfigureAccessPointAsync($access)
    $result = Await-Operation $manager.StartTetheringAsync()
    if ("$result" -match "Success|Already") { $hotspotOk = $true }
} catch {
    $hotspotOk = $false
}

if (-not $hotspotOk) {
    Start-Process "ms-settings:network-mobilehotspot"
    [System.Windows.Forms.MessageBox]::Show(
        "Windows could not turn the hotspot on by itself.`n`nIn the Settings window, set the name to $($settings.internet_name) and the password to $($settings.internet_password), then turn Mobile hotspot on.`n`nPlug the phone in and turn on its Personal Hotspot first if this computer is not online.",
        "Turn On"
    ) | Out-Null
}

$port = [int]$settings.port
netsh advfirewall firewall delete rule name="host-internet website" | Out-Null
netsh advfirewall firewall add rule name="host-internet website" dir=in action=allow protocol=TCP localport=$port | Out-Null

Get-Process web-server -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$argLine = "--config-path `"$(Join-Path $config "server\config.json")`" --bind-address 0.0.0.0:$port --log-file `"$(Join-Path $log "web-server.log")`""
if ($settings.path) { $argLine += " --path-prefix `"$($settings.path)`"" }
Start-Process -FilePath (Join-Path $config "web-server.exe") -WorkingDirectory $config -WindowStyle Hidden -ArgumentList $argLine

$sunshine = @(
    "$env:ProgramFiles\Sunshine\sunshine.exe",
    "${env:ProgramFiles(x86)}\Sunshine\sunshine.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($sunshine) { Start-Process $sunshine }

[System.Windows.Forms.MessageBox]::Show(
    "On the other computer, join Wi-Fi $($settings.internet_name)`npassword $($settings.internet_password)`nthen open $($settings.url)`n`nWebsite login`nusername $($settings.username)`npassword $($settings.password)`n`nThat computer can be a Windows laptop or an Apple laptop.`nIf the browser says there is no internet, type the address anyway.",
    "Turn On"
) | Out-Null
