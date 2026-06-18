# Minimal static file server for local testing (no Python/Node required).
# Usage:  .\serve_local.ps1            (serves current folder at http://localhost:8123)
param([int]$Port = 8123)

$root = (Resolve-Path $PSScriptRoot).Path
$mime = @{
    ".html" = "text/html; charset=utf-8"
    ".js"   = "text/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".wav"  = "audio/wav"
    ".png"  = "image/png"
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $root at http://localhost:$Port/  (Ctrl+C to stop)"

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $rel = [uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if (-not $rel) { $rel = "index.html" }
    $path = Join-Path $root $rel
    try {
        if ((Test-Path $path -PathType Leaf) -and ((Resolve-Path $path).Path.StartsWith($root))) {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $ext = [System.IO.Path]::GetExtension($path).ToLower()
            $ctx.Response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $ctx.Response.StatusCode = 404
        }
    } catch {
        $ctx.Response.StatusCode = 500
    } finally {
        $ctx.Response.OutputStream.Close()
    }
}
