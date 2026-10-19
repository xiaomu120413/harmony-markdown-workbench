$ErrorActionPreference = 'Stop'
# Source vectors and generated layers belong to this repository.
python (Join-Path $PSScriptRoot 'gen-icons.py')
if ($LASTEXITCODE -ne 0) { throw 'Icon rendering failed; install CairoSVG for this Python runtime.' }
