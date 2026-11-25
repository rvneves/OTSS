<#
    OTSS (Over Troubleshooting Script) - coleta offline de diagnostico com o TSS da Microsoft.
    Detecta o papel da maquina (no de cluster, host Hyper-V ou outro), roda o SDP adequado do TSS
    e entrega uma pasta + um zip em C:\temp\OTSS. Normalmente chamado pelo OTSS.exe.

    Codigos de saida: 0 concluido | 1 concluido com avisos (zip gerado) | 2 falha (sem zip; ver OTSS.log)
#>
[CmdletBinding()]
param(
    [string]$TssZip,
    [string]$ExeDir,
    [string]$OutputRoot = 'C:\temp\OTSS',
    [string]$WorkDir,
    [string]$OtssVersion = 'dev',
    [string]$TssVersion = '?',
    [string]$MinidumpPath = 'C:\Windows\Minidump',
    [string]$MemoryDumpPath = 'C:\Windows\MEMORY.DMP',
    [string]$WindowsDir = $env:SystemRoot,
    [switch]$Silencioso,
    [switch]$SemPergunta
)

if (-not (Get-Module OTSS.Core)) { Import-Module (Join-Path $PSScriptRoot 'OTSS.Core.psm1') }
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Finalizar([int]$Codigo) {
    if (-not $Silencioso) { [void](Read-Host 'Pressione Enter para fechar') }
    exit $Codigo
}

Write-Host ''
$tssTxt = if ($TssVersion -ne '?') { "TSS $TssVersion" } else { 'TSS da Microsoft obtido na execucao' }
Write-Host "OTSS v$OtssVersion  -  coleta de diagnostico ($tssTxt)" -ForegroundColor Cyan
Write-Host "Maquina: $env:COMPUTERNAME"

# 1. Administrador
if (-not (Test-OTSSAdmin)) {
    Write-Host 'ERRO: execute como administrador (botao direito > Executar como administrador).' -ForegroundColor Red
    Finalizar 2
}

# 2. Pasta de saida e espaco livre
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
if (-not (Test-OTSSFreeSpace -Drive 'C' -MinGB 5)) {
    $livre = [math]::Round((Get-OTSSFreeBytes -Drive 'C') / 1GB, 1)
    Write-Host "ERRO: espaco livre insuficiente em C: ($livre GB). Sao necessarios pelo menos 5 GB." -ForegroundColor Red
    Finalizar 2
}

# 3. Deteccao
$role = Get-OTSSRole
switch ($role.Tipo) {
    'Cluster' {
        $desc = "no do cluster $($role.Cluster) ($($role.Nos) nos)"
        if ($role.HyperV) { $desc += ' com Hyper-V  -> coleta Cluster + Hyper-V' } else { $desc += '  -> coleta Cluster' }
    }
    'HyperV' { $desc = 'host Hyper-V (fora de cluster)  -> coleta Hyper-V (SDP Cluster do TSS)' }
    default  { $desc = 'nao e Hyper-V  -> coleta padrao (Setup)' }
}
Write-Host "Detectado: $desc" -ForegroundColor Green

# 4. Pasta da execucao e log
$nome = Get-OTSSRunName -Computer $env:COMPUTERNAME -Tipo $role.Tipo -Now (Get-Date) -Root $OutputRoot
$pasta = Join-Path $OutputRoot $nome
$zipFinal = "$pasta.zip"
New-Item -ItemType Directory -Path $pasta -Force | Out-Null
$log = Join-Path $pasta 'OTSS.log'
Write-OTSSLog $log "OTSS v$OtssVersion | TSS $TssVersion | maquina $env:COMPUTERNAME | usuario $env:USERDOMAIN\$env:USERNAME"
Write-OTSSLog $log "Detectado: $desc"
foreach ($m in $role.Motivo) { Write-OTSSLog $log "  motivo: $m" }
$regLog = Get-OTSSTssRegLogFolder
if ($regLog) {
    Write-OTSSLog $log "  AVISO: o registro do TSS aponta LogFolder=$regLog (execucao anterior do TSS interrompida). O TSS pode gravar la em vez desta pasta."
}

