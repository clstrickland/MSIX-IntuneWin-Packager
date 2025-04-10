#Requires -Modules eps

<#
.SYNOPSIS
 Processes *.template files using the eps module for placeholder replacement.

.DESCRIPTION
 Finds all *.template files in the .\DeploymentScripts directory,
 performs placeholder replacements based on command-line arguments,
 and saves the processed files to the .\output directory without the
 .template extension.

 Placeholders should be in the format: <%= $VARIABLE_NAME %>

.PARAMETER FormatArguments
 Specifies the key-value pairs for placeholder replacement.
 Use the format -f:KEY=VALUE. Multiple arguments can be provided.
 Example: .\process-templates.ps1 -f:SOME_VAR1=foo -f:DATABASE_NAME=MyDb

.EXAMPLE
 .\Processor.ps1 --f:API_ENDPOINT=https://prod.example.com --f:VERSION=1.2.3

 This command processes templates in .\DeploymentScripts, replacing <%= API_ENDPOINT %>
 with 'https://prod.example.com' and <%= VERSION %> with '1.2.3', saving
 the results in .\output.

.NOTES
 Requires the 'eps' module (straightdave/eps). Install using:
 Install-Module -Name eps -Repository PSGallery -Scope CurrentUser
 Assumes input directory .\DeploymentScripts and creates .\output if it doesn't exist.
#>
param(
    [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
    [string[]]$FormatArguments
)

# --- Configuration ---
$inputDirectory = Join-Path $PSScriptRoot "DeploymentScriptsTemplates"
$outputDirectory = Join-Path $PSScriptRoot "DeploymentScripts"
$templateExtension = ".eps"
# --- End Configuration ---
Import-Module EPS

# Ensure the eps module is available
if (-not (Get-Command Invoke-EpsTemplate -ErrorAction SilentlyContinue)) {
    Write-Error "The 'eps' module is required but not found. Please install it:"
    Write-Error "Install-Module -Name eps -Repository PSGallery -Scope CurrentUser"
    exit 1
}

# --- Argument Parsing ---
$variables = @{}
if ($PSBoundParameters.ContainsKey('FormatArguments')) {
    foreach ($arg in $FormatArguments) {
        if ($arg -like '--f:*' -and $arg.Contains('=')) {
            $kvp = $arg.Substring(4) # Remove '-f:'
            $index = $kvp.IndexOf('=')
            if ($index -gt 0) {
                $key = $kvp.Substring(0, $index).Trim()
                # Ensure key only contains valid variable characters if needed, or trust user input
                # if ($key -match '^[a-zA-Z0-9_]+$') {
                    $value = $kvp.Substring($index + 1).Trim()
                    $variables[$key] = $value
                    Write-Verbose "Parsed variable: '$key' = '$value'"
                # } else {
                #    Write-Warning "Skipping invalid variable name '$key' in argument '$arg'."
                # }
            } else {
                # '=' was at the beginning, invalid format
                Write-Warning "Could not parse argument '$arg'. Expected format: -f:KEY=VALUE"
            }
        } else {
            Write-Warning "Ignoring incorrectly formatted or unknown argument: '$arg'. Expected format: -f:KEY=VALUE"
        }
    }
}

if ($variables.Count -eq 0) {
    Write-Warning "No replacement variables provided via -f:KEY=VALUE arguments."
    # Decide if you want to continue with no replacements or exit
    # exit 1
} else {
    Write-Host "Using the following variables for replacement:"
    $variables.GetEnumerator() | ForEach-Object { Write-Host ("  " + $_.Key + " = " + $_.Value) }
}

# --- Directory Validation and Setup ---
# Check if input directory exists
if (-not (Test-Path -Path $inputDirectory -PathType Container)) {
    Write-Error "Input directory '$inputDirectory' not found."
    exit 1
}

# Create output directory if it doesn't exist
if (-not (Test-Path -Path $outputDirectory -PathType Container)) {
    Write-Verbose "Creating output directory '$outputDirectory'."
    try {
        New-Item -Path $outputDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create output directory '$outputDirectory': $($_.Exception.Message)"
        exit 1
    }
}

# --- File Processing ---
# Find template files
$templateFiles = Get-ChildItem -Path $inputDirectory -Filter "*$templateExtension" -File -ErrorAction SilentlyContinue

if ($null -eq $templateFiles -or $templateFiles.Count -eq 0) {
    Write-Warning "No '$templateExtension' files found in '$inputDirectory'."
    exit 0 # Exit gracefully as there's nothing to do
}

Write-Host "Found $($templateFiles.Count) template file(s). Processing..."

foreach ($file in $templateFiles) {
    $outputFileName = $file.Name.Replace($templateExtension, "")
    $outputPath = Join-Path -Path $outputDirectory -ChildPath $outputFileName

    Write-Host "Processing '$($file.Name)' -> '$($outputFileName)'"
    Write-Verbose "Input:  $($file.FullName)"
    Write-Verbose "Output: $outputPath"

    try {
        # Read content, expand using eps, and write to output file
        Invoke-EpsTemplate -Path $file.FullName -Safe -Binding $variables -ErrorAction Stop |
        Set-Content -Path $outputPath -Encoding UTF8 # Use UTF8 encoding, change if needed
    } catch {
        Write-Error "Failed to process file '$($file.FullName)': $($_.Exception.Message)"
        # Optionally, you might want to continue with the next file instead of exiting
        # continue
    }
}

Write-Host "Processing complete. Output files are in '$outputDirectory'."
