$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
  param([string]$Message)
  $failures.Add($Message)
}

function Test-RequiredFile {
  param([string]$RelativePath)

  $fullPath = Join-Path $repoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    Add-Failure "Missing required file: $RelativePath"
    return $false
  }

  return $true
}

$qmdFiles = @(
  "Hands-on_Ex/Hands-on_Ex02A/Hands-on_Ex02A.qmd",
  "Hands-on_Ex/Hands-on_Ex02B/Hands-on_Ex02B.qmd"
)

$dataFiles = @(
  "Hands-on_Ex/Hands-on_Ex02A/data/geospatial/ChildCareServices.geojson",
  "Hands-on_Ex/Hands-on_Ex02A/data/geospatial/MasterPlan2019SubzoneBoundaryNoSea.geojson",
  "Hands-on_Ex/Hands-on_Ex02B/data/geospatial/ChildCareServices.geojson",
  "Hands-on_Ex/Hands-on_Ex02B/data/geospatial/MasterPlan2019SubzoneBoundaryNoSea.geojson"
)

$renderedPages = @(
  @{
    Path = "_site/Hands-on_Ex/Hands-on_Ex02A/Hands-on_Ex02A.html"
    Title = "Hands-on Exercise 2A"
    MinimumFigures = 10
  },
  @{
    Path = "_site/Hands-on_Ex/Hands-on_Ex02B/Hands-on_Ex02B.html"
    Title = "Hands-on Exercise 2B"
    MinimumFigures = 8
  }
)

foreach ($qmdFile in $qmdFiles) {
  [void](Test-RequiredFile $qmdFile)
}

foreach ($dataFile in $dataFiles) {
  if (-not (Test-RequiredFile $dataFile)) {
    continue
  }

  try {
    $geojson = Get-Content -LiteralPath (Join-Path $repoRoot $dataFile) -Raw | ConvertFrom-Json
    if ($geojson.type -ne "FeatureCollection") {
      Add-Failure "GeoJSON is not a FeatureCollection: $dataFile"
    }
    if ($geojson.features.Count -lt 100) {
      Add-Failure "GeoJSON has too few features to be the required national dataset: $dataFile"
    }
  }
  catch {
    Add-Failure "GeoJSON cannot be parsed: $dataFile ($($_.Exception.Message))"
  }
}

foreach ($page in $renderedPages) {
  if (-not (Test-RequiredFile $page.Path)) {
    continue
  }

  $html = Get-Content -LiteralPath (Join-Path $repoRoot $page.Path) -Raw
  if ($html -notmatch [regex]::Escape($page.Title)) {
    Add-Failure "Rendered page does not contain its expected title: $($page.Path)"
  }
  if ($html -match "Quitting from|Execution halted|Error in") {
    Add-Failure "Rendered page contains an R or Quarto execution error: $($page.Path)"
  }

  $figureCount = [regex]::Matches($html, '<img\b|class="cell-output-display"').Count
  if ($figureCount -lt $page.MinimumFigures) {
    Add-Failure "Rendered page has $figureCount figure outputs; expected at least $($page.MinimumFigures): $($page.Path)"
  }
}

$indexPath = "_site/index.html"
if (Test-RequiredFile $indexPath) {
  $indexHtml = Get-Content -LiteralPath (Join-Path $repoRoot $indexPath) -Raw
  $expectedLinks = @(
    "Hands-on_Ex/Hands-on_Ex01A/Hands-on_Ex01A.html",
    "Hands-on_Ex/Hands-on_Ex01B/Hands-on_Ex01B.html",
    "Hands-on_Ex/Hands-on_Ex02A/Hands-on_Ex02A.html",
    "Hands-on_Ex/Hands-on_Ex02B/Hands-on_Ex02B.html"
  )

  foreach ($expectedLink in $expectedLinks) {
    if ($indexHtml -notmatch [regex]::Escape($expectedLink)) {
      Add-Failure "Rendered homepage navigation is missing: $expectedLink"
    }
  }
}

if ($failures.Count -gt 0) {
  Write-Host "Hands-on Exercise 2 validation failed:" -ForegroundColor Red
  foreach ($failure in $failures) {
    Write-Host " - $failure" -ForegroundColor Red
  }
  exit 1
}

Write-Host "Hands-on Exercise 2 validation passed." -ForegroundColor Green
