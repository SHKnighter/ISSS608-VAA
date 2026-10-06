param(
    [string]$AcledSource = 'C:\Users\Lenovo\Downloads\Geo\ACLED_Data_Myanmar_Jan2021-Sep2025.csv'
)

# Acquire immutable local source snapshots. Existing recorded files are verified,
# never silently replaced by a newer online response or a different local CSV.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$exerciseRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifestPath = Join-Path $exerciseRoot '_workflow/acquisition.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($relativeDirectory in @('data/raw', '_workflow/sources')) {
    $null = New-Item -ItemType Directory -Path (Join-Path $exerciseRoot $relativeDirectory) -Force
}
$prior = if (Test-Path -LiteralPath $manifestPath) {
    Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
} else { $null }

$definitions = @(
    [ordered]@{
        id = 'acled_events'; provider = 'ACLED'; kind = 'user_supplied_csv'
        local_file = 'data/raw/ACLED_Data_Myanmar_Jan2021-Sep2025.csv'
        source_url = 'https://acleddata.com/'
        local_input = $AcledSource
        original_download_date = $null
        original_download_date_status = 'unknown; filesystem timestamps are not treated as download dates'
        snapshot_label_from_filename = 'January 2021 to September 2025'
        refresh_policy = 'Use the supplied historical snapshot; do not replace with a fresh ACLED export.'
    },
    [ordered]@{
        id = 'mimu_townships'; provider = 'Myanmar Information Management Unit (MIMU)'; kind = 'wfs_geojson'
        local_file = 'data/raw/myanmar-townships-mimu-v9.4.geojson'
        source_url = 'https://geonode.themimu.info/geoserver/wfs?srsName=EPSG%3A4326&typename=geonode%3Ammr_polbnda_adm3_250k_mimu_1&outputFormat=json&version=1.0.0&service=WFS&request=GetFeature'
        layer_name = 'geonode:mmr_polbnda_adm3_250k_mimu_1'
        requested_crs = 'EPSG:4326'; requested_version = 'PCode v9.4'; expected_features = 330
        query_limit = $null
        query_limit_note = 'No maxFeatures parameter: request the nationwide layer.'
        public_release_permission = 'unverified'
        online_use_restriction = 'MIMU metadata states online-platform use requires prior written agreement. Keep the raw boundary local until permission is verified.'
    },
    [ordered]@{
        id = 'mimu_layer_page'; provider = 'MIMU'; kind = 'metadata_html'
        local_file = '_workflow/sources/mimu-townships-v9.4-metadata.html'
        source_url = 'https://geonode.themimu.info/layers/geonode%3Ammr_polbnda_adm3_250k_mimu_1'
    },
    [ordered]@{
        id = 'mimu_layer_api'; provider = 'MIMU'; kind = 'metadata_json'
        local_file = '_workflow/sources/mimu-townships-api.json'
        source_url = 'https://geonode.themimu.info/api/layers/?title__icontains=Township&limit=10'
    },
    [ordered]@{
        id = 'acled_codebook'; provider = 'ACLED'; kind = 'methodology_html'
        local_file = '_workflow/sources/acled-codebook.html'
        source_url = 'https://acleddata.com/methodology/acled-codebook'
        note = 'Current reference captured at acquisition; not claimed to be the codebook version at the unknown original CSV download date.'
    }
)

