# Turn the Windows hotspot and the web page off.
$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Windows.Forms

try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
    $null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
    $profile = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
    if ($profile) {
        $manager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)
        $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq "IAsyncAction"
        } | Select-Object -First 1
        $task = $method.Invoke($null, @($manager.StopTetheringAsync()))
        $task.Wait()
    }
} catch {}

Get-Process web-server -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process sunshine -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
netsh advfirewall firewall delete rule name="host-internet website" | Out-Null

[System.Windows.Forms.MessageBox]::Show("Internet and streaming are off.", "Turn Off") | Out-Null
