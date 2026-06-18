# Select a diverse subset of evaluation items for a pilot/human study.
#
# Keeps only items whose source audio is <= MaxDuration seconds, then picks N
# items biased toward annotator-friendly task types:
#   - AvoidTypes : sub-categories dropped entirely (hard for laypeople to judge,
#                  e.g. Phonemic Stress Pattern Analysis).
#   - PreferTypes: sub-categories filled first (round-robin among them) up to
#                  PreferQuota slots, so intuitive types get more examples.
#   - the remaining slots are filled by round-robin across the other
#                  (dataset | category | sub-category | difficulty) groups for
#                  diversity. All selection is seeded for reproducibility.
#
# Writes items_subset.json (and, with -CopyAudio, audio_subset/ holding only the
# referenced wavs). eval.html reads the filename from config.js (ITEMS_FILE).
#
# Usage:
#   .\select_subset.ps1                       # 10 items, <=15s, seed 42, defaults below
#   .\select_subset.ps1 -PreferQuota 6 -Seed 7
param(
    [int]$N = 10,
    [double]$MaxDuration = 15,
    [int]$Seed = 42,
    [string[]]$AvoidTypes = @("Phonemic Stress Pattern Analysis"),
    [string[]]$PreferTypes = @("Key highlight Extraction", "Multi Speaker Role Mapping"),
    [int]$PreferQuota = 5,
    [string]$Source = "..\qwen2.5_TS+GRPO_exp4_t2_mmau-test-mini_speech_highIoU.json",
    [switch]$CopyAudio
)

$ErrorActionPreference = "Stop"
$base = (Resolve-Path $PSScriptRoot).Path
if (-not $base) { $base = (Get-Location).Path }

function Get-WavDuration($path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    $sr = [BitConverter]::ToUInt32($b, 24); $ch = [BitConverter]::ToUInt16($b, 22); $bits = [BitConverter]::ToUInt16($b, 34)
    $i = 12
    while ($i -lt $b.Length - 8) {
        $cid = [System.Text.Encoding]::ASCII.GetString($b[$i..($i + 3)])
        $csz = [BitConverter]::ToUInt32($b, $i + 4)
        if ($cid -eq 'data') { return [math]::Round($csz / ($sr * $ch * ($bits / 8)), 2) }
        $i += 8 + $csz + ($csz % 2)
    }
    return -1
}

# diversity metadata keyed by source id
$meta = @{}
foreach ($r in (Get-Content $Source -Raw -Encoding UTF8 | ConvertFrom-Json)) { $meta[$r.id] = $r }

$items = Get-Content (Join-Path $base "items.json") -Raw -Encoding UTF8 | ConvertFrom-Json

function Matches-Any($text, $patterns) {
    foreach ($p in $patterns) { if ($text -and $text.ToLower().Contains($p.ToLower())) { return $true } }
    return $false
}

# filter by duration and AvoidTypes
$eligible = foreach ($it in $items) {
    $dur = Get-WavDuration (Join-Path $base $it.audio_path)
    if ($dur -gt 0 -and $dur -le $MaxDuration) {
        $m = $meta[$it.source_id]
        if (Matches-Any $m.'sub-category' $AvoidTypes) { continue }
        [PSCustomObject]@{
            item = $it; dur = $dur; sub = $m.'sub-category'
            type = "$($m.dataset) | $($m.category) | $($m.'sub-category') | $($m.difficulty)"
            prefer = (Matches-Any $m.'sub-category' $PreferTypes)
        }
    }
}
Write-Host "eligible (<= $MaxDuration s, avoiding [$($AvoidTypes -join ', ')]): $($eligible.Count) / $($items.Count)"
if ($eligible.Count -lt $N) { throw "Only $($eligible.Count) eligible items; cannot pick $N." }

$rng = New-Object System.Random($Seed)
function Shuffle($arr) {
    $a = @($arr)
    for ($i = $a.Count - 1; $i -gt 0; $i--) { $j = $rng.Next($i + 1); $t = $a[$i]; $a[$i] = $a[$j]; $a[$j] = $t }
    return $a
}

$picked = [System.Collections.ArrayList]@()
$takenIds = [System.Collections.Generic.HashSet[string]]::new()

# Round-robin helper over a set of groups (group key -> shuffled queue), taking
# one item per distinct group per pass until $limit items are added.
function FillRoundRobin($rows, $limit) {
    $groups = $rows | Where-Object { -not $takenIds.Contains($_.item.item_id) } | Group-Object type
    $queues = @{}; foreach ($g in $groups) { $queues[$g.Name] = [System.Collections.ArrayList]@(Shuffle $g.Group) }
    $order = Shuffle ($groups.Name)
    while ($picked.Count -lt $limit) {
        $tookOne = $false
        foreach ($t in $order) {
            if ($queues[$t].Count -gt 0) {
                $cand = $queues[$t][0]; $queues[$t].RemoveAt(0)
                [void]$picked.Add($cand); [void]$takenIds.Add($cand.item.item_id); $tookOne = $true
                if ($picked.Count -ge $limit) { break }
            }
        }
        if (-not $tookOne) { break }
    }
}

# Phase 1: fill preferred types first (up to PreferQuota slots).
FillRoundRobin ($eligible | Where-Object prefer) ([math]::Min($PreferQuota, $N))
# Phase 2: fill the remaining slots with diversity across all other types.
FillRoundRobin $eligible $N

$picked = Shuffle $picked  # randomize presentation order
$out = $picked | ForEach-Object { $_.item }

# With -CopyAudio, copy only the referenced wavs into audio_subset/ and rewrite
# the manifest paths to point there, so the deployment carries 10 wavs not 66.
if ($CopyAudio) {
    $audioOut = Join-Path $base "audio_subset"
    New-Item -ItemType Directory -Force $audioOut | Out-Null
    foreach ($it in $out) {
        $name = Split-Path $it.audio_path -Leaf
        Copy-Item (Join-Path $base $it.audio_path) (Join-Path $audioOut $name) -Force
        $it.audio_path = "audio_subset/$name"
    }
    Write-Host "copied $($out.Count) wavs -> audio_subset/ (manifest paths rewritten)"
}

$json = ConvertTo-Json -InputObject @($out) -Depth 6
[System.IO.File]::WriteAllText((Join-Path $base "items_subset.json"), $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "selected $($out.Count) items -> items_subset.json"
$picked | ForEach-Object { "{0,5:N2}s  {1}  [{2}]" -f $_.dur, $_.item.item_id, $_.type } | Sort-Object
