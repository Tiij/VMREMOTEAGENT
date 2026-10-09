param(
    [ValidateSet('start','deploy','status','stop','remove')][string]$Action = 'status',
    [switch]$ReuseImage
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$linuxRoot = & wsl -d Ubuntu -- wslpath -u $projectRoot.Replace('\', '/')
if ($LASTEXITCODE -ne 0 -or -not $linuxRoot) { throw 'WSL Ubuntu inaccessible.' }
$linuxRoot = $linuxRoot.Trim()
$reuse = if ($ReuseImage) { '1' } else { '0' }
& wsl -d Ubuntu -u root -- env "REUSE_IMAGE=$reuse" bash "$linuxRoot/scripts/vm-test.sh" $Action
if ($LASTEXITCODE -ne 0) { throw "VM : action $Action échouée." }
