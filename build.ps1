# 自用构建脚本：带弹弹play 凭证编译
# 用法：右键 → 使用 PowerShell 运行，或在 pwsh 里执行 .\build.ps1
#
# 凭证放在 local\credentials.json（该目录已在 .gitignore 里，不会进版本库）：
# {
#   "DANDANAPI_APPID": "你的AppId",
#   "DANDANAPI_KEY": "你的AppSecret"
# }

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cred = Join-Path $root 'local\credentials.json'
$dest = 'F:\Tools\Kazumi-SelfBuild'

$buildArgs = @('build', 'windows', '--release')
if (Test-Path $cred) {
    $buildArgs += "--dart-define-from-file=$cred"
    Write-Host '[1/4] 已找到 local\credentials.json，弹幕凭证会在编译时注入' -ForegroundColor Green
} else {
    Write-Host '[1/4] 警告：没有 local\credentials.json，编译出来的版本弹幕不可用' -ForegroundColor Yellow
}

$env:Path = 'F:\environments\Flutter\bin;F:\Tools\nuget;' + $env:Path

Write-Host '[2/4] 编译中...' -ForegroundColor Cyan
Push-Location $root
try {
    & 'F:\environments\Flutter\bin\flutter.bat' @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build 失败，退出码 $LASTEXITCODE" }
} finally {
    Pop-Location
}

Write-Host '[3/4] 关闭正在运行的自编版...' -ForegroundColor Cyan
Get-Process -Name kazumi -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like '*Kazumi-SelfBuild*' } |
    Stop-Process -Force
Start-Sleep -Seconds 3

Write-Host '[4/4] 复制产物到 ' -NoNewline -ForegroundColor Cyan
Write-Host $dest -ForegroundColor Cyan
Copy-Item "$root\build\windows\x64\runner\Release\*" $dest -Recurse -Force

Write-Host '完成。双击启动：' -NoNewline -ForegroundColor Green
Write-Host "$dest\kazumi.exe" -ForegroundColor Green