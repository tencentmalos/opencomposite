param(
    [string]$VulkanSdk = $env:VULKAN_SDK,
    [string]$WorkDirectory = (Join-Path $PSScriptRoot "build"),
    [string]$Version = "dev",
    [switch]$EnableSystem026
)

$ErrorActionPreference = "Stop"
$commit = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "UPSTREAM_COMMIT")).Trim()
$patch = Join-Path $PSScriptRoot "patches\background-support.patch"
$marker = "Ignoring VRApplication_Background: no shared OpenVR server is available"
$source = Join-Path $WorkDirectory "source"
$build = Join-Path $WorkDirectory "cmake"
$output = Join-Path $WorkDirectory "out"

if ([string]::IsNullOrWhiteSpace($VulkanSdk)) {
    throw "Set VULKAN_SDK or pass -VulkanSdk. OpenComposite needs Vulkan headers and Lib\vulkan-1.lib."
}
$vulkanInclude = Join-Path $VulkanSdk "Include"
$vulkanLibrary = Join-Path $VulkanSdk "Lib\vulkan-1.lib"
if (-not (Test-Path -LiteralPath (Join-Path $vulkanInclude "vulkan\vulkan.h") -PathType Leaf)) {
    throw "Vulkan headers were not found under $vulkanInclude"
}
if (-not (Test-Path -LiteralPath $vulkanLibrary -PathType Leaf)) {
    throw "Vulkan import library was not found at $vulkanLibrary"
}

New-Item -ItemType Directory -Force -Path $WorkDirectory, $output | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $source ".git") -PathType Container)) {
    git clone https://gitlab.com/znixian/OpenOVR.git $source
    if ($LASTEXITCODE -ne 0) { throw "Could not clone OpenComposite" }
}
git -C $source fetch origin $commit
if ($LASTEXITCODE -ne 0) { throw "Could not fetch OpenComposite commit $commit" }
git -C $source checkout --detach --force $commit
if ($LASTEXITCODE -ne 0) { throw "Could not check out OpenComposite commit $commit" }
git -C $source submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw "Could not initialize OpenComposite submodules" }
git -C $source reset --hard $commit
git -C $source clean -dffx
git -C $source apply --check $patch
if ($LASTEXITCODE -ne 0) { throw "The patch no longer applies to $commit" }
git -C $source apply $patch
if ($LASTEXITCODE -ne 0) { throw "Could not apply the patch" }

# Opt-in until a Windows build and Alyx replay validate the newer ABI. The default
# recipe still reproduces the reviewed v2 payload used by XRGame Native.
if ($EnableSystem026) {
    $header = Join-Path $PSScriptRoot "vendor\openvr-2.15.6\openvr.h"
    # The pinned hash is of the LF file; a Windows checkout with core.autocrlf has CRLF.
    $headerText = [System.IO.File]::ReadAllText($header).Replace("`r`n", "`n")
    $headerBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($headerText)
    $headerHash = -join ([System.Security.Cryptography.SHA256]::HashData($headerBytes) |
        ForEach-Object { $_.ToString("x2") })
    if ($headerHash -ne "1e6ed57199896cc1f7c5484e50fa18955e97be15be690beb28d998c877ead7fd") {
        throw "OpenVR 2.15.6 header checksum mismatch"
    }
    Copy-Item -LiteralPath $header -Destination (Join-Path $source "OpenVRHeaders\openvr-2.15.6.h")
    $systemPatch = Join-Path $PSScriptRoot "patches\openvr-system-026.patch"
    git -C $source apply --check $systemPatch
    if ($LASTEXITCODE -ne 0) { throw "System 026 patch no longer applies" }
    git -C $source apply $systemPatch
    if ($LASTEXITCODE -ne 0) { throw "Could not apply System 026 patch" }
}

# Forwards SteamVR mailbox messages (Half-Life: Alyx loading interstitials) to the OpenXR
# runtime through xrSendMailboxMessageGNX; a no-op on runtimes without that function.
$mailboxPatch = Join-Path $PSScriptRoot "patches\mailbox-forward.patch"
$mailboxMarker = "xrSendMailboxMessageGNX"
git -C $source apply --check $mailboxPatch
if ($LASTEXITCODE -ne 0) { throw "Mailbox forward patch no longer applies" }
git -C $source apply $mailboxPatch
if ($LASTEXITCODE -ne 0) { throw "Could not apply the mailbox forward patch" }

$bundledVulkan = Join-Path $source "libs\vulkan"
New-Item -ItemType Directory -Force -Path (Join-Path $bundledVulkan "Include"), (Join-Path $bundledVulkan "Lib") | Out-Null
Copy-Item -Recurse -Force -Path (Join-Path $vulkanInclude "*") -Destination (Join-Path $bundledVulkan "Include")
Copy-Item -Force -LiteralPath $vulkanLibrary -Destination (Join-Path $bundledVulkan "Lib\vulkan-1.lib")

$shortCommit = $commit.Substring(0, 7)
cmake -S $source -B $build -A x64 -DOC_VERSION="$shortCommit-gamenative-$Version"
if ($LASTEXITCODE -ne 0) { throw "Could not configure OpenComposite" }
cmake --build $build --config Release --target OCOVR --parallel
if ($LASTEXITCODE -ne 0) { throw "Could not build OpenComposite" }

$binary = Join-Path $build "bin\Release\vrclient_x64.dll"
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw "OpenComposite output is missing: $binary" }
$bytes = [System.IO.File]::ReadAllBytes($binary)
$offset = [BitConverter]::ToInt32($bytes, 0x3c)
if ([BitConverter]::ToUInt16($bytes, $offset + 4) -ne 0x8664) { throw "Output is not x64" }
if (-not [System.Text.Encoding]::ASCII.GetString($bytes).Contains($marker)) { throw "Output does not contain the background-app patch" }
if (-not [System.Text.Encoding]::ASCII.GetString($bytes).Contains($mailboxMarker)) { throw "Output does not contain the mailbox forward patch" }

$destination = Join-Path $output "opencomposite_x64.dll"
Copy-Item -Force -LiteralPath $binary -Destination $destination
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
Set-Content -NoNewline -LiteralPath "$destination.sha256" -Value "$hash  opencomposite_x64.dll"
Write-Host "Built $destination"
Write-Host "sha256 $hash"
