# TSS falso para os testes do OTSS: aceita os mesmos parametros usados pelo OTSS.
param(
    [string[]]$SDP,
    [string[]]$SkipSDPList,
    [string]$LogFolderPath,
    [switch]$AcceptEula, [switch]$noXray, [switch]$noUpdate, [switch]$noAsk, [switch]$noZip, [switch]$noExpire, [int]$EvtDaysBack
)
Write-Output "FakeTSS SDP=$($SDP -join ',') Skip=$($SkipSDPList -join ',')"
# Como o TSS real: cria a pasta e o transcript antes de validar o SDP
$pasta = Join-Path $LogFolderPath ('SDP_' + [string]::Concat($SDP))
New-Item -ItemType Directory -Path $pasta -Force | Out-Null
'transcript' | Set-Content (Join-Path $pasta 'FAKE_Log-transcript.txt')
foreach ($s in $SDP) { if ($s -in 'HyperV', 'S2D') { Write-Output "WARNING: SDP $s is deprecated"; exit } }
if ($env:FAKE_TSS_ERRO) { 'ERROR: falha simulada' | Set-Content (Join-Path $pasta 'FAKE_Log-Warn-Err-Info.txt') }
if (-not $env:FAKE_TSS_VAZIO) {
    "SDP=$($SDP -join ',') Skip=$($SkipSDPList -join ',') Eula=$AcceptEula Xray=$noXray Upd=$noUpdate Ask=$noAsk Zip=$noZip Exp=$noExpire Evt=$EvtDaysBack" |
        Set-Content (Join-Path $pasta 'args.txt')
}
$code = 0
if ($env:FAKE_TSS_EXIT) { $code = [int]$env:FAKE_TSS_EXIT }
exit $code
