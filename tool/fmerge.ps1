# Git for Windows 可以通过此脚本或直接调用 fmerge.exe。
$FmergeBinary = if ($env:FMERGE_BINARY) { $env:FMERGE_BINARY } else {
    Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\fmerge.exe'
}
& $FmergeBinary @args
exit $LASTEXITCODE
