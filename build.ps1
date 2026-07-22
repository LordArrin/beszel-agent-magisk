# Build Magisk module zips (publish + personal).
# Requires: PowerShell 5+, Compress-Archive or Info-ZIP `zip` if available.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleDir = Join-Path $Root "module"
$Dist = Join-Path $Root "dist"
$Prop = Join-Path $ModuleDir "module.prop"

if (-not (Test-Path $Prop)) { throw "module.prop not found: $Prop" }

$version = "v1.0.0"
Get-Content $Prop | ForEach-Object {
  if ($_ -match '^version=(.+)$') { $script:version = $Matches[1].Trim() }
}

New-Item -ItemType Directory -Force -Path $Dist | Out-Null

function Convert-ToUnixLF([string]$Path) {
  if (-not (Test-Path $Path)) { return }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  # skip binaries (contain NUL)
  if ($bytes -contains 0) { return }
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $text, $utf8NoBom)
}

# Normalize text scripts to LF (Magisk / ash is picky)
$TextFiles = @(
  "module.prop",
  "customize.sh",
  "service.sh",
  ".env.example",
  ".env",
  "META-INF\com\google\android\update-binary",
  "META-INF\com\google\android\updater-script"
)
foreach ($rel in $TextFiles) {
  Convert-ToUnixLF (Join-Path $ModuleDir $rel)
}

function New-ModuleZip {
  param(
    [Parameter(Mandatory = $true)][string]$OutZip,
    [Parameter(Mandatory = $true)][bool]$IncludeEnv
  )

  $stage = Join-Path $env:TEMP ("beszel-agent-magisk-stage-" + [guid]::NewGuid().ToString("N"))
  if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
  New-Item -ItemType Directory -Force -Path $stage | Out-Null

  try {
    # Copy tree; Magisk zip root == module root
    Copy-Item -Recurse -Force (Join-Path $ModuleDir "*") $stage

    # Always ship .env.example; only personal zip includes secrets .env
    if (-not $IncludeEnv) {
      $envPath = Join-Path $stage ".env"
      if (Test-Path $envPath) { Remove-Item -Force $envPath }
    } else {
      if (-not (Test-Path (Join-Path $stage ".env"))) {
        throw "Personal zip requested but module/.env is missing"
      }
    }

    # Drop any host junk
    Get-ChildItem -Recurse -Force $stage -Include ".DS_Store", "Thumbs.db", "desktop.ini" -ErrorAction SilentlyContinue |
      Remove-Item -Force -ErrorAction SilentlyContinue

    if (Test-Path $OutZip) { Remove-Item -Force $OutZip }

    # Prefer `zip` (Info-ZIP) for Unix-style entries; fall back to Compress-Archive
    $zipCmd = Get-Command zip -ErrorAction SilentlyContinue
    if ($zipCmd) {
      Push-Location $stage
      try {
        & zip -r -9 $OutZip . | Out-Null
      } finally {
        Pop-Location
      }
    } else {
      # Compress-Archive paths are relative when using -Path children
      $items = Get-ChildItem -Force $stage | ForEach-Object { $_.FullName }
      Compress-Archive -Path $items -DestinationPath $OutZip -CompressionLevel Optimal
    }

    $size = (Get-Item $OutZip).Length
    Write-Host ("Created {0} ({1:N0} bytes)" -f $OutZip, $size)
  } finally {
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
  }
}

$pub = Join-Path $Dist ("beszel-agent-magisk-{0}.zip" -f $version)
$personal = Join-Path $Dist ("beszel-agent-magisk-{0}-personal.zip" -f $version)

New-ModuleZip -OutZip $pub -IncludeEnv:$false
New-ModuleZip -OutZip $personal -IncludeEnv:$true

Write-Host ""
Write-Host "Publish : $pub"
Write-Host "Personal: $personal"
