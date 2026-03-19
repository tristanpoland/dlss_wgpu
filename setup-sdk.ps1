<#
.SYNOPSIS
  Helper script to configure VULKAN_SDK and DLSS_SDK environment variables for dlss_wgpu.

.DESCRIPTION
  This script checks for the expected SDK directory layout and sets
  the required environment variables in the current PowerShell session.
  Optionally, it can persist them as user environment variables.

.PARAMETER VulkanSdk
  Path to the Vulkan SDK root directory (e.g. C:\VulkanSDK\1.4.304.0).

.PARAMETER DlssSdk
  Path to the NVIDIA DLSS/NGX SDK root directory (e.g. C:\NVIDIA\DLSS_SDK).

.PARAMETER Persist
  If set, will persist the environment variables to the current user environment.

.EXAMPLE
  .\setup-sdk.ps1 -Persist

  Asks for SDK locations if not already set, validates them, sets them in the current session,
  and persists them for new sessions.
#>

param(
    [string]$VulkanSdk = $env:VULKAN_SDK,
    [string]$DlssSdk = $env:DLSS_SDK,
    [switch]$Persist,
    [switch]$AutoDownload = $true,
    [switch]$UseGithubDlss = $true,
    [switch]$InstallVulkan = $true,
    [string]$DlssGitUrl = "https://github.com/NVIDIA/DLSS.git",
    [string]$VulkanVersion = "1.4.304.0",
    [string]$DlssUrl
)

function Confirm-Path($path, $description) {
    if (-not (Test-Path $path -PathType Any)) {
        Write-Error "$description not found: $path"
        return $false
    }
    return $true
}

# No prompts; always run in non-interactive mode.
function Normalize-Path([string]$value) {
    if (-not $value) { return $null }
    $value = $value.Trim('"').Trim()
    return if ([string]::IsNullOrWhiteSpace($value)) { $null } else { $value }
}

function Download-File($url, $dest) {
    Write-Host "Downloading $url -> $dest" -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        Write-Error "Failed to download ${url}: $_"
        return $false
    }
}

function Git-Clone($url, $dest) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Error "Git is not installed or not on PATH. Cannot clone $url."
        return $false
    }

    Write-Host "Cloning $url -> $dest" -ForegroundColor Cyan
    if (Test-Path $dest) {
        Write-Host "Destination already exists; pulling latest changes..." -ForegroundColor Yellow
        Push-Location $dest
        git pull --ff-only
        $success = $LASTEXITCODE -eq 0
        Pop-Location
        return $success
    }

    git clone --recurse-submodules $url $dest
    return $LASTEXITCODE -eq 0
}

function Ensure-Directory([string]$path) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

Write-Host "=== dlss_wgpu SDK setup helper ===" -ForegroundColor Cyan

$VulkanSdk = Normalize-Path $VulkanSdk
$DlssSdk = Normalize-Path $DlssSdk

$expectedVulkanHeader = if ($VulkanSdk) { Join-Path $VulkanSdk 'Include\vulkan\vulkan.h' } else { $null }
$expectedDlssHeader = if ($DlssSdk) { Join-Path $DlssSdk 'include\nvsdk_ngx_helpers.h' } else { $null }

$valid = $true

if ($expectedVulkanHeader) {
    if (-not (Confirm-Path $expectedVulkanHeader 'Vulkan header')) {
        Write-Warning "Expected file: $expectedVulkanHeader"
        $valid = $false
    }
} else {
    Write-Warning "VULKAN_SDK not provided."
    $valid = $false
}

if ($expectedDlssHeader) {
    if (-not (Confirm-Path $expectedDlssHeader 'DLSS header')) {
        Write-Warning "Expected file: $expectedDlssHeader"
        $valid = $false
    }
} else {
    Write-Warning "DLSS_SDK not provided."
    $valid = $false
}