$criouWorkDir = $false
$codigo = 2
$inicio = Get-Date
try {
    if (-not $WorkDir) {
        $WorkDir = Join-Path $OutputRoot ('_tss_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
        $criouWorkDir = $true
    }

    # 5. Extrair o TSS
    Write-OTSSLog $log '[1/4] Preparando (extraindo o TSS)...'
    $tss = Resolve-OTSSTssZip -TssZip $TssZip -ExeDir $ExeDir -WorkDir $WorkDir -SemPergunta:$SemPergunta
    Write-OTSSLog $log "  TSS: $($tss.Origem) ($($tss.Path))"
    $tssDir = Join-Path $WorkDir 'tss'
    [IO.Compression.ZipFile]::ExtractToDirectory($tss.Path, $tssDir)
    $tssPs1 = Join-Path $tssDir 'TSS.ps1'
    if (-not (Test-Path -LiteralPath $tssPs1)) {
        $achado = Get-ChildItem -LiteralPath $tssDir -Filter 'TSS.ps1' -Recurse -File | Select-Object -First 1
        if (-not $achado) { throw 'TSS.ps1 nao encontrado no pacote do TSS.' }
        $tssPs1 = $achado.FullName
    }
    if ($TssVersion -eq '?') { $TssVersion = Get-OTSSTssVersionFromScript -Path $tssPs1 }
    $idade = Get-OTSSTssAge -TssVersion $TssVersion -Now (Get-Date)
    if ($idade -ge 0) {
        Write-OTSSLog $log ("  TSS de {0} ({1} dias)" -f $TssVersion.Substring(0, 10).Replace('.', '-'), $idade)
        if ($idade -gt 180) { Write-OTSSLog $log '  AVISO: o TSS tem mais de 6 meses; baixe um novo em https://aka.ms/getTSS (ou remonte o OTSS).' }
    }

    # 6. Rodar o TSS
    Write-OTSSLog $log '[2/4] Coletando (pode levar de 10 a 30 minutos)...'
    $cmd = Get-OTSSTssCommand -Role $role -TssPath $tssPs1 -LogFolderPath $pasta
    Write-OTSSLog $log "  comando: $cmd"
    $consoleLog = Join-Path $pasta 'tss-console.log'
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "$cmd; exit `$LASTEXITCODE" 2>&1 |
        Tee-Object -FilePath $consoleLog
    $tssExit = $LASTEXITCODE
    if ($null -eq $tssExit) { $tssExit = 0 }
    $erros = Get-OTSSTssErrorCount -Folder $pasta
    Write-OTSSLog $log "  TSS terminou com codigo $tssExit; linhas com ERROR (Warn-Err-Info + console): $erros"

    # 7. Dumps
    $md = Copy-OTSSMinidumps -Source $MinidumpPath -Destination (Join-Path $pasta 'Minidump') -Days 30 -Now (Get-Date)
    Write-OTSSLog $log "  minidumps copiados (ultimos 30 dias): $md"
    Write-OTSSLog $log "  $(Get-OTSSMemoryDumpInfo -Path $MemoryDumpPath)"

    # Logs de instalacao do Windows (CBS, DISM, SCCM) e estado de reinicio pendente
    $pend = @(Get-OTSSPendingReboot -WindowsDir $WindowsDir)
    if ($pend.Count -gt 0) { Write-OTSSLog $log "  AVISO: reinicio pendente: $($pend -join ', ')" }
    else { Write-OTSSLog $log '  reinicio pendente: nenhum' }
    $srv = Join-Path $pasta 'Servicing'
    $sl = Copy-OTSSServicingLogs -WindowsDir $WindowsDir -Destination $srv -Days 30 -MaxMB 2048
    Write-OTSSLog $log ("  logs de instalacao copiados: {0} ({1} MB); em uso nao copiados: {2}; acima do limite de 2 GB: {3}" -f $sl.Copiados, $sl.MB, $sl.Pulados, $sl.ForaDoLimite)
    if (Export-OTSSEventLog -LogName 'Setup' -Destination (Join-Path $srv 'Setup.evtx')) { Write-OTSSLog $log '  log de eventos Setup exportado' }
    else { Write-OTSSLog $log '  AVISO: nao foi possivel exportar o log de eventos Setup' }
    $cbs = Get-OTSSCbsSummary -Folder (Join-Path $srv 'CBS')
    if ($cbs.Corrupcao -or $cbs.SessaoInterrompida) { Write-OTSSLog $log "  AVISO: CBS: $($cbs.Texto)" }
    else { Write-OTSSLog $log "  CBS: $($cbs.Texto)" }

    # 8. Zip
    $saida = Test-OTSSSdpOutput -Folder $pasta
    $zipOk = $false
    $pulados = @()
    if ($saida) {
        Write-OTSSLog $log ("  duracao da coleta: {0:N0} min" -f ((Get-Date) - $inicio).TotalMinutes)
        # O TSS devolve o controle com o msinfo32 ainda gravando (visto em campo: +7 min).
        [void](Wait-OTSSBlockingProcess -Folder $pasta -Since $inicio -TimeoutSec 1200 -PollSec 10 -LogPath $log)

        # Guia para a IA que vai ler a coleta (gerado com a lista final de arquivos, antes do zip)
        $fatos = [ordered]@{
            'Data da coleta'          = $inicio.ToString('yyyy-MM-dd HH:mm')
            'Duracao'                 = ('{0:N0} min' -f ((Get-Date) - $inicio).TotalMinutes)
            'Reinicio pendente'       = $(if ($pend.Count) { $pend -join ', ' } else { 'nenhum' })
            'MEMORY.DMP'              = (Get-OTSSMemoryDumpInfo -Path $MemoryDumpPath)
            'Minidumps (30 dias)'     = $md
            'Logs de instalacao'      = ('{0} arquivos em Servicing/ ({1} MB)' -f $sl.Copiados, $sl.MB)
            'Resumo do CBS'           = $cbs.Texto
            'Linhas ERROR do TSS'     = "$erros (a maioria costuma ser de comandos auxiliares; ver secao 4)"
        }
        if ($regLog) { $fatos['AVISO LogFolder do TSS'] = $regLog }
        try {
            [void](New-OTSSAiGuide -Folder $pasta -Computer $env:COMPUTERNAME -Role $role -OtssVersion $OtssVersion -TssVersion $TssVersion -Facts $fatos)
            Write-OTSSLog $log '  guia para IA gerado: LEIA-PRIMEIRO_IA.md'
        } catch {
            Write-OTSSLog $log "  AVISO: nao foi possivel gerar o guia para IA: $($_.Exception.Message)"
        }

        Write-OTSSLog $log '[3/4] Compactando...'
        $pulados = @(New-OTSSZip -Source $pasta -Destination $zipFinal)
        foreach ($p in $pulados) { Write-OTSSLog $log "  AVISO: arquivo em uso, ficou fora do zip (esta na pasta): $p" }
        $zipOk = Test-Path -LiteralPath $zipFinal
    } else {
        Write-OTSSLog $log 'ERRO: o TSS nao coletou dados (a pasta SDP_* so tem logs do proprio TSS ou nao existe). Veja tss-console.log.'
        if ($regLog) { Write-OTSSLog $log "  Confira tambem $regLog (LogFolder do registro do TSS)." }
    }
    $codigo = Get-OTSSExitCode -OutputExists $saida -TssExitCode $tssExit -TssErrorLines $erros -ZipCreated $zipOk -ZipSkipped $pulados.Count
} catch {
    Write-OTSSLog $log "ERRO: $($_.Exception.Message)"
    $codigo = 2
    # zip parcial (falha no meio da compactacao): nao deixar arquivo corrompido com cara de coleta valida
    if ($zipFinal -and (Test-Path -LiteralPath $zipFinal)) { Remove-Item -LiteralPath $zipFinal -Force -ErrorAction SilentlyContinue }
} finally {
    if ($criouWorkDir -and $WorkDir -and (Test-Path -LiteralPath $WorkDir)) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 9. Resultado
Write-Host ''
switch ($codigo) {
    0 { Write-OTSSLog $log '[4/4] Concluido.' }
    1 { Write-OTSSLog $log '[4/4] Concluido com avisos (o TSS registrou erros; o zip foi gerado).' }
    default { Write-OTSSLog $log '[4/4] FALHOU. Veja o OTSS.log na pasta abaixo.' }
}
Write-Host "Pasta: $pasta"
if ($codigo -ne 2) {
    Write-Host "Zip:   $zipFinal" -ForegroundColor Green
    Write-Host 'Para analisar com IA: entregue o zip e peca para comecar pelo arquivo LEIA-PRIMEIRO_IA.md.' -ForegroundColor Cyan
}
Finalizar $codigo
