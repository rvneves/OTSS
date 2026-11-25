BeforeAll {
    Import-Module "$PSScriptRoot\..\src\OTSS.Core.psm1" -Force
}

Describe 'Get-OTSSRole' {
    Context 'no de cluster' {
        BeforeEach {
            Mock Test-OTSSServiceRunning { $true } -ModuleName OTSS.Core -ParameterFilter { $Name -eq 'ClusSvc' }
            Mock Get-OTSSClusterInfo { [pscustomobject]@{ Name = 'CLUSTER02'; NodeCount = 4 } } -ModuleName OTSS.Core
            Mock Test-OTSSServiceExists { $true } -ModuleName OTSS.Core -ParameterFilter { $Name -eq 'vmms' }
            Mock Test-OTSSS2D { $false } -ModuleName OTSS.Core
        }
        It 'no de cluster com Hyper-V e sem S2D' {
            $r = Get-OTSSRole
            $r.Tipo | Should -Be 'Cluster'
            $r.Cluster | Should -Be 'CLUSTER02'
            $r.Nos | Should -Be 4
            $r.HyperV | Should -BeTrue
            $r.S2D | Should -BeFalse
        }
        It 'cluster com S2D' {
            Mock Test-OTSSS2D { $true } -ModuleName OTSS.Core
            (Get-OTSSRole).S2D | Should -BeTrue
        }
    }
    It 'ClusSvc rodando mas Get-Cluster falha vira HyperV e registra motivo' {
        Mock Test-OTSSServiceRunning { $true } -ModuleName OTSS.Core -ParameterFilter { $Name -eq 'ClusSvc' }
        Mock Get-OTSSClusterInfo { $null } -ModuleName OTSS.Core
        Mock Test-OTSSServiceExists { $true } -ModuleName OTSS.Core -ParameterFilter { $Name -eq 'vmms' }
        $r = Get-OTSSRole
        $r.Tipo | Should -Be 'HyperV'
        ($r.Motivo -join ' ') | Should -Match 'Get-Cluster'
    }
    It 'ClusSvc parado e vmms existe: HyperV' {
        Mock Test-OTSSServiceRunning { $false } -ModuleName OTSS.Core
        Mock Test-OTSSServiceExists { $true } -ModuleName OTSS.Core -ParameterFilter { $Name -eq 'vmms' }
        (Get-OTSSRole).Tipo | Should -Be 'HyperV'
    }
    It 'sem cluster e sem vmms: Setup' {
        Mock Test-OTSSServiceRunning { $false } -ModuleName OTSS.Core
        Mock Test-OTSSServiceExists { $false } -ModuleName OTSS.Core
        $r = Get-OTSSRole
        $r.Tipo | Should -Be 'Setup'
        $r.HyperV | Should -BeFalse
    }
}

Describe 'Get-OTSSRunName' {
    It 'formato' {
        Get-OTSSRunName -Computer 'HVNODE01' -Tipo 'Cluster' -Now ([datetime]'2026-11-25 14:30:00') -Root $TestDrive |
            Should -Be 'HVNODE01_20261125_143000_Cluster'
    }
    It 'nao reutiliza nome existente' {
        New-Item -ItemType Directory "$TestDrive\HVNODE01_20261125_143000_Cluster" | Out-Null
        Get-OTSSRunName -Computer 'HVNODE01' -Tipo 'Cluster' -Now ([datetime]'2026-11-25 14:30:00') -Root $TestDrive |
            Should -Be 'HVNODE01_20261125_143000_Cluster_2'
    }
    It 'considera o zip existente tambem' {
        Set-Content "$TestDrive\X_20261125_143000_Setup.zip" 'z'
        Get-OTSSRunName -Computer 'X' -Tipo 'Setup' -Now ([datetime]'2026-11-25 14:30:00') -Root $TestDrive |
            Should -Be 'X_20261125_143000_Setup_2'
    }
}