if (-not $valid) {
    if ($AutoDownload) {
        Write-Host "\nAttempting to automatically obtain missing SDKs..." -ForegroundColor Cyan

        if (-not (Confirm-Path $expectedVulkanHeader 'Vulkan header')) {
            $downloadDir = Join-Path $PWD 'sdk-downloads'
            Ensure-Directory $downloadDir
            $installer = Join-Path $downloadDir "VulkanSDK-$VulkanVersion-Installer.exe"
            $url = "https://sdk.lunarg.com/sdk/download/$VulkanVersion/windows/VulkanSDK-$VulkanVersion-Installer.exe"

            if (Download-File $url $installer) {
                Write-Host "Downloaded Vulkan SDK installer to: $installer" -ForegroundColor Green
                if ($InstallVulkan) {
                    Write-Host "Running Vulkan SDK installer (silent)..." -ForegroundColor Cyan
                    $installDir = "C:\VulkanSDK\$VulkanVersion"
                    Start-Process -FilePath $installer -ArgumentList "/S /D=$installDir" -Wait
                    $VulkanSdk = $installDir
                    Write-Host "Installed Vulkan SDK to: $VulkanSdk" -ForegroundColor Green
                } else {
                    Write-Host "Run the installer and then re-run this script." -ForegroundColor Yellow
                    Write-Host "(Installer will install to C:\VulkanSDK\$VulkanVersion by default.)" -ForegroundColor Yellow
                    $VulkanSdk = "C:\VulkanSDK\$VulkanVersion"
                }
            } else {
                Write-Warning "Unable to download Vulkan SDK; please download it from https://vulkan.lunarg.com/."
            }

            # update path in case install succeeded
            $expectedVulkanHeader = if ($VulkanSdk) { Join-Path $VulkanSdk 'Include\vulkan\vulkan.h' } else { $null }
        }

        if (-not (Confirm-Path $expectedDlssHeader 'DLSS header')) {
            if ($UseGithubDlss) {
                $downloadDir = Join-Path $PWD 'sdk-downloads'
                Ensure-Directory $downloadDir
                $gitDir = Join-Path $downloadDir 'dlss_git'

                if (Git-Clone $DlssGitUrl $gitDir) {
                    Write-Host "Cloned DLSS SDK repository to: $gitDir" -ForegroundColor Green
                    Write-Host "(You can update it later with 'git -C $gitDir pull --recurse-submodules')" -ForegroundColor Yellow
                    $DlssSdk = $gitDir
                } else {
                    Write-Warning "Failed to clone DLSS SDK repository. Please ensure git is installed and try again."
                }
            } elseif ($DlssUrl) {
                $downloadDir = Join-Path $PWD 'sdk-downloads'
                Ensure-Directory $downloadDir
                $zipPath = Join-Path $downloadDir "dlss_sdk.zip"
                $extractDir = Join-Path $downloadDir "dlss_sdk"

                if (Download-File $DlssUrl $zipPath) {
                    Write-Host "Downloaded DLSS SDK archive to: $zipPath" -ForegroundColor Green
                    Write-Host "Extracting archive..." -ForegroundColor Cyan
                    Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
                    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
                    Write-Host "Extracted DLSS SDK to: $extractDir" -ForegroundColor Green
                    Write-Host "Set DLSS_SDK to: $extractDir" -ForegroundColor Yellow
                    $DlssSdk = $extractDir
                } else {
                    Write-Warning "Failed to download DLSS SDK from provided URL. Please download manually from https://developer.nvidia.com/rtx/ngx."
                }
            } else {
                Write-Host "\nCould not obtain DLSS SDK automatically (no source specified)." -ForegroundColor Yellow
            }

            # update path in case clone/extract succeeded
            $expectedDlssHeader = if ($DlssSdk) { Join-Path $DlssSdk 'include\nvsdk_ngx_helpers.h' } else { $null }
        }

        Write-Host "\nAfter installing/extracting, rerun this script (or set DLSS_SDK/VULKAN_SDK manually)." -ForegroundColor Cyan

        # Re-check validity after attempting downloads
        $expectedVulkanHeader = if ($VulkanSdk) { Join-Path $VulkanSdk 'Include\vulkan\vulkan.h' } else { $null }
        $expectedDlssHeader = if ($DlssSdk) { Join-Path $DlssSdk 'include\nvsdk_ngx_helpers.h' } else { $null }
        $valid = $true
        if ($expectedVulkanHeader -and -not (Confirm-Path $expectedVulkanHeader 'Vulkan header')) {
            $valid = $false
        }
        if ($expectedDlssHeader -and -not (Confirm-Path $expectedDlssHeader 'DLSS header')) {
            $valid = $false
        }

        if (-not $valid) {
            Write-Error "Automatic acquisition did not produce required SDK files. Please set VULKAN_SDK and DLSS_SDK manually."
            exit 1
        }
    } else {
        Write-Host "\nIf you do not have either SDK installed, visit:" -ForegroundColor Yellow
        Write-Host "  Vulkan SDK: https://vulkan.lunarg.com/" -ForegroundColor Yellow
        Write-Host "  NVIDIA NGX/DLSS SDK: https://developer.nvidia.com/rtx/ngx" -ForegroundColor Yellow
        exit 1
    }
}

# Final validation: ensure we actually have usable SDK paths
$expectedVulkanHeader = if ($VulkanSdk) { Join-Path $VulkanSdk 'Include\vulkan\vulkan.h' } else { $null }
$expectedDlssHeader = if ($DlssSdk) { Join-Path $DlssSdk 'include\nvsdk_ngx_helpers.h' } else { $null }

$valid = $true
if (-not ($expectedVulkanHeader -and (Test-Path $expectedVulkanHeader))) {
    Write-Error "Vulkan SDK not found or missing header: $expectedVulkanHeader"
    $valid = $false
}
if (-not ($expectedDlssHeader -and (Test-Path $expectedDlssHeader))) {
    Write-Error "DLSS SDK not found or missing header: $expectedDlssHeader"
    $valid = $false
}

if (-not $valid) {
    Write-Error "SDK setup failed; please ensure the SDKs are installed and environment variables are set."
    exit 1
}

# Set environment variables for current session
$env:VULKAN_SDK = $VulkanSdk
$env:DLSS_SDK = $DlssSdk

Write-Host "\nSuccess: SDK environment variables configured for this session." -ForegroundColor Green
Write-Host "  VULKAN_SDK=$VULKAN_SDK"
Write-Host "  DLSS_SDK=$DLSS_SDK"

if ($Persist) {
    Write-Host "\nPersisting environment variables to user environment..." -ForegroundColor Cyan
    [System.Environment]::SetEnvironmentVariable('VULKAN_SDK', $VulkanSdk, 'User')
    [System.Environment]::SetEnvironmentVariable('DLSS_SDK', $DlssSdk, 'User')
    Write-Host "Done. Restart your shell or log out/in to pick up the changes." -ForegroundColor Green
}

Write-Host "\nYou can now run: cargo check" -ForegroundColor Cyan
