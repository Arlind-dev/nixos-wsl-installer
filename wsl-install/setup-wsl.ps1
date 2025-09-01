#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =========================
# Variable Definitions
# =========================
$NixOSFolder         = "C:\wsl\nixos"
$LogsFolder          = "$NixOSFolder\logs"
$CurrentDateTime     = (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")
$LogFile             = "$LogsFolder\setup_$CurrentDateTime.log"
$TranscriptFile      = "$LogsFolder\setup_$CurrentDateTime.transcript.txt"
$NixOSReleaseTag     = "2505.7.0"
$NixOSPackage        = "$NixOSFolder\nixos.wsl"
$RepoURL             = "https://github.com/Arlind-dev/dotfiles"
$RepoPath            = "$NixOSFolder\dotfiles"
$NixFilesSource      = "/mnt/c/wsl/nixos/dotfiles"
$NixFilesDest        = "/home/nixos/nix-config"
$HomePath            = $env:USERPROFILE
$WSLConfigPath       = "$HomePath\.wslconfig"
$WSLConfigBackupPath = "$HomePath\.wslconfigcopy"
$ScriptPath          = "$NixOSFolder\temp.ps1"

# =========================
# Helper / Utility
# =========================
function Write-OutputLog {
    param([string]$message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] $message"
    Write-Host $line
    try {
        Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
    }
}

function Invoke-Retry {
    param(
        [Parameter(Mandatory)] [scriptblock] $ScriptBlock,
        [int] $MaxAttempts = 3,
        [int] $DelaySeconds = 2
    )
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try { return & $ScriptBlock } catch {
            if ($i -eq $MaxAttempts) { throw }
            Start-Sleep -Seconds ($DelaySeconds * $i)
        }
    }
}

