# Regenerates assets/geo/geosite-ads.srs — the rule-set behind the
# "Блокировка рекламы" switch.
#
# Why a merge and not just the upstream geosite set: SagerNet's
# geosite-category-ads-all holds only ~890 entries. They are broad apex
# suffixes (doubleclick.net, googlesyndication.com) that cover every
# subdomain, which is valuable — but 890 domains is a very thin ad blocker.
# HaGeZi's Multi NORMAL adds ~186k specific ad/tracker hosts, yet frequently
# lists hosts without their apex (ad.at.doubleclick.net but not
# doubleclick.net). Merging both is strictly better than either alone.
#
# Usage:  pwsh -File tool/build_ads_ruleset.ps1
# Requires sing-box.exe on PATH or next to the Windows build.
param(
    [string]$SingBox = 'build/windows/x64/runner/Release/sing-box.exe',
    [string]$Output  = 'assets/geo/geosite-ads.srs'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $SingBox)) {
    $cmd = Get-Command sing-box -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "sing-box.exe not found (looked in $SingBox and PATH)" }
    $SingBox = $cmd.Source
}
$work = Join-Path ([System.IO.Path]::GetTempPath()) "aurora-ads-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $work | Out-Null
$ProgressPreference = 'SilentlyContinue'

Write-Host 'Downloading sources…'
Invoke-WebRequest 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs' -OutFile "$work/sager.srs" -TimeoutSec 90
Invoke-WebRequest 'https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/multi-onlydomains.txt' -OutFile "$work/hagezi.txt" -TimeoutSec 120

& $SingBox rule-set decompile --output "$work/sager.json" "$work/sager.srs" | Out-Null
$rule = (Get-Content "$work/sager.json" -Raw | ConvertFrom-Json).rules[0]

# Suffixes are stored bare (no leading dot) — the convention the upstream
# geosite sets use, where a suffix already covers the apex and its subdomains.
$suffix = [System.Collections.Generic.HashSet[string]]::new()
foreach ($d in @($rule.domain))        { [void]$suffix.Add($d.ToLowerInvariant()) }
foreach ($d in @($rule.domain_suffix)) { [void]$suffix.Add($d.TrimStart('.').ToLowerInvariant()) }
$fromSager = $suffix.Count
foreach ($line in [System.IO.File]::ReadLines("$work/hagezi.txt")) {
    $d = $line.Trim().ToLowerInvariant()
    if (-not $d -or $d.StartsWith('#') -or $d.StartsWith('*')) { continue }
    [void]$suffix.Add($d)
}
Write-Host "SagerNet: $fromSager, merged: $($suffix.Count)"

# Anything that would break normal browsing must never end up in an ad list.
$mustWork = @('googlevideo.com', 'youtube.com', 'google.com', 'telegram.org',
              'vk.com', 'yandex.ru', 'github.com', 'cloudflare.com')
$broken = @($mustWork | Where-Object { $suffix.Contains($_) })
if ($broken.Count) { throw "refusing to build: blocklist contains $($broken -join ', ')" }

$json = "$work/src.json"
$w = [System.IO.StreamWriter]::new($json, $false, [System.Text.UTF8Encoding]::new($false))
$w.Write('{"version":3,"rules":[{"domain_suffix":[')
$first = $true
foreach ($d in $suffix) {
    if (-not $first) { $w.Write(',') }
    $w.Write('"'); $w.Write($d); $w.Write('"'); $first = $false
}
$w.Write(']')
$keywords = @($rule.domain_keyword | Where-Object { $_ -and $_.Trim() })
$regexes = @($rule.domain_regex | Where-Object { $_ -and $_.Trim() })
foreach ($pair in @(@{k = 'domain_keyword'; v = $keywords }, @{k = 'domain_regex'; v = $regexes })) {
    if ($pair.v.Count) {
        $w.Write(',"' + $pair.k + '":[')
        $w.Write((($pair.v | ForEach-Object { '"' + ($_ -replace '\\', '\\') + '"' }) -join ','))
        $w.Write(']')
    }
}
$w.Write('}]}')
$w.Close()

& $SingBox rule-set compile --output $Output $json
if ($LASTEXITCODE -ne 0) { throw 'sing-box rule-set compile failed' }
# Verify the COMPILED set, not just the source list: a single bad keyword or
# regex can make it match everything, and only a real match test catches that.
foreach ($d in $mustWork + @('example.com', 'mangalib.org')) {
    $hit = & $SingBox rule-set match -f binary $Output $d 2>&1 | Select-String 'match rules'
    if ($hit) { throw "compiled rule-set matches $d — refusing to ship (would block normal traffic)" }
}
foreach ($d in @('doubleclick.net', 'googlesyndication.com', 'adriver.ru')) {
    $hit = & $SingBox rule-set match -f binary $Output $d 2>&1 | Select-String 'match rules'
    if (-not $hit) { throw "compiled rule-set does NOT match the ad host $d" }
}
Write-Host "Verified: blocks ads, spares normal sites"
Write-Host "Wrote $Output ($([math]::Round((Get-Item $Output).Length / 1KB, 0)) KB, $($suffix.Count) domains)"
Remove-Item $work -Recurse -Force
