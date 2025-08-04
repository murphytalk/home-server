<#
.SYNOPSIS
    Automates the download of a WireGuard peer configuration from an AWS EC2 instance,
    checks for existing tunnels, uninstalls if present, and installs the new one
    as a Windows WireGuard tunnel service.

.DESCRIPTION
    This script performs the following steps:
    1. Ensures the specified AWS EC2 instance is in a 'running' state. If 'stopped', it attempts to start it.
    2. Retrieves the public IP address of the specified AWS EC2 VM instance using the AWS CLI.
    3. Downloads a WireGuard peer configuration file from a known path on the EC2 VM
       to a local directory using SCP.
    4. Checks if a WireGuard tunnel service with the same name already exists.
    5. If it exists, uninstalls the existing tunnel service.
    6. Installs the downloaded WireGuard configuration as a Windows tunnel service
       using the WireGuard client's command-line interface.

.NOTES
    - Requires AWS CLI and OpenSSH Client to be installed and in your system's PATH.
    - WireGuard for Windows must be installed in its default location ("C:\Program Files\WireGuard\").
    - The script must be run with Administrator privileges to install or uninstall the WireGuard tunnel service.
    - AWS credentials used by AWS CLI must have 'ec2:StartInstances' permission for the specified instance.
#>
param (
    #[string]$InstanceId = 'i-0294a506d8609ea8e',
    [string]$InstanceId = 'i-0fa824dcf80342032',

    [string]$SSHKeyPath = "D:/Syncthing/mobile/vpn/stargate-aws-hk.pem",
    
    [string]$LocalCfgPath = "D:/Syncthing/mobile/vpn",

    [string]$EC2User = 'ubuntu',

    [string]$RemoteConfigPath = '~/wireguard/config/peer_desktop/peer_desktop.conf',

    [string]$Profile = 'my-stargate-profile',

    [switch]$startVmOnly,

    [switch]$shutdown,

    [switch]$UseWSL

)

# --- Configuration ---
$WireGuardExePath = "C:\Program Files\WireGuard\wireguard.exe"
$ConfigFileName = Split-Path -Leaf $RemoteConfigPath
$LocalConfigFilePath = Join-Path $LocalCfgPath $ConfigFileName
$TunnelName = $ConfigFileName.Replace(".conf", "") # Use config file name as tunnel name

# --- Helper Functions ---

function Test-IsAdministrator {
    # Checks if the current PowerShell session is running with Administrator privileges.
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdministrator = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    return $isAdministrator
}

function Get-EC2InstanceState {
    param (
        [string]$InstanceId
    )
    Write-Host "Attempting to get EC2 instance state for instance ID: $InstanceId..."
    return aws ec2 describe-instances --profile $Profile `
                --instance-ids $InstanceId `
                --query "Reservations[0].Instances[0].State.Name" `
                --output text `
                --no-cli-pager 
}

function Wait-EC2InstanceRunning {
    param (
        [string]$InstanceId,
        [int]$MaxRetries = 15,  # Max attempts to check instance state (increased for start up)
        [int]$RetryIntervalSec = 10 # Seconds to wait between retries
    )
    Write-Host "Checking EC2 instance '$InstanceId' state..."

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $instanceState =  Get-EC2InstanceState -InstanceId $InstanceId
            if ($instanceState -eq "running") {
                Write-Host "EC2 instance '$InstanceId' is running." -ForegroundColor Green
                return $true
            } elseif ($instanceState -eq "stopped") {
                Write-Host "EC2 instance '$InstanceId' is stopped. Attempting to start it... (Attempt $i/$MaxRetries)" -ForegroundColor Yellow
                try {
                    aws ec2 start-instances --instance-ids $InstanceId  --profile $Profile| Out-Null
                    Write-Host "Start command sent for '$InstanceId'. Waiting for 'pending' state..." -ForegroundColor Yellow
                    # Give AWS some time to register the start command before re-checking
                    Start-Sleep -Seconds 5
                } catch {
                    Write-Error "Failed to send start command for instance '$InstanceId'. Error: $($_.Exception.Message)"
                    Write-Error "Please ensure your AWS credentials have 'ec2:StartInstances' permission."
                    return $false # Cannot proceed if we can't start it
                }
            } elseif ($instanceState -eq "pending") {
                Write-Host "EC2 instance '$InstanceId' is pending. Retrying in $RetryIntervalSec seconds... (Attempt $i/$MaxRetries)" -ForegroundColor Yellow
            } else {
                Write-Warning "EC2 instance '$InstanceId' is in state '$instanceState'. Waiting for 'running' state. (Attempt $i/$MaxRetries)"
            }
        } catch {
            Write-Error "Failed to get EC2 instance state or an AWS CLI error occurred. Error: $($_.Exception.Message)"
            # If the instance ID doesn't exist, this will also be caught here
            if ($_.Exception.Message -match "InvalidInstanceID.NotFound") {
                Write-Error "Error: The instance ID '$InstanceId' was not found."
                return $false
            }
        }

        if ($i -lt $MaxRetries) {
            Start-Sleep -Seconds $RetryIntervalSec
        }
    }

    Write-Error "EC2 instance '$InstanceId' did not reach 'running' state after $MaxRetries attempts. Current state: $($instanceState -replace '\s+', 'No State Found' -or 'Unknown')"
    return $false
}


