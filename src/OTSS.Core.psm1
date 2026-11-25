# OTSS.Core - funcoes do OTSS (coleta offline do TSS). Sondas do sistema isoladas para os testes.

#region Sondas
function Test-OTSSServiceRunning {
    param([Parameter(Mandatory)][string]$Name)
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
    return [bool]($s -and $s.Status -eq 'Running')
}

function Test-OTSSServiceExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Service -Name $Name -ErrorAction SilentlyContinue)
}

function Get-OTSSClusterInfo {
    try {
        $c = Get-Cluster -ErrorAction Stop
        $n = @(Get-ClusterNode -ErrorAction Stop).Count
        return [pscustomobject]@{ Name = [string]$c.Name; NodeCount = [int]$n }
    } catch {
        return $null
    }
}

function Test-OTSSS2D {
    try {
        $s = Get-ClusterStorageSpacesDirect -ErrorAction Stop
        return [bool]($s -and "$($s.State)" -eq 'Enabled')
    } catch {
        return $false
    }
}

function Get-OTSSFreeBytes {
    param([Parameter(Mandatory)][string]$Drive)
    return [long](Get-PSDrive -Name $Drive.TrimEnd(':') -PSProvider FileSystem -ErrorAction Stop).Free
}

function Get-OTSSTssRegLogFolder {
    # Execucao anterior do TSS interrompida (-Start/-StartAutoLogger) deixa este valor, e o TSS passa a gravar nele.
    $v = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\CESDiagnosticTools\TSS\Parameters' -Name LogFolder -ErrorAction SilentlyContinue
    if ($v -and $v.LogFolder) { return [string]$v.LogFolder }
    return $null
}

function Test-OTSSRegistryPath {
    param([Parameter(Mandatory)][string]$Path)
    return [bool](Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)
}

function Get-OTSSPendingFileRename {
    $v = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    return [bool]($v -and $v.PendingFileRenameOperations)
}

function Export-OTSSEventLog {
    # Exporta um log de eventos inteiro (.evtx) com o wevtutil. $true se gerou o arquivo.
    param([Parameter(Mandatory)][string]$LogName, [Parameter(Mandatory)][string]$Destination)
    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
    & "$env:SystemRoot\System32\wevtutil.exe" epl $LogName $Destination /ow:true 2>$null | Out-Null
    return (Test-Path -LiteralPath $Destination)
}

function Test-OTSSAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
#endregion

function Get-OTSSRole {
    $motivo = New-Object System.Collections.Generic.List[string]
    $hyperV = Test-OTSSServiceExists -Name 'vmms'

    if (Test-OTSSServiceRunning -Name 'ClusSvc') {
        $info = Get-OTSSClusterInfo
        if ($info) {
            $s2d = Test-OTSSS2D
            $motivo.Add("Servico ClusSvc em execucao; Get-Cluster respondeu: $($info.Name) ($($info.NodeCount) nos).")
            if (-not $s2d) { $motivo.Add('S2D nao habilitado ou nao consultavel: SDDC sera pulado.') }
            return [pscustomobject]@{ Tipo = 'Cluster'; Cluster = $info.Name; Nos = $info.NodeCount
                HyperV = $hyperV; S2D = $s2d; Motivo = $motivo.ToArray() }
        }
        $motivo.Add('Servico ClusSvc em execucao, mas Get-Cluster nao respondeu (modulo ausente ou no fora do cluster).')
    } else {
        $motivo.Add('Servico ClusSvc ausente ou parado: nao e no de cluster.')
    }

    if ($hyperV) {
        $motivo.Add('Servico vmms presente: host Hyper-V.')
        return [pscustomobject]@{ Tipo = 'HyperV'; Cluster = $null; Nos = $null; HyperV = $true; S2D = $false; Motivo = $motivo.ToArray() }
    }
    $motivo.Add('Servico vmms ausente: nao e host Hyper-V; coleta padrao (Setup).')
    return [pscustomobject]@{ Tipo = 'Setup'; Cluster = $null; Nos = $null; HyperV = $false; S2D = $false; Motivo = $motivo.ToArray() }
}

function Get-OTSSRunName {
    param(
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][string]$Tipo,
        [Parameter(Mandatory)][datetime]$Now,
        [Parameter(Mandatory)][string]$Root
    )
    $base = '{0}_{1}_{2}' -f $Computer, $Now.ToString('yyyyMMdd_HHmmss'), $Tipo
    $nome = $base; $i = 1
    while ((Test-Path -LiteralPath (Join-Path $Root $nome)) -or (Test-Path -LiteralPath (Join-Path $Root "$nome.zip"))) {
        $i++; $nome = "${base}_$i"
    }
    return $nome
}

