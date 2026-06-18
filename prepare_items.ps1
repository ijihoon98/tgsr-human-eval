# PowerShell port of prepare_items.py (for machines without Python).
# Builds items.json and copies referenced audio into audio/.
param(
    [string]$InputJson = "..\qwen2.5_TS+GRPO_exp4_t2_mmau-test-mini_speech_highIoU.json",
    [string]$AudioDir  = "..\test-mini-audios",
    [string]$OutDir    = ".",
    [switch]$AllSteps,
    [int]$Seed = 42
)

$ErrorActionPreference = "Stop"
$rng = New-Object System.Random($Seed)
$tsPattern = [regex]'(?i)from\s+(\d+(?:\.\d+)?)\s*(?:s|secs?|seconds?)?\s+to\s+(\d+(?:\.\d+)?)\s*(?:s|secs?|seconds?)?'

$records = Get-Content $InputJson -Raw -Encoding UTF8 | ConvertFrom-Json
$audioOut = Join-Path $OutDir "audio"
New-Item -ItemType Directory -Force $audioOut | Out-Null

$items = New-Object System.Collections.ArrayList
$skipped = @()

foreach ($rec in $records) {
    # extract timestamped steps
    $steps = @()
    foreach ($line in ($rec.model_prediction -split "`n")) {
        $line = $line.Trim()
        if (-not $line) { continue }
        if ($line.ToLower().StartsWith("final answer")) { continue }
        $regions = @()
        foreach ($m in $tsPattern.Matches($line)) {
            $s = [double]$m.Groups[1].Value; $e = [double]$m.Groups[2].Value
            if ($e -gt $s) { $regions += ,@([math]::Round($s,2), [math]::Round($e,2)) }
        }
        if ($regions.Count -gt 0) {
            $steps += ,@{ text = $line; regions = $regions }
        }
    }
    if ($steps.Count -eq 0) { $skipped += $rec.id; continue }

    $audioName = Split-Path $rec.audio_id -Leaf
    $src = Join-Path $AudioDir $audioName
    if (-not (Test-Path $src)) { $skipped += $rec.id; continue }
    $dst = Join-Path $audioOut $audioName
    if (-not (Test-Path $dst)) { Copy-Item $src $dst }

    if ($AllSteps) { $chosen = 0..($steps.Count - 1) }
    else { $chosen = @($rng.Next($steps.Count)) }

    foreach ($idx in $chosen) {
        $st = $steps[$idx]
        [void]$items.Add([ordered]@{
            item_id        = "$($rec.id.Substring(0,8))_s$idx"
            source_id      = $rec.id
            audio_path     = "audio/$audioName"
            reasoning_step = $st.text
            regions        = $st.regions
            question       = $rec.question
            choices        = $rec.choices
            model_output   = $rec.model_output
            avg_iou        = $rec.avg_iou
        })
    }
}

# Fisher-Yates shuffle (seeded)
for ($i = $items.Count - 1; $i -gt 0; $i--) {
    $j = $rng.Next($i + 1)
    $tmp = $items[$i]; $items[$i] = $items[$j]; $items[$j] = $tmp
}

$json = ConvertTo-Json -InputObject $items -Depth 6
$outPath = Join-Path $OutDir "items.json"
[System.IO.File]::WriteAllText((Resolve-Path $OutDir).Path + "\items.json", $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "items written : $($items.Count) -> $outPath"
Write-Host "audio copied  : $((Get-ChildItem $audioOut).Count) files -> $audioOut"
if ($skipped.Count -gt 0) {
    Write-Host "skipped: $($skipped.Count)"
    $skipped | ForEach-Object { Write-Host "  - $_" }
}
