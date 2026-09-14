$ErrorActionPreference='Stop'
$taskRoot='C:\SHKnighter\ISSS608-VAA\Take-home_Ex\Take-home_Ex01'
$siteRoot='C:\SHKnighter\ISSS608-VAA\_site'
$pages=@('Take-home_Ex01','technical-report','executive-summary')
$broken=@()
foreach($page in $pages){
 $path=Join-Path $siteRoot "Take-home_Ex\Take-home_Ex01\$page.html"
 $html=Get-Content -LiteralPath $path -Raw -Encoding UTF8
 if($html -match 'Data acquisition is in progress|In preparation|will be added after'){throw "Placeholder in $page"}
 foreach($m in [regex]::Matches($html,'(?:src|href)="([^"]+)"')){
  $ref=[Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
  if($ref -match '^(https?:|data:|mailto:|#|javascript:)'){continue}
  $ref=($ref -split '[?#]')[0]
  if(-not $ref){continue}
  $ref=[Uri]::UnescapeDataString($ref)
  $target=if($ref.StartsWith('/')){Join-Path $siteRoot $ref.TrimStart('/')}else{Join-Path (Split-Path $path) $ref}
  if(-not(Test-Path -LiteralPath $target)){$broken+="$page : $ref"}
 }
}
if($broken){throw ($broken -join "`n")}
$report=Get-Content -LiteralPath (Join-Path $taskRoot 'technical-report.qmd') -Raw -Encoding UTF8
$public=[regex]::Match($report,'(?s)## Public-safety planning and management\s+(.*?)\s+## Limitations').Groups[1].Value
$public=$public -replace '\]\([^)]*\)',']'
$words=[regex]::Matches($public,'\b[\w]+(?:[-''][\w]+)*\b').Count
if($words -gt 500){throw "Public safety exceeds 500 words: $words"}
$slideSource=Get-Content -LiteralPath (Join-Path $taskRoot 'executive-summary.qmd') -Raw -Encoding UTF8
$slides=[regex]::Matches($slideSource,'(?m)^## ').Count
if($slides -ne 8){throw "Unexpected body slide count $slides"}
$mapCounts=@()
foreach($m in [regex]::Matches($report,'(?s)\*\*Map interpretation\.\*\*\s*(.*?)(?:\r?\n){2}')){
 $n=[regex]::Matches($m.Groups[1].Value,'\b[\w]+(?:[-''][\w]+)*\b').Count
 if($n -gt 150){throw "Map interpretation exceeds 150 words: $n"};$mapCounts+=$n
}
"PASS: local HTML links/resources, no preparation placeholders, $slides body slides; public safety $words words; map paragraphs $($mapCounts -join ', ') words (conservative source count)."