function Get-OTSSTssCommand {
    param(
        [Parameter(Mandatory)][pscustomobject]$Role,
        [Parameter(Mandatory)][string]$TssPath,
        [Parameter(Mandatory)][string]$LogFolderPath
    )
    # No TSS 2026.11, os SDP 'HyperV' e 'S2D' sao obsoletos e abortam a coleta ("Please use -SDP Cluster").
    # O SDP Cluster ja inclui as funcoes de Hyper-V; o SDDC (S2D) entra so quando S2D esta habilitado.
    $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
    switch ($Role.Tipo) {
        'Cluster' { $sdp = 'Cluster'; $skip = if ($Role.S2D) { 'skipBPA' } else { 'skipBPA,skipSddc' } }
        'HyperV'  { $sdp = 'Cluster'; $skip = 'skipBPA,skipSddc' }
        default   { $sdp = 'Setup';   $skip = 'skipBPA' }
    }
    # -noExpire: o TSS se recusa a rodar 90 dias depois da versao dele; o OTSS embute uma versao fixa.
    # -EvtDaysBack 30: converte para texto/CSV so os ultimos 30 dias de eventos (os .evtx seguem completos);
    #   em nos de cluster com centenas de milhares de eventos, isso encurta muito a coleta e a carga de CPU.
    return "& $(& $q $TssPath) -SDP $sdp -SkipSDPList $skip -LogFolderPath $(& $q $LogFolderPath) -AcceptEula -noXray -noUpdate -noAsk -noZip -noExpire -EvtDaysBack 30"
}

function Get-OTSSExitCode {
    param(
        [Parameter(Mandatory)][bool]$OutputExists,
        [Parameter(Mandatory)][int]$TssExitCode,
        [Parameter(Mandatory)][int]$TssErrorLines,
        [Parameter(Mandatory)][bool]$ZipCreated,
        [int]$ZipSkipped = 0
    )
    if (-not $OutputExists -or -not $ZipCreated) { return 2 }
    if ($TssExitCode -ne 0 -or $TssErrorLines -gt 0 -or $ZipSkipped -gt 0) { return 1 }
    return 0
}

function Get-OTSSBlockingProcess {
    # Processos que o TSS deixa rodando depois de devolver o controle (ex.: msinfo32 /nfo gravando na pasta
    # da coleta) ou cuja linha de comando cita a pasta da coleta. Retorna 'nome (PID)'.
    param([Parameter(Mandatory)][string]$Folder, [Parameter(Mandatory)][datetime]$Since)
    $lista = @()
    $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    foreach ($p in $procs) {
        if ($p.ProcessId -eq $PID) { continue }
        $inicio = $null
        try { $inicio = $p.CreationDate } catch { }
        $recente = (-not $inicio) -or ($inicio -ge $Since.AddMinutes(-1))
        $citaPasta = $p.CommandLine -and ($p.CommandLine.IndexOf($Folder, [StringComparison]::OrdinalIgnoreCase) -ge 0)
        if (($p.Name -ieq 'msinfo32.exe' -and $recente) -or $citaPasta) { $lista += ('{0} ({1})' -f $p.Name, $p.ProcessId) }
    }
    return $lista
}

function Wait-OTSSBlockingProcess {
    # Espera os processos de Get-OTSSBlockingProcess terminarem. $true se terminaram; $false no tempo limite.
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][datetime]$Since,
        [int]$TimeoutSec = 1200,
        [int]$PollSec = 10,
        [string]$LogPath
    )
    $limite = (Get-Date).AddSeconds($TimeoutSec)
    $avisou = $false
    while ($true) {
        $procs = @(Get-OTSSBlockingProcess -Folder $Folder -Since $Since)
        if ($procs.Count -eq 0) { return $true }
        if ((Get-Date) -ge $limite) {
            if ($LogPath) { Write-OTSSLog $LogPath "  AVISO: tempo limite esperando: $($procs -join ', '). Compactando mesmo assim." }
            return $false
        }
        if (-not $avisou -and $LogPath) {
            Write-OTSSLog $LogPath "  Aguardando processos da coleta terminarem: $($procs -join ', ')"
            $avisou = $true
        }
        Start-Sleep -Seconds $PollSec
    }
}

