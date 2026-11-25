BeforeAll {
    Import-Module "$PSScriptRoot\..\src\OTSS.Core.psm1" -Force
    $script = "$PSScriptRoot\..\src\Invoke-OTSS.ps1"
    $zip = Join-Path $TestDrive 'FakeTSS.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory("$PSScriptRoot\fixtures\FakeTSS", $zip)
    $out = Join-Path $TestDrive 'out'
    # WindowsDir falso: sem ele cada teste copiaria (e compactaria) os logs reais do CBS desta maquina
    $args0 = @{ TssZip = $zip; OutputRoot = $out; MinidumpPath = "$TestDrive\md"; MemoryDumpPath = "$TestDrive\M.DMP"; WindowsDir = "$TestDrive\semwindows"; Silencioso = $true }
}

Describe 'Invoke-OTSS.ps1' {
    BeforeEach {
        Mock Test-OTSSAdmin { $true } -ModuleName OTSS.Core
        Mock Get-OTSSFreeBytes { 50GB } -ModuleName OTSS.Core
        Mock Get-OTSSRole { [pscustomobject]@{ Tipo = 'Cluster'; Cluster = 'C1'; Nos = 2; HyperV = $true; S2D = $false; Motivo = @('teste') } } -ModuleName OTSS.Core
        # o script chama as funcoes do modulo pelo escopo dele: mocks tambem fora do modulo
        Mock Test-OTSSAdmin { $true }
        Mock Get-OTSSFreeBytes { 50GB }
        Mock Get-OTSSRole { [pscustomobject]@{ Tipo = 'Cluster'; Cluster = 'C1'; Nos = 2; HyperV = $true; S2D = $false; Motivo = @('teste') } }
        Mock Get-OTSSTssRegLogFolder { $null }
        Mock Get-OTSSBlockingProcess { @() } -ModuleName OTSS.Core
        Mock Get-OTSSPendingReboot { @() }
        Mock Export-OTSSEventLog { $true }
    }
    It 'guia para IA entra na pasta e no zip' {
        & $script @args0
        $pasta = Get-ChildItem $out -Directory | Where-Object Name -like '*_Cluster'
        Test-Path "$($pasta.FullName)\LEIA-PRIMEIRO_IA.md" | Should -BeTrue
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [IO.Compression.ZipFile]::OpenRead("$($pasta.FullName).zip")
        try { $z.Entries.FullName | Should -Contain 'LEIA-PRIMEIRO_IA.md' } finally { $z.Dispose() }
    }
    It 'logs de instalacao vao para Servicing e reinicio pendente para o OTSS.log' {
        $win = New-Item -ItemType Directory "$TestDrive\winT\Logs\CBS" -Force
        '2026-11-19 16:27:45, Error CBS Failed to resolve package ''Package_1_for_KB5065427~x'' [HRESULT = 0x800f0831 - CBS_E_STORE_CORRUPTION]' | Set-Content "$win\CBS.log"
        Mock Get-OTSSPendingReboot { @('CBS RebootPending', 'WinSxS\pending.xml') }
        $a = $args0.Clone(); $a.WindowsDir = "$TestDrive\winT"
        & $script @a
        $pasta = Get-ChildItem $out -Directory | Where-Object Name -like '*_Cluster'
        Test-Path "$($pasta.FullName)\Servicing\CBS\CBS.log" | Should -BeTrue
        $log = (Get-Content "$($pasta.FullName)\OTSS.log" -Encoding UTF8) -join "`n"
        $log | Should -Match 'AVISO: reinicio pendente: CBS RebootPending, WinSxS\\pending\.xml'
        $log | Should -Match 'logs de instalacao copiados: 1'
        $log | Should -Match 'AVISO: CBS: 1 x 0x800f0831'
        (Get-Content "$($pasta.FullName)\LEIA-PRIMEIRO_IA.md" -Raw -Encoding UTF8) | Should -Match '0x800f0831.*KB5065427'
        Should -Invoke Export-OTSSEventLog -ParameterFilter { $LogName -eq 'Setup' }
    }
    It 'arquivo preso fica fora do zip: codigo 1 e listado no OTSS.log' {
        Mock New-OTSSZip { param($Source, $Destination) Set-Content -LiteralPath $Destination 'zip'; @("$Source\SDP_Cluster\x_msinfo32.nfo") }
        & $script @args0
        $LASTEXITCODE | Should -Be 1
        $pasta = Get-ChildItem $out -Directory | Where-Object Name -like '*_Cluster'
        (Get-Content "$($pasta.FullName)\OTSS.log" -Encoding UTF8) -join "`n" | Should -Match 'AVISO: arquivo em uso.*msinfo32\.nfo'
    }
    AfterEach {
        Remove-Item Env:FAKE_TSS_ERRO, Env:FAKE_TSS_VAZIO, Env:FAKE_TSS_EXIT -ErrorAction SilentlyContinue
        Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'sucesso: pasta, zip, OTSS.log, argumentos certos, codigo 0' {
        & $script @args0
        $LASTEXITCODE | Should -Be 0
        $pasta = Get-ChildItem $out -Directory | Where-Object Name -like '*_Cluster'
        $pasta | Should -Not -BeNullOrEmpty
        Test-Path "$($pasta.FullName).zip" | Should -BeTrue
        Get-Content "$($pasta.FullName)\SDP_Cluster\args.txt" | Should -Match 'SDP=Cluster Skip=skipBPA,skipSddc Eula=True Xray=True Upd=True Ask=True Zip=True Exp=True Evt=30'
        (Get-Content "$($pasta.FullName)\OTSS.log" -Encoding UTF8) -join "`n" | Should -Match 'C1'
        Get-ChildItem $out -Directory -Filter '_tss_*' | Should -BeNullOrEmpty
    }
    It 'TSS com ERROR gera zip e codigo 1' {
        $env:FAKE_TSS_ERRO = '1'
        & $script @args0
        $LASTEXITCODE | Should -Be 1
        Get-ChildItem $out -Filter *.zip | Should -Not -BeNullOrEmpty
    }
    It 'TSS sem saida: sem zip e codigo 2' {
        $env:FAKE_TSS_VAZIO = '1'
        & $script @args0
        $LASTEXITCODE | Should -Be 2
        Get-ChildItem $out -Filter *.zip | Should -BeNullOrEmpty
    }
    It 'sem administrador: codigo 2 e nada criado' {
        Mock Test-OTSSAdmin { $false }
        & $script @args0
        $LASTEXITCODE | Should -Be 2
        Test-Path $out | Should -BeFalse
    }
    It 'pouco espaco: codigo 2' {
        Mock Get-OTSSFreeBytes { 1GB } -ModuleName OTSS.Core
        Mock Get-OTSSFreeBytes { 1GB }
        & $script @args0
        $LASTEXITCODE | Should -Be 2
    }
    It 'zip do TSS invalido: codigo 2, _tss_ apagado e erro no OTSS.log' {
        & $script -TssZip "$TestDrive\naoexiste.zip" -OutputRoot $out -MinidumpPath "$TestDrive\md" -MemoryDumpPath "$TestDrive\M.DMP" -Silencioso
        $LASTEXITCODE | Should -Be 2
        Get-ChildItem $out -Directory -Filter '_tss_*' | Should -BeNullOrEmpty
        $pasta = Get-ChildItem $out -Directory | Where-Object Name -like '*_Cluster'
        (Get-Content "$($pasta.FullName)\OTSS.log" -Encoding UTF8) -join "`n" | Should -Match 'ERRO'
    }
    It 'TSS que so gera logs proprios (transcript): sem zip e codigo 2' {
        $env:FAKE_TSS_VAZIO = '1'
        & $script @args0
        $LASTEXITCODE | Should -Be 2
        Get-ChildItem $out -Filter *.zip | Should -BeNullOrEmpty
    }
    It 'LogFolder no registro do TSS gera aviso no OTSS.log' {
        Mock Get-OTSSTssRegLogFolder { 'D:\outra\SDP_X' }
        & $script @args0
        $pasta = Get-ChildItem $out -Directory | Where-Object Name -like '*_Cluster'
        (Get-Content "$($pasta.FullName)\OTSS.log" -Encoding UTF8) -join "`n" | Should -Match ('AVISO.*' + [regex]::Escape('D:\outra\SDP_X'))
    }
    It 'registra a idade do TSS' {
        & $script @args0 -TssVersion '2026.11.11.0'
        $pasta = Get-ChildItem $out -Directory | Where-Object Name -like '*_Cluster'
        (Get-Content "$($pasta.FullName)\OTSS.log" -Encoding UTF8) -join "`n" | Should -Match 'TSS de 2026-11-11 \(\d+ dias\)'
    }
    It 'coleta anterior preservada' {
        New-Item -ItemType Directory "$out\ANTIGA" -Force | Out-Null
        & $script @args0
        Test-Path "$out\ANTIGA" | Should -BeTrue
    }
    It 'WorkDir do iniciador e respeitado e nao apagado pelo script' {
        $wd = New-Item -ItemType Directory "$TestDrive\wd_iniciador" -Force
        & $script @args0 -WorkDir $wd.FullName
        $LASTEXITCODE | Should -Be 0
        Test-Path $wd.FullName | Should -BeTrue
    }
}
