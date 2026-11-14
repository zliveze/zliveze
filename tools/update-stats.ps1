#Requires -Version 5.1
<#
.SYNOPSIS
  Regenerates assets/stats.svg and assets/languages.svg from live GitHub data.

.DESCRIPTION
  Only PUBLIC, non-fork repositories are aggregated — private code never leaks
  into the published charts. Run from the repo root:

    powershell -ExecutionPolicy Bypass -File tools\update-stats.ps1
#>
param(
    [string]$Gh = "gh",
    [string]$User = "zliveze",
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "assets")
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# ---- fetch data (public repos only) ----
$query = @'
query($login: String!) { user(login: $login) { contributionsCollection { contributionCalendar { totalContributions } } followers { totalCount } repositories(first: 100, ownerAffiliations: OWNER, privacy: PUBLIC) { totalCount nodes { name isFork stargazerCount languages(first: 10) { edges { size node { name color } } } } } } }
'@
# PowerShell 5.1 mangles multi-line native arguments — collapse to one line
$queryOneLine = (($query -split '\s+') -join ' ').Trim()
$raw = & $Gh api graphql -f query=$queryOneLine -f login=$User 2>$null
$raw = ($raw | Out-String).Trim()
$json = $raw | ConvertFrom-Json
if ($json.errors) { throw ($json.errors | ConvertTo-Json) }
# NOTE: not $user — the [string]$User param keeps a type constraint in this scope
$udata = $json.data.user

$repos = @($udata.repositories.nodes | Where-Object { -not $_.isFork })
$contributions = $udata.contributionsCollection.contributionCalendar.totalContributions
$repoCount = $udata.repositories.totalCount
$stars = ($repos | Measure-Object -Property stargazerCount -Sum).Sum
$followers = $udata.followers.totalCount

# ---- aggregate languages (public, non-fork only) ----
$langs = @{}
$colors = @{}
foreach ($r in $repos) {
    foreach ($e in $r.languages.edges) {
        $n = $e.node.name
        if (-not $langs.ContainsKey($n)) { $langs[$n] = 0L; $colors[$n] = $e.node.color }
        $langs[$n] = [int64]($langs[$n] + $e.size)
    }
}
$totalBytes = ($langs.Values | Measure-Object -Sum).Sum
$top = $langs.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 7

# ---- svg helpers ----
$esc = { param($t) $t.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;") }
$updated = (Get-Date).ToString("yyyy-MM-dd")

# ---- stats.svg ----
$tileX = @(28, 252); $tileY = @(70, 130)
$tiles = @(
    @("$contributions", "contributions (last 12 mo)"),
    @("$repoCount", "public repositories"),
    @("$stars", "stars earned"),
    @("$followers", "followers")
)
$statsSvg = New-Object System.Text.StringBuilder
[void]$statsSvg.AppendLine('<svg xmlns="http://www.w3.org/2000/svg" width="480" height="185" viewBox="0 0 480 185" role="img" aria-label="GitHub snapshot">')
[void]$statsSvg.AppendLine('  <rect x="0.5" y="0.5" width="479" height="184" rx="12" fill="#0d1117" stroke="#30363d"/>')
[void]$statsSvg.AppendLine('  <circle cx="26" cy="26" r="5" fill="#58a6ff"/>')
[void]$statsSvg.AppendLine('  <text x="42" y="31" font-family="Segoe UI, Helvetica, Arial, sans-serif" font-size="13" font-weight="600" fill="#e6edf3">GITHUB SNAPSHOT</text>')
[void]$statsSvg.AppendLine("  <text x=`"454`" y=`"31`" text-anchor=`"end`" font-family=`"Segoe UI, Helvetica, Arial, sans-serif`" font-size=`"10`" fill=`"#484f58`">updated $updated</text>")
for ($i = 0; $i -lt 4; $i++) {
    $x = $tileX[$i % 2]; $y = $tileY[[math]::Floor($i / 2)]
    [void]$statsSvg.AppendLine("  <text x=`"$x`" y=`"$y`" font-family=`"Segoe UI, Helvetica, Arial, sans-serif`" font-size=`"26`" font-weight=`"700`" fill=`"#e6edf3`">$($tiles[$i][0])</text>")
    [void]$statsSvg.AppendLine("  <text x=`"$x`" y=`"$($y + 20)`" font-family=`"Segoe UI, Helvetica, Arial, sans-serif`" font-size=`"11`" fill=`"#8b949e`">$($tiles[$i][1])</text>")
}
[void]$statsSvg.AppendLine('</svg>')
Set-Content -Path (Join-Path $OutDir "stats.svg") -Value $statsSvg.ToString() -Encoding UTF8

# ---- languages.svg ----
$h = 78 + ($top.Count * 24) + 14
$langSvg = New-Object System.Text.StringBuilder
[void]$langSvg.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"480`" height=`"$h`" viewBox=`"0 0 480 $h`" role=`"img`" aria-label=`"Top languages`">")
[void]$langSvg.AppendLine("  <rect x=`"0.5`" y=`"0.5`" width=`"479`" height=`"$($h - 1)`" rx=`"12`" fill=`"#0d1117`" stroke=`"#30363d`" />")
[void]$langSvg.AppendLine('  <circle cx="26" cy="26" r="5" fill="#3fb950"/>')
[void]$langSvg.AppendLine('  <text x="42" y="31" font-family="Segoe UI, Helvetica, Arial, sans-serif" font-size="13" font-weight="600" fill="#e6edf3">TOP LANGUAGES</text>')
[void]$langSvg.AppendLine("  <text x=`"454`" y=`"31`" text-anchor=`"end`" font-family=`"Segoe UI, Helvetica, Arial, sans-serif`" font-size=`"10`" fill=`"#484f58`">public repos, by code size</text>")
$y = 62
foreach ($e in $top) {
    $pct = if ($totalBytes -gt 0) { [math]::Round($e.Value / $totalBytes * 100, 1) } else { 0 }
    $c = $colors[$e.Name]; if (-not $c) { $c = "#8b949e" }
    $barW = [math]::Max(4, [int](210 * $e.Value / $top[0].Value))
    [void]$langSvg.AppendLine("  <circle cx=`"30`" cy=`"$($y - 4)`" r=`"4`" fill=`"$c`" />")
    [void]$langSvg.AppendLine("  <text x=`"42`" y=`"$y`" font-family=`"Segoe UI, Helvetica, Arial, sans-serif`" font-size=`"12`" fill=`"#e6edf3`">$(& $esc $e.Name)</text>")
    [void]$langSvg.AppendLine("  <rect x=`"170`" y=`"$($y - 11)`" width=`"$barW`" height=`"10`" rx=`"5`" fill=`"$c`" />")
    [void]$langSvg.AppendLine("  <text x=`"454`" y=`"$y`" text-anchor=`"end`" font-family=`"Segoe UI, Helvetica, Arial, sans-serif`" font-size=`"11`" fill=`"#8b949e`">$pct%</text>")
    $y += 24
}
[void]$langSvg.AppendLine('</svg>')
Set-Content -Path (Join-Path $OutDir "languages.svg") -Value $langSvg.ToString() -Encoding UTF8

Write-Host "stats.svg      : contributions=$contributions repos=$repoCount stars=$stars followers=$followers"
Write-Host "languages.svg  : top=$($top.Name -join ', ') (total $totalBytes bytes)"