function New-OTSSZip {
    # Compacta a pasta arquivo a arquivo, abrindo cada um em modo compartilhado (FileShare ReadWrite/Delete).
    # Arquivo preso exclusivamente: tenta $Retries vezes; se continuar preso, fica fora do zip.
    # Retorna os caminhos dos arquivos que ficaram fora (vazio = zip completo).
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [int]$Retries = 6,
        [int]$RetryDelaySec = 10
    )
    Add-Type -AssemblyName System.IO.Compression
    # Prefixo \\?\ para enumerar e abrir caminhos acima de 260 caracteres (o TSS gera nomes longos,
    # ex.: LocaleMetaData\<host>_evt_Microsoft-Windows-...-Operational_1033.MTA); Get-ChildItem do PS 5.1 os ignora.
    $raiz = (Resolve-Path -LiteralPath $Source).ProviderPath.TrimEnd('\') + '\'
    $raizLonga = if ($raiz.StartsWith('\\?\')) { $raiz } elseif ($raiz.StartsWith('\\')) { '\\?\UNC\' + $raiz.Substring(2) } else { '\\?\' + $raiz }
    $pulados = New-Object System.Collections.Generic.List[string]
    $destStream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($destStream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            foreach ($caminho in [IO.Directory]::EnumerateFiles($raizLonga, '*', [IO.SearchOption]::AllDirectories)) {
                $rel = $caminho.Substring($raizLonga.Length)
                $ok = $false
                for ($i = 1; $i -le [math]::Max(1, $Retries) -and -not $ok; $i++) {
                    try {
                        $in = [IO.File]::Open($caminho, [IO.FileMode]::Open, [IO.FileAccess]::Read,
                                              ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                        try {
                            $entry = $zip.CreateEntry($rel.Replace('\', '/'), [IO.Compression.CompressionLevel]::Optimal)
                            $entry.LastWriteTime = [IO.File]::GetLastWriteTime($caminho)
                            $out = $entry.Open()
                            try { $in.CopyTo($out) } finally { $out.Dispose() }
                            $ok = $true
                        } finally { $in.Dispose() }
                    } catch [IO.IOException] {
                        if ($i -lt $Retries) { Start-Sleep -Seconds $RetryDelaySec }
                    }
                }
                if (-not $ok) { $pulados.Add($raiz + $rel) }
            }
        } finally { $zip.Dispose() }
    } finally { $destStream.Dispose() }
    return $pulados.ToArray()
}

$script:LogsProprios = @('*_Log-transcript.txt', '*_Log-Warn-Err-Info.txt', '*_ErrorVariable.txt', '*Command-Error.txt')

function Test-OTSSSdpOutput {
    # Ha coleta real se alguma pasta SDP_* tem arquivo alem dos logs do proprio TSS
    # (o TSS cria a pasta e o transcript mesmo quando aborta).
    param([Parameter(Mandatory)][string]$Folder)
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return $false }
    foreach ($sdp in @(Get-ChildItem -LiteralPath $Folder -Directory -Filter 'SDP_*')) {
        foreach ($f in @(Get-ChildItem -LiteralPath $sdp.FullName -File -Recurse -ErrorAction SilentlyContinue)) {
            $proprio = $false
            foreach ($p in $script:LogsProprios) { if ($f.Name -like $p) { $proprio = $true; break } }
            if (-not $proprio) { return $true }
        }
    }
    return $false
}

function Get-OTSSTssErrorCount {
    # Linhas com ERROR no *_Log-Warn-Err-Info.txt do TSS e no tss-console.log
    param([Parameter(Mandatory)][string]$Folder)
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return 0 }
    $arquivos = @(Get-ChildItem -LiteralPath $Folder -Directory -Filter 'SDP_*' |
                  Get-ChildItem -File -Recurse -Filter '*_Log-Warn-Err-Info.txt' -ErrorAction SilentlyContinue)
    $console = Join-Path $Folder 'tss-console.log'
    if (Test-Path -LiteralPath $console) { $arquivos += Get-Item -LiteralPath $console }
    $n = 0
    foreach ($a in $arquivos) {
        $n += @(Select-String -LiteralPath $a.FullName -Pattern '\bERROR\b' -CaseSensitive -ErrorAction SilentlyContinue).Count
    }
    return $n
}

function Get-OTSSTssAge {
    # Dias desde a versao do TSS (ex.: '2026.11.11.0'); -1 se ilegivel
    param([Parameter(Mandatory)][string]$TssVersion, [Parameter(Mandatory)][datetime]$Now)
    $m = [regex]::Match($TssVersion, '^(\d{4})\.(\d{1,2})\.(\d{1,2})')
    if (-not $m.Success) { return -1 }
    try { $d = New-Object DateTime ([int]$m.Groups[1].Value), ([int]$m.Groups[2].Value), ([int]$m.Groups[3].Value) } catch { return -1 }
    return [int][math]::Floor(($Now.Date - $d).TotalDays)
}

function Test-OTSSFreeSpace {
    param([Parameter(Mandatory)][string]$Drive, [Parameter(Mandatory)][int]$MinGB)
    return ((Get-OTSSFreeBytes -Drive $Drive) -ge ([long]$MinGB * 1GB))
}

function Copy-OTSSMinidumps {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][int]$Days,
        [Parameter(Mandatory)][datetime]$Now
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return 0 }
    $limite = $Now.AddDays(-$Days)
    $arquivos = @(Get-ChildItem -LiteralPath $Source -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $limite })
    if ($arquivos.Count -eq 0) { return 0 }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $n = 0
    foreach ($a in $arquivos) {
        try { Copy-Item -LiteralPath $a.FullName -Destination $Destination -ErrorAction Stop; $n++ } catch { }
    }
    return $n
}