function Test-NetworkConnectivity {
    try {
        Write-OutputLog "Checking network connectivity to github.com..."
        $ok = Test-NetConnection github.com -Port 443 -InformationLevel Quiet
        if (-not $ok) {
            Write-OutputLog "Network check failed (github.com:443). Please ensure you have internet access and retry."
            Read-Host -Prompt "Press Enter to exit"
            Exit 1
        }
        Write-OutputLog "Network connectivity OK."
    } catch {
        Write-OutputLog "Network check encountered an error: $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

# =========================
# Initialization
# =========================
function Initialize-LogsFolder {
    try {
        if (-Not (Test-Path -Path $LogsFolder)) {
            New-Item -Path $LogsFolder -ItemType Directory -Force | Out-Null
        }

        try {
            Start-Transcript -Path $TranscriptFile -Append -ErrorAction Stop | Out-Null
            Write-OutputLog "Transcript started at $TranscriptFile."
        } catch {
            Write-OutputLog "Could not start transcript: $_"
        }

        Write-OutputLog "Logs folder ready at $LogsFolder."
    }
    catch {
        Write-Host "Failed to initialize logging at $LogsFolder."
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Invoke-CheckAdminElevation {
    if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        $message = "Script is not running as administrator. Attempting to restart with elevated privileges..."
        Write-OutputLog $message

        $pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue
        $shellPath = if ($pwshPath) { "pwsh.exe" } else { "powershell.exe" }

        $wtPath = Get-Command wt -ErrorAction SilentlyContinue

        if (-not $PSCommandPath) {
            if (-Not (Test-Path -Path $NixOSFolder)) {
                New-Item -Path $NixOSFolder -ItemType Directory -Force | Out-Null
                Write-OutputLog "Created NixOS folder at $NixOSFolder."
            }

            $scriptUrl = "https://raw.githubusercontent.com/Arlind-dev/dotfiles/main/wsl-install/setup-wsl.ps1"
            $scriptContent = (Invoke-WebRequest -Uri $scriptUrl -UseBasicParsing -ErrorAction Stop).Content
            Set-Content -Path $ScriptPath -Value $scriptContent -Encoding UTF8
            Write-OutputLog "Downloaded and saved script content to $ScriptPath."
        }

        if ($wtPath) {
            Write-OutputLog "Windows Terminal found. Restarting in Windows Terminal with $shellPath..."
            Start-Process -FilePath "wt.exe" -ArgumentList "new-tab $shellPath -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -Verb RunAs
        }
        else {
            Write-OutputLog "Windows Terminal not found. Restarting with $shellPath..."
            Start-Process -FilePath $shellPath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -Verb RunAs
        }
        Exit
    }
}

# =========================
# Preflight / Validation
# =========================
function Test-VirtualizationPrereqs {
    try {
        Write-OutputLog "Validating CPU & firmware virtualization prerequisites..."

        $cpu = Get-WmiObject Win32_Processor | Select-Object Name, VirtualizationFirmwareEnabled

        if (-not $cpu.VirtualizationFirmwareEnabled) {
            Write-OutputLog "Virtualization prerequisite check FAILED: Virtualization is not enabled in firmware (BIOS/UEFI)."
            Write-OutputLog "Please enable Intel VT-x / AMD-V in BIOS/UEFI settings."
            Read-Host -Prompt "Press Enter to exit"
            Exit 1
        }

        Write-OutputLog "Virtualization prerequisites OK. CPU: $($cpu.Name)"
    }
    catch {
        Write-OutputLog "Failed to validate virtualization prerequisites: $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

# =========================
# Windows Features
# =========================
function Enable-WSLFeature {
    try {
        Write-OutputLog "Enabling Windows Subsystem for Linux feature (if not already enabled)..."
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
        Write-OutputLog "WSL feature ensured."
    }
    catch {
        Write-OutputLog "Failed to enable WSL feature. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Set-WSLDefaultVersion2 {
    try {
        Write-OutputLog "Setting WSL default version to 2..."
        wsl.exe --set-default-version 2
        Write-OutputLog "WSL default version set to 2."
    }
    catch {
        Write-OutputLog "Failed to set WSL default version to 2. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Enable-HyperVFeature {
    try {
        Write-OutputLog "Ensuring Microsoft-Hyper-V optional feature is enabled..."
        $featureState = (dism.exe /online /get-featureinfo /featurename:Microsoft-Hyper-V | Select-String "State : (\w+)").Matches.Groups[1].Value
        if ($featureState -ne "Enabled") {
            Write-OutputLog "Hyper-V not enabled. Enabling now..."
            Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart | Out-Null
            Write-OutputLog "Microsoft-Hyper-V feature enabled (restart may be required)."
        } else {
            Write-OutputLog "Microsoft-Hyper-V already enabled."
        }
    }
    catch {
        Write-OutputLog "Failed to enable Microsoft-Hyper-V feature. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Update-WSLConfig {
    param ([string]$configPath)

    $newConfigLine = "kernelCommandLine = cgroup_no_v1=all"
    $wsl2Section = "[wsl2]"

    try {
        if (Test-Path -Path $configPath) {
            $currentConfig = Get-Content -Path $configPath -ErrorAction Stop

            $hasWSL2Section = $currentConfig -contains $wsl2Section
            $hasKernelCommandLine = $currentConfig -contains $newConfigLine

            if (-not $hasKernelCommandLine) {
                Copy-Item -Path $configPath -Destination $WSLConfigBackupPath -Force
                Write-OutputLog "Backed up existing .wslconfig to $WSLConfigBackupPath."

                if (-not $hasWSL2Section) {
                    Add-Content -Path $configPath -Value "`r`n$wsl2Section`r`n$newConfigLine"
                    Write-OutputLog "Added [wsl2] section and updated .wslconfig at $configPath."
                }
                else {
                    $wsl2Index = [Array]::IndexOf($currentConfig, $wsl2Section)
                    $contentBefore = $currentConfig[0..$wsl2Index]
                    $contentAfter  = @()
                    if ($wsl2Index + 1 -lt $currentConfig.Length) {
                        $contentAfter = $currentConfig[($wsl2Index + 1)..($currentConfig.Length - 1)]
                    }
                    $newConfig = $contentBefore + $newConfigLine + $contentAfter
                    Set-Content -Path $configPath -Value $newConfig -Encoding UTF8
                    Write-OutputLog "Updated .wslconfig at $configPath."
                }
            }
            else {
                Write-OutputLog "No changes needed in .wslconfig."
            }
        }
        else {
            Set-Content -Path $configPath -Value "[wsl2]`r`n$newConfigLine" -Encoding UTF8
            Write-OutputLog "Created new .wslconfig at $configPath."
        }
    }
    catch {
        Write-OutputLog "Failed to update .wslconfig. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

# =========================
# WSL / NixOS Steps
# =========================
function Install-WSL {
    try {
        Write-OutputLog "Installing WSL (no distribution)..."
        wsl.exe --install --no-distribution
        Write-OutputLog "WSL installation ensured."
    }
    catch {
        Write-OutputLog "Failed to install WSL. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Unregister-NixOS {
    try {
        Write-OutputLog "Unregistering existing NixOS (if present)..."
        wsl.exe --unregister NixOS
        Write-OutputLog "NixOS unregistered."
    }
    catch {
        Write-OutputLog "Failed to unregister NixOS. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Invoke-DownloadNixOSPackage {
    try {
        $url = "https://github.com/nix-community/NixOS-WSL/releases/download/$NixOSReleaseTag/nixos.wsl"
        Write-OutputLog "Downloading NixOS package (.wsl) from $url ..."
        Invoke-Retry -ScriptBlock {
            Invoke-WebRequest -Uri $url -OutFile $NixOSPackage -UseBasicParsing -ErrorAction Stop
        } | Out-Null
        Write-OutputLog "Downloaded NixOS package to $NixOSPackage."
    }
    catch {
        Write-OutputLog "Failed to download NixOS package. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Invoke-CloneDotfilesRepository {
    try {
        Write-OutputLog "Cloning dotfiles repository..."
        git clone $RepoURL $RepoPath
        Write-OutputLog "Cloned dotfiles repository to $RepoPath."
    }
    catch {
        Write-OutputLog "Failed to clone repository. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Update-DotfilesRepository {
    try {
        Write-OutputLog "Updating dotfiles repository..."
        git -C $RepoPath pull --ff-only
        Write-OutputLog "Updated dotfiles repository."
    }
    catch {
        Write-OutputLog "Failed to update repository. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Import-NixOS {
    try {
        Write-OutputLog "Importing NixOS from .wsl package..."
        wsl.exe --import NixOS "$NixOSFolder" "$NixOSPackage"
        Write-OutputLog "Imported NixOS."
    }
    catch {
        Write-OutputLog "Failed to import NixOS. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Set-DefaultWSL {
    try {
        Write-OutputLog "Setting NixOS as the default WSL distribution..."
        wsl.exe -s NixOS
        Write-OutputLog "Set NixOS as default."
    }
    catch {
        Write-OutputLog "Failed to set NixOS as default. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Copy-NixOSConfigurationFiles {
    try {
        Write-OutputLog "Copying NixOS configuration files to $NixFilesDest..."
        wsl.exe -d NixOS -- bash -c "mkdir -p $NixFilesDest"
        wsl.exe -d NixOS -- bash -c "cp -r $NixFilesSource/* $NixFilesDest"
        Write-OutputLog "Copied NixOS configuration files."
    }
    catch {
        Write-OutputLog "Failed to copy NixOS configuration files. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Invoke-RebuildWithFlake {
    param ([string]$flakePath = "~/nix-config#nixos-wsl")
    try {
        Write-OutputLog "Rebuilding NixOS with flake configuration at $flakePath..."
        wsl.exe -d NixOS -- bash -c "sudo nixos-rebuild switch --flake $flakePath"
        Write-OutputLog "Rebuild with flake at $flakePath completed."
    }
    catch {
        Write-OutputLog "Failed to rebuild NixOS with flake at $flakePath. Error: $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Stop-WSL {
    try {
        Write-OutputLog "Shutting down WSL..."
        wsl.exe --shutdown
        Write-OutputLog "WSL shutdown."
    }
    catch {
        Write-OutputLog "Failed to shut down WSL. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Set-Ownership {
    try {
        Write-OutputLog "Changing ownership of home directory..."
        wsl.exe -d NixOS -- bash -c "sudo chown -R 1000:100 /home/nixos"
        Write-OutputLog "Changed ownership of home directory."
    }
    catch {
        Write-OutputLog "Failed to change ownership of home directory. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Set-UserPassword {
    try {
        Write-OutputLog "Setting password for 'nixos' user..."
        wsl.exe -d NixOS -- bash -c "echo 'nixos:nixos' | sudo chpasswd"
        Write-OutputLog "Password for 'nixos' user set."
    }
    catch {
        Write-OutputLog "Failed to set password for 'nixos' user. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Remove-OldHomeManagerProfiles {
    try {
        Write-OutputLog "Removing old home-manager profiles..."
        wsl.exe -d NixOS -- bash -c "rm -rf /home/nixos/.local/state/nix/profiles/home-manager*"
        Write-OutputLog "Removed old home-manager profiles."
    }
    catch {
        Write-OutputLog "Failed to remove old home-manager profiles. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Remove-OldHomeManagerGcroots {
    try {
        Write-OutputLog "Removing old home-manager gcroots..."
        wsl.exe -d NixOS -- bash -c "rm -rf /home/nixos/.local/state/home-manager/gcroots/current-home"
        Write-OutputLog "Removed old home-manager gcroots."
    }
    catch {
        Write-OutputLog "Failed to remove old home-manager gcroots. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function New-NixFilesDirectory {
    try {
        Write-OutputLog "Creating directory for NixOS configuration files..."
        wsl.exe -d NixOS -- bash -c "mkdir -p $NixFilesDest"
        Write-OutputLog "Created directory $NixFilesDest."
    }
    catch {
        Write-OutputLog "Failed to create directory $NixFilesDest. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Copy-NixFiles {
    try {
        Write-OutputLog "Copying NixOS configuration files..."
        wsl.exe -d NixOS -- bash -c "cp -r $NixFilesSource/* $NixFilesDest"
        Write-OutputLog "Copied NixOS configuration files."
    }
    catch {
        Write-OutputLog "Failed to copy NixOS configuration files. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Remove-OldDotfilesRepo {
    try {
        Write-OutputLog "Removing old dotfiles repository in ~/nix-config#nixos-wsl ..."
        wsl.exe -d NixOS -- bash -c "rm -rf ~/nix-config"
        Write-OutputLog "Removed old dotfiles repository."
    }
    catch {
        Write-OutputLog "Failed to remove old dotfiles repository. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

function Invoke-CloneNewDotfilesRepo {
    try {
        Write-OutputLog "Cloning new dotfiles repository into ~/nix-config/ ..."
        wsl.exe -d NixOS -- bash -c "git clone $RepoURL ~/nix-config/"
        Write-OutputLog "Cloned new dotfiles repository."
    }
    catch {
        Write-OutputLog "Failed to clone new dotfiles repository. $_"
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }
}

# =========================
# Main
# =========================
function main {
    Initialize-LogsFolder
    Invoke-CheckAdminElevation
    Test-NetworkConnectivity
    Test-VirtualizationPrereqs

    # Ensure core Windows features
    $dismOutput = dism.exe /online /get-featureinfo /featurename:Microsoft-Windows-Subsystem-Linux | Select-String "State : (\w+)"
    $wslFeatureState = $dismOutput.Matches[0].Groups[1].Value
    if ($wslFeatureState -ne "Enabled") {
        Enable-WSLFeature
    }

    Enable-HyperVFeature
    Set-WSLDefaultVersion2

    if (-Not (Test-Path -Path $WSLConfigPath) -or -Not ((Get-Content -Path $WSLConfigPath -ErrorAction SilentlyContinue) -match 'kernelCommandLine\s*=\s*cgroup_no_v1=all')) {
        Update-WSLConfig $WSLConfigPath
    }

    if (-Not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-OutputLog "Git is not installed. Please install Git before proceeding."
        Read-Host -Prompt "Press Enter to exit"
        Exit 1
    }

    Write-OutputLog "Starting NixOS WSL setup..."

    $wslCheck = $null
    try { $wslCheck = wsl.exe --version 2>$null } catch {}
    if (-Not $wslCheck) { Install-WSL }

    $wslInstances = (wsl.exe -l -q) -split "(`r`n|`n|`r)" | Where-Object { $_ -and $_.Trim() -ne "" }
    if ($wslInstances -contains "NixOS") {
        Unregister-NixOS
    }

    if (-Not (Test-Path -Path $NixOSPackage)) {
        Invoke-DownloadNixOSPackage
    }

    if (-Not (Test-Path -Path $RepoPath)) {
        Invoke-CloneDotfilesRepository
    }
    else {
        Update-DotfilesRepository
    }

    Import-NixOS
    Set-DefaultWSL

    Copy-NixOSConfigurationFiles
    Invoke-RebuildWithFlake "~/nix-config#nixos-wsl"

    Stop-WSL
    Set-Ownership
    Set-UserPassword
    Remove-OldHomeManagerProfiles
    Remove-OldHomeManagerGcroots
    New-NixFilesDirectory
    Copy-NixFiles
    Invoke-RebuildWithFlake "~/nix-config#nixos-wsl"
    Remove-OldDotfilesRepo
    Invoke-CloneNewDotfilesRepo
    Invoke-RebuildWithFlake "~/nix-config#nixos-wsl"

    Write-OutputLog "Setup complete."

    try { Stop-Transcript | Out-Null } catch {}
    Read-Host -Prompt "Press Enter to exit"
}

main
