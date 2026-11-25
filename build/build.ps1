<#
    Monta o OTSS.exe: baixa o TSS (ou usa -TssZipPath), compila o iniciador C# com o csc.exe do
    .NET Framework e embute TSS.zip, Invoke-OTSS.ps1, OTSS.Core.psm1 e TSSVersion.txt.
    Saida: <OutDir>\OTSS.exe e <OutDir>\OTSS.exe.sha256

    Exemplo: powershell -ExecutionPolicy Bypass -File build\build.ps1
#>
[CmdletBinding()]
param(
    [string]$TssZipPath,
    [string]$Version = '1.0.0',
    [string]$OutDir,
    [string]$CertThumbprint,
    [string]$IconPath
)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
if (-not $IconPath) { $IconPath = Join-Path $raiz 'assets\otss.ico' }
if (-not $OutDir) { $OutDir = Join-Path $raiz 'dist' }
$cache = Join-Path $PSScriptRoot 'cache'
New-Item -ItemType Directory -Path $cache, $OutDir -Force | Out-Null

# 1. TSS
if (-not $TssZipPath) {
    $TssZipPath = Join-Path $cache 'TSS.zip'
    Write-Host 'Baixando o TSS de https://aka.ms/getTSS ...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    (New-Object Net.WebClient).DownloadFile('https://aka.ms/getTSS', $TssZipPath)
}
$TssZipPath = (Resolve-Path $TssZipPath).Path

# 2. Versao do TSS (linha $global:TssVerDate = "..." do TSS.ps1 dentro do zip)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::OpenRead($TssZipPath)
try {
    $entrada = $z.Entries | Where-Object { $_.Name -eq 'TSS.ps1' } | Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if (-not $entrada) { throw "TSS.ps1 nao encontrado em $TssZipPath" }
    $leitor = New-Object IO.StreamReader($entrada.Open())
    $texto = $leitor.ReadToEnd(); $leitor.Close()
} finally { $z.Dispose() }
$m = [regex]::Match($texto, '\$global:TssVerDate\s*=\s*"([^"]+)"')
$tssVersion = if ($m.Success) { $m.Groups[1].Value } else { 'desconhecida' }
$verFile = Join-Path $cache 'TSSVersion.txt'
[IO.File]::WriteAllText($verFile, $tssVersion)
Write-Host "TSS versao $tssVersion"

# 3. AssemblyInfo com a versao do OTSS
$info = Join-Path $cache 'AssemblyInfo.cs'
@"
using System.Reflection;
[assembly: AssemblyTitle("OTSS - Over Troubleshooting Script")]
[assembly: AssemblyProduct("OTSS")]
[assembly: AssemblyVersion("$Version.0")]
[assembly: AssemblyFileVersion("$Version.0")]
[assembly: AssemblyInformationalVersion("$Version (TSS $tssVersion)")]
"@ | Set-Content -Path $info -Encoding UTF8

# 4. Compilar
$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
$exe = Join-Path $OutDir 'OTSS.exe'
$cscArgs = @(
    '/nologo', '/target:exe', '/platform:anycpu', '/optimize+',
    "/out:$exe",
    "/win32manifest:$(Join-Path $raiz 'launcher\app.manifest')",
    "/win32icon:$IconPath",
    "/resource:$TssZipPath,TSS.zip",
    "/resource:$(Join-Path $raiz 'src\Invoke-OTSS.ps1'),Invoke-OTSS.ps1",
    "/resource:$(Join-Path $raiz 'src\OTSS.Core.psm1'),OTSS.Core.psm1",
    "/resource:$verFile,TSSVersion.txt",
    (Join-Path $raiz 'launcher\OTSS.cs'), $info
)
& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw "csc.exe falhou com codigo $LASTEXITCODE" }

# 5. Assinatura opcional
if ($CertThumbprint) {
    $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object Thumbprint -eq $CertThumbprint
    if (-not $cert) { throw "Certificado $CertThumbprint nao encontrado em Cert:\CurrentUser\My" }
    Set-AuthenticodeSignature -FilePath $exe -Certificate $cert -TimestampServer 'http://timestamp.digicert.com' | Out-Null
}

# 6. Hash
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText("$exe.sha256", "$hash  OTSS.exe" + [Environment]::NewLine)
$mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Host "OK: $exe ($mb MB)  sha256 $hash"