function Get-OTSSPendingReboot {
    # Motivos de reinicio pendente (vazio = nenhum). Causa comum de falha de instalacao de cumulativo.
    param([string]$WindowsDir = $env:SystemRoot)
    $motivos = @()
    if (Test-OTSSRegistryPath -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $motivos += 'CBS RebootPending' }
    if (Test-OTSSRegistryPath -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress') { $motivos += 'CBS RebootInProgress' }
    if (Test-OTSSRegistryPath -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending') { $motivos += 'CBS PackagesPending' }
    if (Test-OTSSRegistryPath -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $motivos += 'WindowsUpdate RebootRequired' }
    if (Get-OTSSPendingFileRename) { $motivos += 'PendingFileRenameOperations' }
    if (Test-Path -LiteralPath (Join-Path $WindowsDir 'WinSxS\pending.xml')) { $motivos += 'WinSxS\pending.xml' }
    return $motivos
}

function Copy-OTSSServicingLogs {
    # Logs de instalacao do Windows: CBS (*.log e CbsPersist_*.cab dos ultimos $Days dias), DISM e os logs de
    # atualizacao do SCCM (WUAHandler, UpdatesDeployment, UpdatesHandler, UpdatesStore, CAS, ContentTransferManager,
    # inclusive os rotacionados "-AAAAMMDD-HHMMSS"). Copia em modo compartilhado (o CBS.log fica aberto pelo
    # TrustedInstaller), mais recentes primeiro, ate $MaxMB.
    param(
        [Parameter(Mandatory)][string]$WindowsDir,
        [Parameter(Mandatory)][string]$Destination,
        [int]$Days = 30,
        [datetime]$Now = (Get-Date),
        [int]$MaxMB = 2048
    )
    $limiteData = $Now.AddDays(-$Days)
    $ccm = '^(WUAHandler|UpdatesDeployment|UpdatesHandler|UpdatesStore|CAS|ContentTransferManager)(-\d{8}-\d{6})?\.lo[g_]$'
    $fontes = @(
        @{ Dir = 'Logs\CBS';  Sub = 'CBS';  Filtro = { $_.Extension -in '.log', '.cab' } }
        @{ Dir = 'Logs\DISM'; Sub = 'DISM'; Filtro = { $_.Extension -eq '.log' } }
        @{ Dir = 'CCM\Logs';  Sub = 'CCM';  Filtro = { $_.Name -match $ccm } }
    )
    $candidatos = @()
    foreach ($f in $fontes) {
        $dir = Join-Path $WindowsDir $f.Dir
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        $candidatos += @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
            Where-Object $f.Filtro | Where-Object { $_.LastWriteTime -ge $limiteData } |
            ForEach-Object { [pscustomobject]@{ Arquivo = $_; Sub = $f.Sub } })
    }
    $res = [pscustomobject]@{ Copiados = 0; Pulados = 0; ForaDoLimite = 0; MB = 0 }
    $total = [long]0; $max = [long]$MaxMB * 1MB
    foreach ($c in ($candidatos | Sort-Object { $_.Arquivo.LastWriteTime } -Descending)) {
        if ($total + $c.Arquivo.Length -gt $max) { $res.ForaDoLimite++; continue }
        $destDir = Join-Path $Destination $c.Sub
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        try {
            $in = [IO.File]::Open($c.Arquivo.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read,
                                  ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            try {
                $out = [IO.File]::Create((Join-Path $destDir $c.Arquivo.Name))
                try { $in.CopyTo($out) } finally { $out.Dispose() }
            } finally { $in.Dispose() }
            $total += $c.Arquivo.Length
            $res.Copiados++
        } catch {
            $res.Pulados++
        }
    }
    $res.MB = [math]::Round($total / 1MB, 1)
    return $res
}

#region Guia para IA (LEIA-PRIMEIRO_IA.md)
# Sintoma -> arquivos da coleta em ordem de prioridade (padrao do caminho relativo, com '/') e o que procurar.
$script:OTSSSintomas = @(
    [pscustomobject]@{ N = 1; Nome = 'Tela azul (BSOD) ou reinício inesperado'; Itens = @(
        @{ P = 'OTSS.log'; D = 'MEMORY.DMP (existe? data?) e quantidade de minidumps copiados.' }
        @{ P = 'Minidump/*'; D = 'Minidumps dos últimos 30 dias: analisar com WinDbg (!analyze -v).' }
        @{ P = '*_evt_System.txt'; D = 'IDs 41 (Kernel-Power), 6008 (desligamento inesperado), 1001 (BugCheck), 1074 (quem reiniciou), 6005/6006, WHEA-Logger 17/18/19/47, 161/49 (falha ao gravar dump). Reinício (41/6008) sem BugCheck e sem dump costuma ser hardware: procure, logo após cada volta, a fonte "HPE Agentless Management Service" (ID 1295 = registro do IML do iLO), com "Uncorrectable Machine Check" (processador e Bank; Banks 7/8 = controlador de memória, apontam DIMM da CPU indicada) ou erro de memória/fonte; confirme no IML/AHS do iLO.' }
        @{ P = '*_SUMMARY.TXT'; D = 'Seção CrashControl (CrashDumpEnabled, DumpFile) e tamanho do pagefile x RAM.' }
        @{ P = '*_evt_Application.txt'; D = 'ID 1001 Windows Error Reporting com BlueScreen ou LiveKernelEvent.' }
        @{ P = '*_sym_RunningDrivers.TXT'; D = 'Drivers de terceiros carregados e versões (antigos = suspeitos).' }
        @{ P = '*_sym_Drivers.TXT'; D = 'Versões e datas de todos os drivers.' }
        @{ P = '*_msinfo32.txt'; D = 'Dispositivos com problema, BIOS, modelo.' }
    ) }
    [pscustomobject]@{ N = 2; Nome = 'Lentidão / performance'; Itens = @(
        @{ P = '*_Perfmon.blg'; D = 'Contadores de CPU, memória, disco (latência) e rede durante a coleta.' }
        @{ P = '*_Poolmon.txt'; D = 'Vazamento de pool do kernel (tags com uso alto).' }
        @{ P = '*_PStat.txt'; D = 'Processos e threads com mais CPU/memória.' }
        @{ P = '*_evt_Microsoft-Windows-Storage-Storport-Operational.txt'; D = 'Latência e resets de IO (IDs 505, 549).' }
        @{ P = '*_HyperV_BasicInfo_*.TXT'; D = 'Configuração das VMs e do host (memória, vCPUs, NUMA).' }
        @{ P = '*_evt_Microsoft-Windows-Hyper-V-Hypervisor-Operational.txt'; D = 'Avisos do hypervisor.' }
        @{ P = '*/ClusterLogs/cluster.log'; D = 'Atrasos e timeouts de recursos.' }
    ) }
    [pscustomobject]@{ N = 3; Nome = 'Falha de atualização (Windows Update / SCCM)'; Itens = @(
        @{ P = 'OTSS.log'; D = 'Linha "reinicio pendente" (CBS RebootPending, pending.xml) - causa comum de 0x80240016.' }
        @{ P = 'Servicing/CBS/*'; D = 'CBS.log/CbsPersist: (a) "0x800f0831 - CBS_E_STORE_CORRUPTION" = repositório de componentes (WinSxS) corrompido, bloqueia qualquer cumulativo - reparar com DISM /RestoreHealth com fonte local; (b) "Session leak detected" no desligamento = instalação cortada por reinício; (c) linhas "FLOW: Entering stage" (Extracting, Planning, Resolving, Staging, Installing) mostram em que etapa a instalação estava - compare com o horário do evento 1074 (quem pediu o reinício) no evt_System; (d) "Failed", "rollback", "0x800f" no horário da instalação. O resumo automático está em "Fatos desta coleta".' }
        @{ P = 'Servicing/Setup.evtx'; D = 'Resultado de cada pacote (IDs 2, 3, 4 = instalado/reinício; erros com o KB).' }
        @{ P = 'Servicing/CCM/*'; D = 'SCCM: UpdatesDeployment/UpdatesHandler/WUAHandler mostram o que foi mandado instalar e o resultado.' }
        @{ P = '*_WindowsUpdate.ETW_Converted.txt'; D = '"Installing updates", "Completed install", "Exit code", "Reboot required", hr=0x... por horário.' }
        @{ P = '*_evt_Microsoft-Windows-WindowsUpdateClient-Operational.txt'; D = 'ID 25 (falha de busca) com o código, 19/20 (instalação ok/falha).' }
        @{ P = '*_HotfixRollups.TXT'; D = 'Quais cumulativos estão instalados (Yes/No) e o build atual.' }
        @{ P = 'Servicing/DISM/*'; D = 'Erros de DISM/reparo do repositório de componentes.' }
        @{ P = '*_WindowsUpdate_reg_wupolicy_output.txt'; D = 'Servidor WSUS e políticas.' }
    ) }
    [pscustomobject]@{ N = 4; Nome = 'Nó sai do cluster / failover / recursos falhando'; Itens = @(
        @{ P = '*/ClusterLogs/cluster.log'; D = 'Horário do evento: "lost", "removed", "heartbeat", "regroup", "Quarantine".' }
        @{ P = '*_evt_Microsoft-Windows-FailoverClustering-Operational.txt'; D = 'Eventos do cluster em ordem.' }
        @{ P = '*_evt_System.txt'; D = 'FailoverClustering 1135 (nó removido), 1069 (recurso falhou), 1146/1177 (quorum/RHS).' }
        @{ P = '*_evt_Microsoft-Windows-FailoverClustering-NetFt-Operational.txt'; D = 'Perda de rotas de heartbeat entre nós.' }
        @{ P = '*_ClusterProperties.txt'; D = 'SameSubnetDelay/Threshold, quorum, configuração.' }
        @{ P = '*/ClusterReports/Validation Report*.htm'; D = 'Validações do cluster, mais recente primeiro (avisos e falhas).'; Rev = $true; Max = 3 }
    ) }
    [pscustomobject]@{ N = 5; Nome = 'Máquina virtual com problema (não liga, migração, travada)'; Itens = @(
        @{ P = '*_evt_Microsoft-Windows-Hyper-V-VMMS-Admin.txt'; D = 'Erros de gerenciamento, migração ao vivo, checkpoint.' }
        @{ P = '*_evt_Microsoft-Windows-Hyper-V-Worker-Admin.txt'; D = 'Falhas da VM em execução (worker process).' }
        @{ P = '*_evt_Microsoft-Windows-Hyper-V-High-Availability-Admin.txt'; D = 'VM clusterizada: falhas de recurso.' }
        @{ P = '*_evt_Microsoft-Windows-Hyper-V-Compute-*.txt'; D = 'Hyper-V Compute (HCS).' }
        @{ P = '*_evt_Microsoft-Windows-Hyper-V-VMMS-Storage.txt'; D = 'VHDX, caminhos e permissões.' }
        @{ P = '*_HyperV_BasicInfo_*.TXT'; D = 'Inventário das VMs por nó.' }
    ) }
    [pscustomobject]@{ N = 6; Nome = 'Storage / CSV / discos'; Itens = @(
        @{ P = '*_evt_Microsoft-Windows-FailoverClustering-CsvFs-Operational.txt'; D = 'CSV pausado/redirecionado.' }
        @{ P = '*_evt_Microsoft-Windows-Storage-Storport-Operational.txt'; D = 'Resets e latência de HBA (Emulex/QLogic).' }
        @{ P = '*_evt_Microsoft-Windows-Storage-ClassPnP-Operational.txt'; D = 'Erros de IO por disco.' }
        @{ P = '*_evt_Microsoft-Windows-Storage-MultipathIoControlDriver-Operational.txt'; D = 'Caminhos MPIO caindo.' }
        @{ P = '*_mpclaim.txt'; D = 'Política e caminhos MPIO.' }
        @{ P = '*_StorageInfo.txt'; D = 'Discos, volumes, CSV.' }
        @{ P = '*_evt_System.txt'; D = 'disk 153/129, Ntfs 55/98/140, iScsiPrt.' }
        @{ P = '*/ClusterReports/ValidateStorage.log'; D = 'Testes de storage da validação.' }
    ) }
    [pscustomobject]@{ N = 7; Nome = 'Rede (vSwitch, LBFO, SMB, DNS)'; Itens = @(
        @{ P = '*_NetworkAdapters_info_pscmdlets.TXT'; D = 'Placas, drivers, RSS/VMQ, velocidade.' }
        @{ P = '*_NetworkLBFO_*'; D = 'Team LBFO (modo, membros).' }
        @{ P = '*_HyperV_Networking_Info_pscmdlets_*.TXT'; D = 'vSwitches e adaptadores virtuais.' }
        @{ P = '*_evt_Microsoft-Windows-SMBClient-Connectivity.txt'; D = 'Quedas de conexão SMB (CSV redirecionado, Live Migration).' }
        @{ P = '*_evt_Microsoft-Windows-FailoverClustering-NetFt-Operational.txt'; D = 'Rede de heartbeat do cluster.' }
        @{ P = '*_DnsClient_*'; D = 'Resolução de nomes.' }
        @{ P = '*_evt_System.txt'; D = 'Hyper-V-VmSwitch 106/15, NETLOGON 5719.' }
    ) }
    [pscustomobject]@{ N = 8; Nome = 'Outro (descrever)'; Itens = @(
        @{ P = '*_SUMMARY.TXT'; D = 'Visão geral da máquina.' }
        @{ P = '*_evt_System.txt'; D = 'Erros e críticos no período relatado.' }
        @{ P = '*_evt_Application.txt'; D = 'Erros de aplicação no período relatado.' }
        @{ P = 'OTSS.log'; D = 'Detecção, avisos e duração da coleta.' }
    ) }
)

function Get-OTSSRelativeFiles {
    # Caminhos relativos (com '/') e tamanho de todos os arquivos da pasta, inclusive caminhos acima de 260.
    param([Parameter(Mandatory)][string]$Folder)
    $raiz = (Resolve-Path -LiteralPath $Folder).ProviderPath.TrimEnd('\') + '\'
    $longa = if ($raiz.StartsWith('\\')) { '\\?\UNC\' + $raiz.Substring(2) } else { '\\?\' + $raiz }
    foreach ($c in [IO.Directory]::EnumerateFiles($longa, '*', [IO.SearchOption]::AllDirectories)) {
        [pscustomobject]@{ Rel = $c.Substring($longa.Length).Replace('\', '/'); Bytes = (New-Object IO.FileInfo($c)).Length }
    }
}

function New-OTSSAiGuide {
    # Gera LEIA-PRIMEIRO_IA.md na raiz da coleta: instrucoes para a IA que vai ler os logs (perguntar o sintoma
    # primeiro) e, por sintoma, os arquivos desta coleta com maior afinidade e o que procurar em cada um.
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][pscustomobject]$Role,
        [string]$OtssVersion = '?',
        [string]$TssVersion = '?',
        [System.Collections.IDictionary]$Facts = @{}
    )
    $arquivos = @(Get-OTSSRelativeFiles -Folder $Folder | Where-Object { $_.Rel -ne 'LEIA-PRIMEIRO_IA.md' })
    $tam = { param($b) if ($b -ge 1MB) { '{0:N1} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f [math]::Max(1, $b / 1KB) } }
    # Pasta de saida do TSS (ex.: SDP_Cluster/<host>_<data>_SDP_Cluster/), abreviada como SDP/ no texto
    $sdpPrefixo = $null
    $m = $arquivos | ForEach-Object { [regex]::Match($_.Rel, '^(SDP_[^/]+/[^/]+_SDP_[^/]+/)') } | Where-Object Success | Select-Object -First 1
    if ($m) { $sdpPrefixo = $m.Groups[1].Value }
    $mostra = { param($rel) if ($sdpPrefixo -and $rel.StartsWith($sdpPrefixo)) { 'SDP/' + $rel.Substring($sdpPrefixo.Length) } else { $rel } }
    $papel = switch ($Role.Tipo) {
        'Cluster' { "nó do cluster $($Role.Cluster) ($($Role.Nos) nós)$(if ($Role.HyperV) { ' com Hyper-V' })" }
        'HyperV'  { 'host Hyper-V fora de cluster' }
        default   { 'servidor sem Hyper-V (coleta padrão)' }
    }
    $sb = New-Object Text.StringBuilder
    $add = { param($l) [void]$sb.AppendLine($l) }

    & $add '# LEIA PRIMEIRO - instruções para a IA que vai analisar esta coleta'
    & $add ''
    & $add "Coleta OTSS de **$Computer** ($papel). Gerada pelo OTSS $OtssVersion com o TSS da Microsoft $TssVersion."
    & $add ''
    & $add '## 1. Pergunte o sintoma ANTES de analisar'
    & $add ''
    & $add 'ANTES de abrir qualquer outro arquivo desta coleta, faça ao usuário esta pergunta e espere a resposta:'
    & $add ''
    & $add '> **Qual é o principal sintoma?** Por exemplo: é um problema de tela azul ou de performance?'
    & $add '>'
    foreach ($s in $script:OTSSSintomas) { & $add "> $($s.N). $($s.Nome)" }
    & $add '>'
    & $add '> Se souber, informe também **quando** aconteceu (data e hora) e em **qual host ou VM**.'
    & $add ''
    & $add 'Depois da resposta, leia **primeiro** os arquivos da seção do sintoma escolhido (seção 3), na ordem em que'
    & $add 'aparecem, e só depois amplie para os demais. Se o usuário der data/hora, filtre os logs por esse período.'
    & $add ''
    & $add '## 2. Fatos desta coleta'
    & $add ''
    & $add "- Máquina: $Computer"
    & $add "- Papel detectado: $papel"
    foreach ($k in $Facts.Keys) { & $add "- ${k}: $($Facts[$k])" }
    & $add ''
    & $add '## 3. Arquivos com maior afinidade, por sintoma'
    & $add ''
    & $add 'Só aparecem arquivos que existem nesta coleta. Caminhos relativos à raiz do zip.'
    if ($sdpPrefixo) { & $add ('Abreviação: `SDP/` = `' + $sdpPrefixo + '` (pasta de saída do TSS).') }
    foreach ($s in $script:OTSSSintomas) {
        & $add ''
        & $add "### $($s.N). $($s.Nome)"
        & $add ''
        $listou = $false
        foreach ($it in $s.Itens) {
            $achados = @($arquivos | Where-Object { $_.Rel -like $it.P } | Sort-Object Rel -Descending:([bool]$it.Rev))
            if ($achados.Count -eq 0) { continue }
            $listou = $true
            $limite = if ($it.Max) { $it.Max } else { 6 }
            $mostrar = @($achados | Select-Object -First $limite)
            $lista = ($mostrar | ForEach-Object { '`' + (& $mostra $_.Rel) + '` (' + (& $tam $_.Bytes) + ')' }) -join ', '
            if ($achados.Count -gt $mostrar.Count) { $lista += " e mais $($achados.Count - $mostrar.Count)" }
            & $add "- $lista - $($it.D)"
        }
        if (-not $listou) { & $add '- (nenhum arquivo específico nesta coleta; use a seção 8)' }
    }
    & $add ''
    & $add '## 4. Como ler e responder'
    & $add ''
    & $add '- Separe o que é **constatado** (está no log, com arquivo e horário), **deduzido** e **a confirmar**.'
    & $add '- Cite arquivo e horário de cada evidência. Não invente eventos que não estão nos arquivos.'
    & $add '- Os `.txt` de eventos e vários relatórios do TSS estão em **UTF-16**. Os `.evtx` estão completos; os `.txt`/`.csv` de eventos podem cobrir só os últimos 30 dias (`-EvtDaysBack 30`).'
    & $add '- Arquivos binários: `.evtx` (abrir no Visualizador de Eventos ou `Get-WinEvent -Path`), `.blg` (converter com `relog arquivo.blg -f csv -o saida.csv`), `.etl`, `.hiv` (hive de registro), `.cab`. Prefira os `.txt` equivalentes quando existirem.'
    & $add '- O log de eventos do Windows dá a volta: veja a primeira e a última data de cada arquivo antes de concluir que "não há eventos".'
    & $add '- Linhas `ERROR` do próprio TSS no `*_Log-Warn-Err-Info.txt` (ex.: `showpriv`, `netsh ipv6`, `vssadmin list shadows`) costumam ser comandos auxiliares sem importância; não as trate como causa.'
    & $add '- `OTSS.log` traz a detecção, avisos (reinício pendente, LogFolder do TSS) e a duração da coleta.'
    & $add '- Termine com próximos passos práticos e o que coletar a mais, se faltar evidência.'
    & $add ''
    & $add '## 5. Todos os arquivos'
    & $add ''
    & $add ("{0} arquivos, {1} no total. Índice completo: liste o zip; os principais estão na seção 3." -f $arquivos.Count, (& $tam (($arquivos | Measure-Object Bytes -Sum).Sum)))

    $destino = Join-Path $Folder 'LEIA-PRIMEIRO_IA.md'
    [IO.File]::WriteAllText($destino, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
    return $destino
}
#endregion

function Get-OTSSCbsSummary {
    # Varre os .log do CBS copiados e conta os dois sinais vistos em campo:
    # 0x800f0831 (repositorio de componentes corrompido) e "CBS Session leak detected" (instalacao cortada no desligamento).
    param([Parameter(Mandatory)][string]$Folder)
    $r = [pscustomobject]@{ Corrupcao = 0; PrimeiraCorrupcao = $null; KBsCorrupcao = @(); SessaoInterrompida = 0
                            PrimeiraSessaoInterrompida = $null; Texto = '' }
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { $r.Texto = 'sem logs do CBS na coleta'; return $r }
    $kbs = New-Object System.Collections.Generic.HashSet[string]
    $menor = { param($atual, $novo) if (-not $atual -or $novo -lt $atual) { $novo } else { $atual } }
    foreach ($f in @(Get-ChildItem -LiteralPath $Folder -File -Filter '*.log')) {
        foreach ($l in [IO.File]::ReadLines($f.FullName)) {
            if ($l.IndexOf('0x800f0831', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $r.Corrupcao++
                if ($l.Length -ge 19) { $r.PrimeiraCorrupcao = & $menor $r.PrimeiraCorrupcao $l.Substring(0, 19) }
                $m = [regex]::Match($l, 'for_(KB\d+)')
                if ($m.Success) { [void]$kbs.Add($m.Groups[1].Value) }
            } elseif ($l.IndexOf('CBS Session leak detected', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $r.SessaoInterrompida++
                if ($l.Length -ge 19) { $r.PrimeiraSessaoInterrompida = & $menor $r.PrimeiraSessaoInterrompida $l.Substring(0, 19) }
            }
        }
    }
    $r.KBsCorrupcao = @($kbs | Sort-Object)
    $partes = @()
    if ($r.Corrupcao) {
        $partes += ('{0} x 0x800f0831 (repositorio de componentes corrompido; pacotes {1}) desde {2}' -f $r.Corrupcao, ($r.KBsCorrupcao -join ', '), $r.PrimeiraCorrupcao)
    }
    if ($r.SessaoInterrompida) {
        $partes += ('{0} sessao(oes) de instalacao interrompida(s) no desligamento, primeira em {1}' -f $r.SessaoInterrompida, $r.PrimeiraSessaoInterrompida)
    }
    $r.Texto = if ($partes) { $partes -join '; ' } else { 'sem sinais de corrupcao (0x800f0831) nem de instalacao interrompida' }
    return $r
}

function Get-OTSSMemoryDumpInfo {
    param([Parameter(Mandatory)][string]$Path)
    $f = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $f) { return 'MEMORY.DMP nao encontrado' }
    $gb = [math]::Round($f.Length / 1GB, 1).ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
    return 'MEMORY.DMP: {0}, {1} GB (nao copiado)' -f $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $gb
}

function Write-OTSSLog {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Message)
    $linha = '{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message
    [IO.File]::AppendAllText($Path, $linha + [Environment]::NewLine, (New-Object Text.UTF8Encoding($true)))
    Write-Host $Message
}

Export-ModuleMember -Function *-OTSS*