Describe 'Get-OTSSTssCommand' {
    BeforeAll {
        $base = '-AcceptEula -noXray -noUpdate -noAsk -noZip -noExpire -EvtDaysBack 30'
        $tss = 'C:\temp\OTSS\_tss_1\tss\TSS.ps1'; $out = 'C:\temp\OTSS\H_1_Cluster'
    }
    It 'cluster com Hyper-V sem S2D' {
        $role = [pscustomobject]@{ Tipo = 'Cluster'; HyperV = $true; S2D = $false }
        Get-OTSSTssCommand -Role $role -TssPath $tss -LogFolderPath $out |
            Should -Be "& '$tss' -SDP Cluster -SkipSDPList skipBPA,skipSddc -LogFolderPath '$out' $base"
    }
    It 'cluster com S2D mantem SDDC' {
        $role = [pscustomobject]@{ Tipo = 'Cluster'; HyperV = $true; S2D = $true }
        Get-OTSSTssCommand -Role $role -TssPath $tss -LogFolderPath $out | Should -Match '-SDP Cluster -SkipSDPList skipBPA -LogFolderPath'
    }
    It 'cluster sem Hyper-V' {
        $role = [pscustomobject]@{ Tipo = 'Cluster'; HyperV = $false; S2D = $false }
        Get-OTSSTssCommand -Role $role -TssPath $tss -LogFolderPath $out | Should -Match '-SDP Cluster -SkipSDPList skipBPA,skipSddc '
    }
    It 'Hyper-V isolado usa o SDP Cluster (HyperV obsoleto no TSS) sem SDDC' {
        $role = [pscustomobject]@{ Tipo = 'HyperV'; HyperV = $true; S2D = $false }
        Get-OTSSTssCommand -Role $role -TssPath $tss -LogFolderPath $out | Should -Match '-SDP Cluster -SkipSDPList skipBPA,skipSddc -LogFolderPath'
    }
    It 'nunca usa SDP obsoleto (HyperV, S2D)' {
        foreach ($r in @(@{Tipo='Cluster';HyperV=$true;S2D=$true}, @{Tipo='Cluster';HyperV=$true;S2D=$false}, @{Tipo='HyperV';HyperV=$true;S2D=$false})) {
            Get-OTSSTssCommand -Role ([pscustomobject]$r) -TssPath $tss -LogFolderPath $out | Should -Not -Match '-SDP [^ ]*(HyperV|S2D)'
        }
    }
    It 'reserva' {
        $role = [pscustomobject]@{ Tipo = 'Setup'; HyperV = $false; S2D = $false }
        Get-OTSSTssCommand -Role $role -TssPath $tss -LogFolderPath $out | Should -Match '-SDP Setup -SkipSDPList skipBPA -LogFolderPath'
    }
    It 'apostrofo e espaco no caminho continuam validos' {
        $cmd = Get-OTSSTssCommand -Role ([pscustomobject]@{ Tipo = 'Setup'; HyperV = $false; S2D = $false }) -TssPath "C:\a b\O'x\TSS.ps1" -LogFolderPath "C:\a b\O'x\out"
        $cmd | Should -Match ([regex]::Escape("& 'C:\a b\O''x\TSS.ps1'"))
        { [scriptblock]::Create($cmd) } | Should -Not -Throw
    }
}

Describe 'Get-OTSSExitCode' {
    It 'sucesso'         { Get-OTSSExitCode -OutputExists $true  -TssExitCode 0 -TssErrorLines 0 -ZipCreated $true  | Should -Be 0 }
    It 'erro no TSS'     { Get-OTSSExitCode -OutputExists $true  -TssExitCode 1 -TssErrorLines 0 -ZipCreated $true  | Should -Be 1 }
    It 'linhas de ERROR' { Get-OTSSExitCode -OutputExists $true  -TssExitCode 0 -TssErrorLines 2 -ZipCreated $true  | Should -Be 1 }
    It 'sem saida'       { Get-OTSSExitCode -OutputExists $false -TssExitCode 0 -TssErrorLines 0 -ZipCreated $false | Should -Be 2 }
    It 'zip falhou'      { Get-OTSSExitCode -OutputExists $true  -TssExitCode 0 -TssErrorLines 0 -ZipCreated $false | Should -Be 2 }
}

Describe 'Test-OTSSFreeSpace' {
    It 'abaixo de 5 GB'    { Mock Get-OTSSFreeBytes { 4GB } -ModuleName OTSS.Core; Test-OTSSFreeSpace -Drive C -MinGB 5 | Should -BeFalse }
    It 'com 5 GB ou mais'  { Mock Get-OTSSFreeBytes { 5GB } -ModuleName OTSS.Core; Test-OTSSFreeSpace -Drive C -MinGB 5 | Should -BeTrue }
}