$records = @()
foreach ($definition in $definitions) {
    $destination = Join-Path $exerciseRoot $definition.local_file
    $recorded = @($prior.sources | Where-Object { $_.id -eq $definition.id })
    if (Test-Path -LiteralPath $destination) {
        if ($recorded.Count -ne 1) {
            throw "Existing file has no unique provenance record: $destination. Inspect it before any acquisition."
        }
        $actualHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($actualHash -ne $recorded[0].sha256) {
            throw "Existing file differs from recorded SHA256: $destination. No file was replaced."
        }
        if ($definition.id -eq 'acled_events' -and (Test-Path -LiteralPath $AcledSource)) {
            if ((Get-FileHash -LiteralPath $AcledSource -Algorithm SHA256).Hash -ne $actualHash) {
                throw 'The supplied ACLED file differs from the recorded snapshot. No file was replaced.'
            }
        }
        $records += $recorded[0]
        Write-Output "Verified existing $($definition.local_file)"
        continue
    }

    $pendingPath = "$destination.pending-$([guid]::NewGuid().ToString('N'))"
    $record = [ordered]@{}
    foreach ($key in $definition.Keys) { $record[$key] = $definition[$key] }
    if ($definition.kind -eq 'user_supplied_csv') {
        if (-not (Test-Path -LiteralPath $AcledSource -PathType Leaf)) {
            throw "Supply the original CSV with -AcledSource: $AcledSource"
        }
        Copy-Item -LiteralPath $AcledSource -Destination $pendingPath
        $sourceHash = (Get-FileHash -LiteralPath $AcledSource -Algorithm SHA256).Hash
        if ((Get-FileHash -LiteralPath $pendingPath -Algorithm SHA256).Hash -ne $sourceHash) {
            throw "Copy verification failed: $pendingPath"
        }
        $record['local_input_sha256'] = $sourceHash
        $record['byte_identical_to_local_input'] = $true
    } else {
        $response = Invoke-WebRequest -Uri $definition.source_url -UseBasicParsing -OutFile $pendingPath -PassThru -TimeoutSec 240
        $record['http_status'] = [int]$response.StatusCode
        $record['http_content_type'] = [string]$response.Headers['Content-Type']
    }
    $acquiredUtc = [DateTimeOffset]::UtcNow
    $record['acquired_at_utc'] = $acquiredUtc.ToString('o')
    $record['acquired_at_singapore'] = $acquiredUtc.ToOffset([TimeSpan]::FromHours(8)).ToString('o')
    $record['bytes'] = (Get-Item -LiteralPath $pendingPath).Length
    $record['sha256'] = (Get-FileHash -LiteralPath $pendingPath -Algorithm SHA256).Hash
    # Destination absence was checked above; never overwrite an existing input.
    Move-Item -LiteralPath $pendingPath -Destination $destination
    $records += [pscustomobject]$record

    # Save completed downloads after each success so an interrupted run resumes.
    $manifest = [ordered]@{
        schema_version = 1
        study = 'Take-home Exercise 2: Myanmar ACLED snapshot and township boundaries'
        acquisition_status = 'in_progress'
        storage_policy = 'Local only. Raw inputs and source snapshots are not approved for commit, publication, or redistribution.'
        sources = @($records) + @($prior.sources | Where-Object { $_.id -notin @($records.id) })
    }
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 12), $utf8)
    Write-Output "Acquired $($definition.local_file) ($($record.bytes) bytes)"
}

$boundary = Get-Content -LiteralPath (Join-Path $exerciseRoot 'data/raw/myanmar-townships-mimu-v9.4.geojson') -Raw | ConvertFrom-Json
if ($boundary.type -ne 'FeatureCollection' -or $boundary.features.Count -ne 330 -or $boundary.totalFeatures -ne 330) {
    throw 'MIMU nationwide feature-count validation failed; inspect the saved response.'
}
$pcodeVersions = @($boundary.features | ForEach-Object { $_.properties.PCode_V } | Sort-Object -Unique)
if ($pcodeVersions.Count -ne 1 -or $pcodeVersions[0] -ne 9.4) {
    throw 'MIMU PCode version is not uniformly v9.4; inspect the saved response.'
}
$metadata = Get-Content -LiteralPath (Join-Path $exerciseRoot '_workflow/sources/mimu-townships-api.json') -Raw | ConvertFrom-Json
$selectedLayer = @($metadata.objects | Where-Object { $_.detail_url -eq '/layers/geonode%3Ammr_polbnda_adm3_250k_mimu_1' })
if ($selectedLayer.Count -ne 1 -or $selectedLayer[0].title -ne 'Myanmar Township Boundaries MIMU v9.4') {
    throw 'MIMU API metadata did not uniquely identify the expected v9.4 layer.'
}
$codebook = Get-Content -LiteralPath (Join-Path $exerciseRoot '_workflow/sources/acled-codebook.html') -Raw
if ($codebook -notmatch 'ACLED Codebook' -or $codebook -notmatch 'geo_precision') {
    throw 'The saved ACLED codebook does not contain the expected methodology content.'
}
$manifest = [ordered]@{
    schema_version = 1
    study = 'Take-home Exercise 2: Myanmar ACLED snapshot and township boundaries'
    acquisition_status = 'complete'
    verified_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
    storage_policy = 'Local only. Raw inputs and source snapshots are not approved for commit, publication, or redistribution.'
    sources = $records
    boundary_checks = [ordered]@{
        geojson_type = $boundary.type
        returned_feature_count = $boundary.features.Count
        total_features = $boundary.totalFeatures
        response_crs = $boundary.crs
        property_names = @($boundary.features[0].properties.PSObject.Properties.Name)
        pcode_version_values = $pcodeVersions
        matching_api_layer_count = $selectedLayer.Count
        api_title = if ($selectedLayer.Count -eq 1) { $selectedLayer[0].title } else { $null }
        api_metadata_date = $selectedLayer[0].date
        api_scale_note = $selectedLayer[0].supplemental_information
    }
    codebook_check = 'ACLED Codebook title and geo_precision field found in saved HTML.'
}
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 12), $utf8)
Write-Output 'Acquisition complete: supplied CSV copy verified; nationwide boundary contains 330 features.'
