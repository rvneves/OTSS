BeforeAll {
    $raiz = Resolve-Path "$PSScriptRoot\.."
    # TSS real se ja estiver no cache do build; senao, um zip minimo com TSS.ps1 e a linha de versao
    $tssZip = Join-Path $raiz 'build\cache\TSS.zip'
    if (-not (Test-Path $tssZip)) {
        $fake = New-Item -ItemType Directory "$TestDrive\faketss" -Force
        '$global:TssVerDate = "2026.11.11.0"	# versao' | Set-Content "$fake\TSS.ps1"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $tssZip = Join-Path $TestDrive 'TSS.zip'
        [IO.Compression.ZipFile]::CreateFromDirectory($fake, $tssZip)
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$raiz\build\build.ps1" -TssZipPath $tssZip -OutDir "$TestDrive\dist" -Version '1.0.0' | Out-Null
    $exe = "$TestDrive\dist\OTSS.exe"
}

Describe 'build.ps1' {
    It 'gera exe e sha256 coerente' {
        Test-Path $exe | Should -BeTrue
        $h = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
        Get-Content "$TestDrive\dist\OTSS.exe.sha256" | Should -Be "$h  OTSS.exe"
    }
    It 'embute os quatro recursos e o TSS e identico' {
        $asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($exe))
        $asm.GetManifestResourceNames() | Sort-Object | Should -Be @('Invoke-OTSS.ps1', 'OTSS.Core.psm1', 'TSS.zip', 'TSSVersion.txt')
        $ms = New-Object IO.MemoryStream
        $asm.GetManifestResourceStream('TSS.zip').CopyTo($ms)
        $sha = [Security.Cryptography.SHA256]::Create().ComputeHash($ms.ToArray())
        ([BitConverter]::ToString($sha) -replace '-').ToLower() | Should -Be (Get-FileHash $tssZip -Algorithm SHA256).Hash.ToLower()
    }
    It 'versao do TSS lida do zip' {
        $asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($exe))
        (New-Object IO.StreamReader($asm.GetManifestResourceStream('TSSVersion.txt'))).ReadToEnd().Trim() | Should -Match '^\d{4}\.\d{1,2}\.\d{1,2}\.\d+$'
    }
    It 'versao do OTSS no executavel' {
        [Reflection.AssemblyName]::GetAssemblyName($exe).Version.ToString() | Should -Be '1.0.0.0'
    }
    It 'tem o icone do porquinho (rosa no centro)' {
        Add-Type -AssemblyName System.Drawing
        $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
        $bmp = $ico.ToBitmap()
        $px = $bmp.GetPixel([int]($bmp.Width / 2), [int]($bmp.Height / 2))
        ($px.R -gt 200 -and $px.G -gt 110 -and $px.G -lt 210 -and $px.B -gt 120 -and $px.B -lt 220) | Should -BeTrue -Because "pixel central $($px.R),$($px.G),$($px.B) deveria ser rosa"
    }
    It '-SemTss: exe publico so com os scripts, sem o TSS da Microsoft' {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$raiz\build\build.ps1" -SemTss -OutDir "$TestDrive\dist_pub" -Version '1.1.0' | Out-Null
        $pub = "$TestDrive\dist_pub\OTSS.exe"
        $asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($pub))
        $asm.GetManifestResourceNames() | Sort-Object | Should -Be @('Invoke-OTSS.ps1', 'OTSS.Core.psm1')
        (Get-Item $pub).Length | Should -BeLessThan 1MB
        Test-Path "$TestDrive\dist_pub\OTSS.exe.sha256" | Should -BeTrue
    }
    It 'manifesto pede administrador' {
        [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($exe)) | Should -Match 'requireAdministrator'
    }
}