Describe 'Copy-OTSSMinidumps' {
    It 'copia so os de menos de 30 dias' {
        $src = New-Item -ItemType Directory "$TestDrive\md"; $now = [datetime]'2026-11-25'
        'a' | Set-Content "$src\novo.dmp";  (Get-Item "$src\novo.dmp").LastWriteTime = $now.AddDays(-2)
        'b' | Set-Content "$src\velho.dmp"; (Get-Item "$src\velho.dmp").LastWriteTime = $now.AddDays(-40)
        Copy-OTSSMinidumps -Source $src -Destination "$TestDrive\out\Minidump" -Days 30 -Now $now | Should -Be 1
        Test-Path "$TestDrive\out\Minidump\novo.dmp" | Should -BeTrue
        Test-Path "$TestDrive\out\Minidump\velho.dmp" | Should -BeFalse
    }
    It 'origem inexistente retorna 0 e nao cria pasta' {
        Copy-OTSSMinidumps -Source "$TestDrive\nada" -Destination "$TestDrive\o2" -Days 30 -Now (Get-Date) | Should -Be 0
        Test-Path "$TestDrive\o2" | Should -BeFalse
    }
}

Describe 'Get-OTSSMemoryDumpInfo' {
    It 'ausente' { Get-OTSSMemoryDumpInfo -Path "$TestDrive\MEMORY.DMP" | Should -Be 'MEMORY.DMP nao encontrado' }
    It 'presente nao e copiado' {
        'x' | Set-Content "$TestDrive\MEMORY.DMP"
        Get-OTSSMemoryDumpInfo -Path "$TestDrive\MEMORY.DMP" | Should -Match '^MEMORY\.DMP: \d{4}-\d{2}-\d{2} \d{2}:\d{2}, [\d,\.]+ GB \(nao copiado\)$'
    }
}

Describe 'Write-OTSSLog' {
    It 'grava linha com carimbo e acentos' {
        Write-OTSSLog -Path "$TestDrive\OTSS.log" -Message ('Coleta conclu' + [char]0x00ED + 'da')
        Get-Content "$TestDrive\OTSS.log" -Encoding UTF8 | Should -Match ('^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}  Coleta conclu' + [char]0x00ED + 'da$')
    }
}

Describe 'Test-OTSSSdpOutput' {
    It 'so logs do proprio TSS nao contam como coleta' {
        $d = New-Item -ItemType Directory "$TestDrive\run1\SDP_Cluster" -Force
        'x' | Set-Content "$d\H_251125_Log-transcript.txt"
        'x' | Set-Content "$d\H_251125_Log-Warn-Err-Info.txt"
        'x' | Set-Content "$d\H_251125_ErrorVariable.txt"
        'x' | Set-Content "$d\H_251125Command-Error.txt"
        Test-OTSSSdpOutput -Folder "$TestDrive\run1" | Should -BeFalse
    }
    It 'arquivo de dados conta como coleta' {
        $d = New-Item -ItemType Directory "$TestDrive\run2\SDP_Cluster\dados" -Force
        'x' | Set-Content "$d\H_msinfo32.nfo"
        Test-OTSSSdpOutput -Folder "$TestDrive\run2" | Should -BeTrue
    }
    It 'sem pasta SDP_' { Test-OTSSSdpOutput -Folder "$TestDrive\semnada" | Should -BeFalse }
}

Describe 'Get-OTSSTssErrorCount' {
    It 'conta ERROR no Warn-Err-Info e no console' {
        $d = New-Item -ItemType Directory "$TestDrive\err1\SDP_Cluster" -Force
        "linha ok`n[ERROR] falhou X`nWARNING y`nERROR: falhou Z" | Set-Content "$d\H_Log-Warn-Err-Info.txt"
        'ERROR: no console' | Set-Content "$TestDrive\err1\tss-console.log"
        Get-OTSSTssErrorCount -Folder "$TestDrive\err1" | Should -Be 3
    }
    It 'sem arquivos: zero' { Get-OTSSTssErrorCount -Folder "$TestDrive\semnada" | Should -Be 0 }
}

