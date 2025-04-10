#Requires -Version 5.1

param (
    [Parameter(Mandatory = $true, HelpMessage = "Path to the MSIX file.")]
    [string]$MsixPath
)

# Get the directory containing the MSIX file
$MsixDirectory = Split-Path -Path $MsixPath -Parent

# Get the file object of the MSIX
$MsixFile = Get-Item -Path $MsixPath
$MsixFilename = $MsixFile.BaseName
$MsixExtension = $MsixFile.Extension

# Create a temporary directory in the Windows temp folder
$TempDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("IntuneWinTemp_" + [System.Guid]::NewGuid().ToString().Substring(0, 8))
$AppDirectory = Join-Path -Path $TempDirectory -ChildPath "App"

# Create the temporary directories if they don't exist
if (-not (Test-Path -Path $TempDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $TempDirectory | Out-Null
}
if (-not (Test-Path -Path $AppDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $AppDirectory | Out-Null
}

# Copy the MSIX file to the App directory, renaming it to App.{original extension}
Copy-Item -Path $MsixPath -Destination (Join-Path -Path $AppDirectory -ChildPath ("App" + $MsixExtension))

# Copy the files in the same directory (excluding the original MSIX) to the App directory
Get-ChildItem -Path $MsixDirectory | Where-Object { $_.Name -ne $MsixFile.Name -and $_.Extension -ne ".intunewin" } | Copy-Item -Destination $AppDirectory -Recurse -Force

# Copy the DeploymentScripts folder to the temporary directory's root
$DeploymentScriptsPath = Join-Path -Path $PSScriptRoot -ChildPath "DeploymentScripts"
if (Test-Path -Path $DeploymentScriptsPath -PathType Container) {
    Copy-Item -Path $DeploymentScriptsPath -Destination $TempDirectory -Recurse -Force
}

# Construct the IntuneWinAppUtil command
$IntuneWinAppUtilPath = Join-Path -Path $PSScriptRoot -ChildPath "IntuneWinAppUtil.exe"
$TempOutputIntuneWinPath = Join-Path -Path $TempDirectory -ChildPath "Install.intunewin" # Create IntuneWin in temp.
$ContentSource = $TempDirectory
$SetupFile = Join-Path $TempDirectory "DeploymentScripts/Install.ps1"
$OutputFolder = $TempDirectory #Output to temp



# Run IntuneWinAppUtil.exe
try {
    Write-Host "Util Path: $($IntuneWinAppUtilPath)"
    Write-Host "Running IntuneWinAppUtil.exe with the following parameters:"
    Write-Host "  - Content Source: $ContentSource"
    Write-Host "  - Setup File: $SetupFile"
    Write-Host "  - Output Folder: $OutputFolder"

    # Capture output and errors from IntuneWinAppUtil.exe
    $utilOutput = & $IntuneWinAppUtilPath -c $ContentSource -s $SetupFile -o $OutputFolder -q 2>&1
    Write-Host "IntuneWinAppUtil Output:"
    Write-Host $utilOutput

    # Check if the output file exists
    if (-not (Test-Path -Path $TempOutputIntuneWinPath)) {
        Write-Error "Expected output file '$TempOutputIntuneWinPath' does not exist. IntuneWinAppUtil.exe might have failed."
        Write-Error "Output from IntuneWinAppUtil.exe: $utilOutput"
        exit 1
    }

    Rename-Item -Path $TempOutputIntuneWinPath -NewName "$($MsixFilename).intunewin"
    $TempOutputIntuneWinPath = Join-Path -Path $TempDirectory -ChildPath "$($MsixFilename).intunewin"

    # Copy the final .intunewin to the original MSIX directory
    Copy-Item -Path $TempOutputIntuneWinPath -Destination (Join-Path -Path $MsixDirectory -ChildPath "$($MsixFilename).intunewin") -Force
    Write-Host "Final IntuneWin file: $(Join-Path -Path $MsixDirectory -ChildPath "$($MsixFilename).intunewin")"
}
catch {
    Write-Error "Failed to create IntuneWin file: $($_.Exception.Message)"
    exit 1
}
finally {
    # Remove the temporary directory
    Remove-Item -Path $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