function Get-EC2PublicIp {
    param (
        [string]$InstanceId
    )
    Write-Host "Attempting to retrieve public IP for EC2 instance ID: $InstanceId..."

    try {
        $publicIp = aws ec2 describe-instances --profile $Profile `
            --instance-ids $InstanceId `
            --query "Reservations[0].Instances[0].PublicIpAddress" `
            --output text `
            --no-cli-pager

        if ($publicIp -and $publicIp -notmatch "None") {
            Write-Host "Successfully retrieved public IP: $publicIp" -ForegroundColor Green
            return $publicIp
        } else {
            Write-Warning "Could not find a public IP address for instance ID: $InstanceId. Check instance state or if it has a public IP (it might be in 'running' but still initializing or without a public IP)."
            return $null
        }
    } catch {
        Write-Error "Failed to retrieve EC2 public IP using AWS CLI. Error: $($_.Exception.Message)"
        return $null
    }
}

function Download-WireGuardConfigFromWSL {
    param (
        [string]$LocalConfigFilePath
    )
    Write-Host "Attempting to download WireGuard config using WSL..."

    # Ensure the local directory exists
    $LocalConfigDir = Split-Path -Parent $LocalConfigFilePath
    if (-not (Test-Path $LocalConfigDir)) {
        Write-Host "Creating local directory: $LocalConfigDir"
        New-Item -ItemType Directory -Path $LocalConfigDir | Out-Null
    }

    # Convert the Windows path to a WSL path
    $path = $LocalConfigFilePath.Replace('\', '/')
    $wslConfigPath = wsl wslpath -u "$path"
    Write-Host "WSL config path: $wslConfigPath"
    
    # Resolve wireguard.sh path and convert it for WSL
    $wireguardShPath = Join-Path $PSScriptRoot "wireguard.sh"
    # Replace backslashes with forward slashes for wslpath compatibility
    $wireguardShPathForWsl = $wireguardShPath.Replace('\', '/')
    $wslWireguardShPath = wsl wslpath -u $wireguardShPathForWsl

    try {
        $wslCommand = "wsl"
        # Execute the bash script with arguments passed directly
        $wslArguments = @(
            "-e",
            "bash",
            $wslWireguardShPath,
            "--get-config",
            $InstanceId,
            $wslConfigPath
        )

        $process = Start-Process -FilePath $wslCommand -ArgumentList $wslArguments -Wait -NoNewWindow -PassThru -ErrorAction Stop

        if ($process.ExitCode -eq 0) {
            Write-Host "WireGuard config downloaded successfully to: $LocalConfigFilePath" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "WSL script failed with exit code $($process.ExitCode). Check the WSL script logs for details."
            return $false
        }
    } catch {
        Write-Error "Failed to execute WSL script. Error: $($_.Exception.Message)"
        return $false
    }
}

function Download-WireGuardConfig {
    param (
        [string]$PublicIp,
        [string]$SSHKeyPath,
        [string]$EC2User,
        [string]$RemoteConfigPath,
        [string]$LocalConfigFilePath
    )
    Write-Host "Attempting to download WireGuard config from $EC2User@${PublicIp}:${RemoteConfigPath} to $LocalConfigFilePath..."

    # Ensure the local directory exists
    $LocalConfigDir = Split-Path -Parent $LocalConfigFilePath
    if (-not (Test-Path $LocalConfigDir)) {
        Write-Host "Creating local directory: $LocalConfigDir"
        New-Item -ItemType Directory -Path $LocalConfigDir | Out-Null
    }

    try {
        $scpCommand = "scp"
        $scpArguments = @(
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=NUL",
            "-i", "$SSHKeyPath",
            "$EC2User@$PublicIp`:$RemoteConfigPath",
            "$LocalConfigFilePath"
        )

        $process = Start-Process -FilePath $scpCommand -ArgumentList $scpArguments -Wait -NoNewWindow -PassThru -ErrorAction Stop

        if ($process.ExitCode -eq 0) {
            Write-Host "WireGuard config downloaded successfully to: $LocalConfigFilePath" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "SCP command failed with exit code $($process.ExitCode). Check SSH key, remote path, or network connectivity."
            return $false
        }
    } catch {
        Write-Error "Failed to download WireGuard config via SCP. Error: $($_.Exception.Message)"
        return $false
    }
}

function Uninstall-WireGuardTunnelService {
    param (
        [string]$WireGuardExePath,
        [string]$TunnelName
    )
    $serviceName = "WireGuardTunnel`$$TunnelName"
    Write-Host "Checking if WireGuard tunnel service $serviceName exists..."
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    if ($service) {
        Write-Host "WireGuard tunnel service '$TunnelName' found. Uninstalling..."
        try {
            $uninstallCommand = "$WireGuardExePath"
            $uninstallArguments = @(
                "/uninstalltunnelservice",
                $TunnelName
            )

            Write-Host "Running: $($uninstallCommand) $($uninstallArguments -join ' ')"
            $process = Start-Process -FilePath $uninstallCommand -ArgumentList $uninstallArguments -Wait -NoNewWindow -PassThru -ErrorAction Stop

            if ($process.ExitCode -eq 0) {
                Write-Host "WireGuard tunnel service '$TunnelName' uninstalled successfully." -ForegroundColor Green
                return $true
            } else {
                Write-Warning "Failed to uninstall WireGuard tunnel service. Exit code: $($process.ExitCode). This usually requires Administrator privileges."
                return $false
            }
        } catch {
            Write-Error "An error occurred during WireGuard service uninstallation. Error: $($_.Exception.Message)"
            return $false
        }
    } else {
        Write-Host "WireGuard tunnel service '$TunnelName' not found. No need to uninstall." -ForegroundColor Yellow
        return $true # Return true because the desired state (no service) is already achieved
    }
}


function Install-WireGuardTunnelService {
    param (
        [string]$WireGuardExePath,
        [string]$LocalConfigFilePath,
        [string]$TunnelName
    )
    Write-Host "Attempting to install WireGuard tunnel service '$TunnelName' from: $LocalConfigFilePath..."

    if (-not (Test-Path $WireGuardExePath)) {
        Write-Error "WireGuard executable not found at '$WireGuardExePath'. Please ensure WireGuard is installed correctly."
        return $false
    }

    if (-not (Test-Path $LocalConfigFilePath)) {
        Write-Error "WireGuard config file not found at '$LocalConfigFilePath'. Cannot install service."
        return $false
    }

    try {
        # The /installtunnelservice command needs to be run from an elevated prompt.
        # This script should already be running as admin.
        $installCommand = "$WireGuardExePath"
        $installArguments = @(
            "/installtunnelservice",
            "`"$LocalConfigFilePath`""
        )

        Write-Host "Running: $($installCommand) $($installArguments -join ' ')"
        $process = Start-Process -FilePath $installCommand -ArgumentList $installArguments -Wait -NoNewWindow -PassThru -ErrorAction Stop

        if ($process.ExitCode -eq 0) {
            Write-Host "WireGuard tunnel service '$TunnelName' installed successfully!" -ForegroundColor Green
            Write-Host "You can now activate the tunnel via the WireGuard GUI or using PowerShell:"
            Write-Host "  Start-Service -Name 'WireGuardTunnel$$($TunnelName)'" -ForegroundColor Cyan
            return $true
        } else {
            Write-Warning "Failed to install WireGuard tunnel service. Exit code: $($process.ExitCode). This usually requires Administrator privileges."
            return $false
        }
    } catch {
        Write-Error "An error occurred during WireGuard service installation. Error: $($_.Exception.Message)"
        return $false
    }
}

# --- Main Script Execution ---

Write-Host "Starting WireGuard Tunnel Automation Script..." -ForegroundColor Yellow

# 1. Check for Administrator privileges
if (-not (Test-IsAdministrator)) {
    Write-Error "This script must be run with Administrator privileges to install the WireGuard tunnel service."
    Write-Error "Please right-click PowerShell and select 'Run as Administrator'."
    exit 1
}

# Check if the tunnel is already running. If so, treat it as a shutdown command.
$serviceNameForCheck = "WireGuardTunnel`$TunnelName"
$service = Get-Service -Name $serviceNameForCheck -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq 'Running') {
    Write-Host "WireGuard tunnel '$TunnelName' is already running. Shutting it down now." -ForegroundColor Yellow
    # Setting the shutdown flag to true to trigger the shutdown logic below
    $shutdown = $true
}
else {
    if ($UseWSL) {
        Write-Host "Asking WSL to see if EC2 instance '$InstanceId' is already running." -ForegroundColor Yellow
    }
    else {
        $instanceState =  Get-EC2InstanceState -InstanceId $InstanceId
        if ($instanceState -eq "running") {
            Write-Host "EC2 instance '$InstanceId' is already running. Shutting it down now." -ForegroundColor Yellow
            $shutdown = $true
        }
    }
}

if ($shutdown) {
    if ($UseWSL) {
        Write-Host "Asking WSL to see if EC2 instance '$InstanceId' is already running." -ForegroundColor Yellow
    }
    else {
        $uninstallSuccess = Uninstall-WireGuardTunnelService -WireGuardExePath $WireGuardExePath -TunnelName $TunnelName
        Write-Host "Shutting down EC2 instance '$InstanceId'..."
        try {
            aws ec2 stop-instances --instance-ids $InstanceId --profile $Profile | Out-Null
            Write-Host "EC2 instance '$InstanceId' shutdown successfully." -ForegroundColor Green
        } catch {
            Write-Error "Failed to shutdown EC2 instance '$InstanceId'. Error: $($_.Exception.Message)"
            exit 1
        }
    }
    exit 0
}

if ($UseWSL) {
    $downloadSuccess = Download-WireGuardConfigFromWSL -LocalConfigFilePath $LocalConfigFilePath
} else {
    # 2. Wait for EC2 instance to be running (and start if stopped)
    $instanceReady = Wait-EC2InstanceRunning -InstanceId $InstanceId
    if (-not $instanceReady) {
        Write-Error "EC2 instance '$InstanceId' is not running or could not be started. Cannot proceed."
        exit 1
    }

    # 3. Get Public IP
    $ec2PublicIp = Get-EC2PublicIp -InstanceId $InstanceId
    if (-not $ec2PublicIp) {
        Write-Error "Failed to get EC2 public IP. Exiting."
        exit 1
    }

    if ($startVmOnly) {
        Write-Host "EC2 instance '$InstanceId' is running. Exiting."
        exit 0
    }

    # 4. Download WireGuard Config
    $downloadSuccess = Download-WireGuardConfig `
        -PublicIp $ec2PublicIp `
        -SSHKeyPath $SSHKeyPath `
        -EC2User $EC2User `
        -RemoteConfigPath $RemoteConfigPath `
        -LocalConfigFilePath $LocalConfigFilePath
}

if (-not $downloadSuccess) {
    Write-Error "Failed to download WireGuard configuration. Exiting."
    exit 1
}

# 5. Uninstall existing tunnel (if it exists)
$uninstallSuccess = Uninstall-WireGuardTunnelService -WireGuardExePath $WireGuardExePath -TunnelName $TunnelName
if (-not $uninstallSuccess) {
    Write-Error "Failed to uninstall existing WireGuard tunnel service. Exiting."
    exit 1
}

# 6. Install WireGuard Tunnel Service
$installSuccess = Install-WireGuardTunnelService `
    -WireGuardExePath $WireGuardExePath `
    -LocalConfigFilePath $LocalConfigFilePath `
    -TunnelName $TunnelName

if (-not $installSuccess) {
    Write-Error "Failed to install WireGuard tunnel service. Please check the logs above."
    exit 1
}


Write-Host "`nScript finished successfully!" -ForegroundColor Yellow