Describe 'New-OTSSZip' {
    BeforeEach {
        $src = Join-Path $TestDrive ('z' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory "$src\SDP_Cluster\sub" -Force | Out-Null
        'a' | Set-Content "$src\OTSS.log"
        'b' | Set-Content "$src\SDP_Cluster\sub\dados.txt"
        $zip = "$src.zip"
    }
    It 'compacta tudo com caminhos relativos' {
        $r = New-OTSSZip -Source $src -Destination $zip -Retries 1 -RetryDelaySec 0
        $r.Count | Should -Be 0
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [IO.Compression.ZipFile]::OpenRead($zip)
        try { ($z.Entries.FullName | Sort-Object) -replace '\\', '/' | Should -Be @('OTSS.log', 'SDP_Cluster/sub/dados.txt') } finally { $z.Dispose() }
    }
    It 'inclui arquivo aberto para escrita com compartilhamento (como o msinfo32 gravando)' {
        $fs = [IO.File]::Open("$src\SDP_Cluster\sub\dados.txt", 'Open', 'Write', 'Read')
        try { $r = New-OTSSZip -Source $src -Destination $zip -Retries 1 -RetryDelaySec 0 } finally { $fs.Dispose() }
        $r.Count | Should -Be 0
    }
    It 'inclui arquivo com caminho acima de 260 caracteres' {
        $longo = "$src\SDP_Cluster\" + ('d' * 120) + '\' + ('e' * 100)
        [IO.Directory]::CreateDirectory('\\?\' + $longo) | Out-Null
        [IO.File]::WriteAllText('\\?\' + $longo + '\evt_Microsoft-Windows-Storage-MultipathIoControlDriver-Operational_1033.MTA', 'x')
        try {
            $r = @(New-OTSSZip -Source $src -Destination $zip -Retries 1 -RetryDelaySec 0)
            $r.Count | Should -Be 0
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $z = [IO.Compression.ZipFile]::OpenRead($zip)
            try { @($z.Entries | Where-Object Name -like '*.MTA').Count | Should -Be 1 } finally { $z.Dispose() }
        } finally {
            # o Pester nao apaga caminhos acima de 260 caracteres do TestDrive
            [IO.Directory]::Delete('\\?\' + "$src\SDP_Cluster\" + ('d' * 120), $true)
        }
    }
    It 'arquivo preso exclusivamente e pulado, listado, e o resto vai para o zip' {
        $fs = [IO.File]::Open("$src\SDP_Cluster\sub\dados.txt", 'Open', 'ReadWrite', 'None')
        try { $r = @(New-OTSSZip -Source $src -Destination $zip -Retries 2 -RetryDelaySec 0) } finally { $fs.Dispose() }
        $r.Count | Should -Be 1
        $r[0] | Should -Match 'dados\.txt$'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [IO.Compression.ZipFile]::OpenRead($zip)
        try { $z.Entries.FullName | Should -Be @('OTSS.log') } finally { $z.Dispose() }
    }
}

Describe 'Wait-OTSSBlockingProcess' {
    It 'espera ate os processos sumirem' {
        $script:n = 0
        Mock Get-OTSSBlockingProcess { $script:n++; if ($script:n -lt 3) { @('msinfo32.exe (1234)') } else { @() } } -ModuleName OTSS.Core
        Wait-OTSSBlockingProcess -Folder $TestDrive -Since (Get-Date) -TimeoutSec 30 -PollSec 0 | Should -BeTrue
        Should -Invoke Get-OTSSBlockingProcess -ModuleName OTSS.Core -Times 3 -Exactly
    }
    It 'desiste no tempo limite e retorna falso' {
        Mock Get-OTSSBlockingProcess { @('msinfo32.exe (1234)') } -ModuleName OTSS.Core
        Wait-OTSSBlockingProcess -Folder $TestDrive -Since (Get-Date) -TimeoutSec 0 -PollSec 0 | Should -BeFalse
    }
}

Describe 'Get-OTSSExitCode com arquivos pulados no zip' {
    It 'arquivo pulado vira aviso' { Get-OTSSExitCode -OutputExists $true -TssExitCode 0 -TssErrorLines 0 -ZipCreated $true -ZipSkipped 2 | Should -Be 1 }
}

Describe 'Copy-OTSSServicingLogs' {
    BeforeEach {
        $win = Join-Path $TestDrive ('win' + [guid]::NewGuid().ToString('N'))
        $now = [datetime]'2026-11-25 12:00'
        New-Item -ItemType Directory "$win\Logs\CBS", "$win\Logs\DISM", "$win\CCM\Logs" -Force | Out-Null
        'cbs' | Set-Content "$win\Logs\CBS\CBS.log"
        'cab' | Set-Content "$win\Logs\CBS\CbsPersist_20261119.cab"
        'velho' | Set-Content "$win\Logs\CBS\CbsPersist_20260101.cab"
        (Get-Item "$win\Logs\CBS\CbsPersist_20260101.cab").LastWriteTime = $now.AddDays(-60)
        'dism' | Set-Content "$win\Logs\DISM\dism.log"
        'wua' | Set-Content "$win\CCM\Logs\WUAHandler.log"
        'wua2' | Set-Content "$win\CCM\Logs\WUAHandler-20261119-120000.log"
        'upd' | Set-Content "$win\CCM\Logs\UpdatesDeployment.log"
        'outro' | Set-Content "$win\CCM\Logs\PolicyAgent.log"
        $dest = Join-Path $TestDrive ('srv' + [guid]::NewGuid().ToString('N'))
    }
    It 'copia CBS (30 dias), DISM e logs de atualizacao do SCCM, e nada mais' {
        $r = Copy-OTSSServicingLogs -WindowsDir $win -Destination $dest -Days 30 -Now $now -MaxMB 2048
        $r.Copiados | Should -Be 6
        Test-Path "$dest\CBS\CBS.log" | Should -BeTrue
        Test-Path "$dest\CBS\CbsPersist_20261119.cab" | Should -BeTrue
        Test-Path "$dest\CBS\CbsPersist_20260101.cab" | Should -BeFalse
        Test-Path "$dest\DISM\dism.log" | Should -BeTrue
        Test-Path "$dest\CCM\WUAHandler-20261119-120000.log" | Should -BeTrue
        Test-Path "$dest\CCM\PolicyAgent.log" | Should -BeFalse
    }
    It 'copia CBS.log aberto para escrita pelo TrustedInstaller' {
        $fs = [IO.File]::Open("$win\Logs\CBS\CBS.log", 'Open', 'Write', 'ReadWrite')
        try { $r = Copy-OTSSServicingLogs -WindowsDir $win -Destination $dest -Days 30 -Now $now -MaxMB 2048 } finally { $fs.Dispose() }
        Test-Path "$dest\CBS\CBS.log" | Should -BeTrue
        $r.Pulados | Should -Be 0
    }
    It 'respeita o limite de tamanho e informa' {
        $r = Copy-OTSSServicingLogs -WindowsDir $win -Destination $dest -Days 30 -Now $now -MaxMB 0
        $r.Copiados | Should -Be 0
        $r.ForaDoLimite | Should -Be 6
    }
    It 'sem pastas de log: zero, sem erro' {
        $r = Copy-OTSSServicingLogs -WindowsDir "$TestDrive\naoexiste" -Destination $dest -Days 30 -Now $now -MaxMB 2048
        $r.Copiados | Should -Be 0
    }
}

Describe 'Get-OTSSPendingReboot' {
    It 'lista os motivos de reinicio pendente' {
        Mock Test-OTSSRegistryPath { $Path -like '*Component Based Servicing\RebootPending' } -ModuleName OTSS.Core
        Mock Get-OTSSPendingFileRename { $true } -ModuleName OTSS.Core
        $r = Get-OTSSPendingReboot -WindowsDir $TestDrive
        $r | Should -Contain 'CBS RebootPending'
        $r | Should -Contain 'PendingFileRenameOperations'
        $r | Should -Not -Contain 'WindowsUpdate RebootRequired'
    }
    It 'pending.xml do WinSxS' {
        Mock Test-OTSSRegistryPath { $false } -ModuleName OTSS.Core
        Mock Get-OTSSPendingFileRename { $false } -ModuleName OTSS.Core
        New-Item -ItemType Directory "$TestDrive\px\WinSxS" -Force | Out-Null
        'x' | Set-Content "$TestDrive\px\WinSxS\pending.xml"
        Get-OTSSPendingReboot -WindowsDir "$TestDrive\px" | Should -Be @('WinSxS\pending.xml')
    }
    It 'nada pendente: lista vazia' {
        Mock Test-OTSSRegistryPath { $false } -ModuleName OTSS.Core
        Mock Get-OTSSPendingFileRename { $false } -ModuleName OTSS.Core
        @(Get-OTSSPendingReboot -WindowsDir "$TestDrive\semnada").Count | Should -Be 0
    }
}

Describe 'New-OTSSAiGuide' {
    BeforeEach {
        $c = Join-Path $TestDrive ('col' + [guid]::NewGuid().ToString('N'))
        $sdp = New-Item -ItemType Directory "$c\SDP_Cluster\H_261125-115814_SDP_Cluster" -Force
        'x' | Set-Content "$sdp\H_evt_System.txt"
        'x' | Set-Content "$sdp\H_evt_Microsoft-Windows-FailoverClustering-Operational.txt"
        'x' | Set-Content "$sdp\H_SUMMARY.TXT"
        New-Item -ItemType Directory "$sdp\ClusterLogs", "$c\Servicing\CBS" -Force | Out-Null
        'x' | Set-Content "$sdp\ClusterLogs\cluster.log"
        'x' | Set-Content "$c\Servicing\CBS\CBS.log"
        'x' | Set-Content "$c\OTSS.log"
        $role = [pscustomobject]@{ Tipo = 'Cluster'; Cluster = 'CLUSTER01'; Nos = 6; HyperV = $true; S2D = $false; Motivo = @() }
        $fatos = [ordered]@{ 'Reinicio pendente' = 'CBS RebootPending'; 'MEMORY.DMP' = 'nao encontrado' }
        $p = New-OTSSAiGuide -Folder $c -Computer 'HOST01' -Role $role -OtssVersion '1.0.4' -TssVersion '2026.11.11.0' -Facts $fatos
        $txt = Get-Content -LiteralPath $p -Raw -Encoding UTF8
    }
    It 'cria LEIA-PRIMEIRO_IA.md na raiz da coleta' {
        $p | Should -Be (Join-Path $c 'LEIA-PRIMEIRO_IA.md')
    }
    It 'manda a IA perguntar o sintoma antes de analisar, com opcoes' {
        $txt | Should -Match 'ANTES de abrir qualquer outro arquivo'
        $txt | Should -Match 'Qual . o principal sintoma'
        foreach ($s in 'Tela azul', 'Lentid', 'Falha de atualiza', 'sai do cluster', 'M.quina virtual', 'Storage', 'Rede', 'Outro') { $txt | Should -Match $s }
    }
    It 'traz os fatos da coleta' {
        $txt | Should -Match 'HOST01'
        $txt | Should -Match 'CLUSTER01'
        $txt | Should -Match 'CBS RebootPending'
        $txt | Should -Match '1\.0\.4'
    }
    It 'lista arquivos presentes, abreviando a pasta do TSS como SDP/ e explicando a sigla' {
        $txt | Should -Match ([regex]::Escape('`SDP/` = `SDP_Cluster/H_261125-115814_SDP_Cluster/`'))
        $txt | Should -Match ([regex]::Escape('`SDP/H_evt_System.txt`'))
        $txt | Should -Match ([regex]::Escape('`SDP/ClusterLogs/cluster.log`'))
        $txt | Should -Match ([regex]::Escape('`Servicing/CBS/CBS.log`'))
        $txt | Should -Not -Match ([regex]::Escape('`SDP_Cluster/H_261125-115814_SDP_Cluster/H_evt_System.txt`'))
    }
    It 'relatorios de validacao: os 3 mais recentes primeiro' {
        $cr = New-Item -ItemType Directory "$c\SDP_Cluster\H_261125-115814_SDP_Cluster\ClusterReports" -Force
        foreach ($d in '2018.01.24', '2019.05.09', '2019.09.15', '2025.10.07', '2025.12.30') { 'x' | Set-Content "$cr\Validation Report $d At 10.00.00.htm" }
        $txt2 = Get-Content -LiteralPath (New-OTSSAiGuide -Folder $c -Computer 'H' -Role $role) -Raw -Encoding UTF8
        $linha = ($txt2 -split "`n" | Where-Object { $_ -match 'Validation Report' })
        $linha | Should -Match '2025\.12\.30.*2025\.10\.07.*2019\.09\.15'
        $linha | Should -Not -Match '2018\.01\.24'
    }
    It 'avisa que blg e evtx sao binarios' {
        $txt | Should -Match 'relog'
    }
    It 'reinicio inesperado: orienta a procurar erro de hardware do iLO (IML via HPE AMS) e reinicio sem dump' {
        $txt | Should -Match 'HPE Agentless Management Service'
        $txt | Should -Match 'Uncorrectable Machine Check'
        $txt | Should -Match 'sem BugCheck'
    }
    It 'falha de atualizacao: orienta a procurar corrupcao, sessao interrompida e etapas do CBS' {
        $txt | Should -Match '0x800f0831'
        $txt | Should -Match 'Session leak detected'
        $txt | Should -Match 'FLOW: Entering stage'
        $txt | Should -Match '1074'
    }
    It 'nao lista arquivo que nao existe na coleta' {
        $txt | Should -Not -Match 'Perfmon\.blg'
        $txt | Should -Not -Match 'Minidump/'
    }
}

Describe 'Get-OTSSCbsSummary' {
    BeforeEach {
        $cbs = New-Item -ItemType Directory (Join-Path $TestDrive ('cbs' + [guid]::NewGuid().ToString('N'))) -Force
        @(
            '2026-11-19 16:10:51, Error                 CBS    Error: Public CBS Session leak detected, SessionID: 31291470_3088694854, Client: WindowsUpdateAgent, Reference Count: 6 [HRESULT = 0x800f0909 - CBS_E_PUBLIC_OBJECT_LEAK]'
            '2026-11-19 16:10:51, Error                 CBS    Error: Public CBS Package leak detected, Owner SessionID: 31291480_1994523849'
        ) | Set-Content "$cbs\CbsPersist_20261119192654.log"
        @(
            '2026-11-19 16:27:45, Error                 CBS    Failed to resolve package ''Package_3782_for_KB5065427~31bf3856ad364e35~amd64~~10.0.1.10'' [HRESULT = 0x800f0831 - CBS_E_STORE_CORRUPTION]'
            '2026-11-19 16:27:46, Error                 CBS    Failed to resolve package ''Package_3783_for_KB5065427~31bf3856ad364e35~amd64~~10.0.1.10'' [HRESULT = 0x800f0831 - CBS_E_STORE_CORRUPTION]'
            '2026-11-19 16:28:00, Info                  CBS    linha normal'
        ) | Set-Content "$cbs\CbsPersist_20261119210937.log"
        'binario' | Set-Content "$cbs\CbsPersist_20261119.cab"
    }
    It 'conta corrupcao do repositorio e sessoes interrompidas, com a primeira ocorrencia' {
        $r = Get-OTSSCbsSummary -Folder $cbs
        $r.Corrupcao | Should -Be 2
        $r.PrimeiraCorrupcao | Should -Be '2026-11-19 16:27:45'
        $r.KBsCorrupcao | Should -Be @('KB5065427')
        $r.SessaoInterrompida | Should -Be 1
        $r.PrimeiraSessaoInterrompida | Should -Be '2026-11-19 16:10:51'
    }
    It 'texto de resumo para o log e para o guia' {
        (Get-OTSSCbsSummary -Folder $cbs).Texto | Should -Match '2 x 0x800f0831.*KB5065427.*2026-11-19 16:27:45.*1 sess'
    }
    It 'sem problemas' {
        $limpo = New-Item -ItemType Directory "$TestDrive\cbslimpo" -Force
        '2026-11-19 10:00:00, Info CBS ok' | Set-Content "$limpo\CBS.log"
        $r = Get-OTSSCbsSummary -Folder $limpo
        $r.Corrupcao | Should -Be 0
        $r.SessaoInterrompida | Should -Be 0
        $r.Texto | Should -Match 'sem sinais'
    }
    It 'pasta inexistente' { (Get-OTSSCbsSummary -Folder "$TestDrive\nada").Texto | Should -Match 'sem logs do CBS' }
}

Describe 'Get-OTSSTssAge' {
    It 'dias desde a versao do TSS' { Get-OTSSTssAge -TssVersion '2026.11.11.0' -Now ([datetime]'2026-11-25') | Should -Be 14 }
    It 'versao ilegivel: -1'         { Get-OTSSTssAge -TssVersion '?' -Now (Get-Date) | Should -Be -1 }
}

