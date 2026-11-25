<p align="center"><img src="assets/otss.png" width="128" alt="OTSS"></p>

# OTSS — Over Troubleshooting Script

**[Português](#português) · [English](#english)**

---

## Português

O OTSS é um **executável único** que roda o [TSS (Troubleshooting Script)](https://aka.ms/getTSS) da Microsoft
**sem internet**, descobre sozinho se a máquina é nó de cluster, host Hyper-V ou servidor comum, escolhe a melhor
coleta e entrega uma pasta e um zip em `C:\temp\OTSS`, prontos para análise, inclusive por uma IA.

Como um porquinho que fuça a lama atrás de comida, o OTSS fuça os logs atrás do erro.

### De onde veio

O OTSS parte da ideia dos scripts `TSSCollect.ps1` e `TSSv2Collect_Offline.ps1` de
**[Fabiano Inacio](https://github.com/fginacio/MS)**, que simplificam a coleta do TSS. O OTSS foi escrito do zero
sobre essa ideia e a leva adiante:

| | Scripts originais | OTSS |
|---|---|---|
| Entrega | Scripts PowerShell e menu | Um `OTSS.exe` com tudo embutido (pede administrador sozinho) |
| Escolha da coleta | O técnico marca se é cluster ou Hyper-V | Detecção automática: cluster, host Hyper-V ou servidor comum, sem perguntas |
| TSS atual | `-SDP HyperV`/`S2D`, que o TSS de 2026 aborta | `-SDP Cluster` (que já inclui Hyper-V); `-noExpire` contra a expiração de 90 dias |
| Compactação | Falha se algum arquivo estiver preso | Espera o `msinfo32`, compacta arquivo a arquivo, tolera arquivo em uso e caminho com mais de 260 caracteres |
| Logs de instalação | — | CBS, DISM, logs de atualização do SCCM e evento Setup, com resumo automático de corrupção do repositório de componentes (0x800f0831) e instalação interrompida |
| Telas azuis | — | Copia minidumps dos últimos 30 dias e informa o `MEMORY.DMP` |
| Análise | O técnico procura nos arquivos | Gera o `LEIA-PRIMEIRO_IA.md`, um roteiro para a IA (ver abaixo) |
| Qualidade | — | 81 testes automatizados (Pester) |

### Pronto para conversar com a IA

Toda coleta traz na raiz o **`LEIA-PRIMEIRO_IA.md`**, gerado para aquela máquina. Entregue o zip a uma IA e peça para
começar por ele. O arquivo instrui a IA a:

1. **perguntar primeiro qual é o sintoma** (tela azul ou reinício, lentidão, falha de atualização, nó saindo do
   cluster, VM, storage, rede ou outro) e quando aconteceu, antes de abrir qualquer log;
2. ler **primeiro os arquivos de maior afinidade** com o sintoma, só os que existem naquela coleta, com o que
   procurar em cada um (IDs de evento, palavras-chave, armadilhas conhecidas);
3. separar **constatado, deduzido e a confirmar**, citando arquivo e horário.

Também traz os fatos da coleta (papel detectado, reinício pendente, dumps, resumo do CBS) e avisos de leitura
(arquivos em UTF-16, binários, linhas de erro normais do TSS). Em campo, esse roteiro levou a IA direto a casos como
um repositório de componentes corrompido por reinício no meio de uma atualização e a reinícios causados por erro de
memória registrado pelo iLO.

### Uso

1. Copie o `OTSS.exe` para o servidor (pen drive, compartilhamento ou RDP).
2. Dê dois cliques e confirme o "Deseja permitir...?" (precisa ser administrador).
3. Não precisa escolher nada. Aguarde de 20 a 30 minutos sem fechar a janela; o servidor pode ser usado normalmente.
4. Pegue o zip em `C:\temp\OTSS\<SERVIDOR>_<AAAAMMDD_HHMMSS>_<Cluster|HyperV|Setup>.zip`.

- Só lê informações: não altera discos, VMs nem o cluster. Precisa de 5 GB livres em C:.
- Coleta só a máquina local; num cluster, rode em cada nó com problema.
- Sem janela de espera no fim (uso remoto ou agendado): `OTSS.exe /silencioso`.
- Códigos de saída: `0` concluído · `1` concluído com avisos (zip gerado) · `2` falha (ver `OTSS.log`).

| Máquina | Detecção | Coleta do TSS |
|---|---|---|
| Nó de cluster (com ou sem Hyper-V) | serviço `ClusSvc` rodando e `Get-Cluster` responde | `-SDP Cluster` (SDDC só se S2D estiver habilitado) |
| Host Hyper-V fora de cluster | serviço `vmms` presente | `-SDP Cluster -SkipSDPList skipBPA,skipSddc` |
| Outra | — | `-SDP Setup` |

### Montar o executável

O TSS da Microsoft **não** vem neste repositório. O script de build baixa a versão oficial e a embute no exe.
Requisitos: Windows com .NET Framework 4 (o `csc.exe` já vem no Windows) e PowerShell 5.1.

```powershell
powershell -ExecutionPolicy Bypass -File build\build.ps1 -Version 1.0.6
# ou com um TSS.zip já baixado (máquina sem internet):
powershell -ExecutionPolicy Bypass -File build\build.ps1 -Version 1.0.6 -TssZipPath C:\caminho\TSS.zip
```

Gera `dist\OTSS.exe` e `dist\OTSS.exe.sha256`. `-CertThumbprint` assina o exe, se houver certificado.
O TSS recusa rodar 90 dias após a versão dele; o OTSS usa `-noExpire`, mas remonte periodicamente.

### Testes

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
Invoke-Pester tests
```

### Estrutura

| Pasta | Conteúdo |
|---|---|
| `src/` | `Invoke-OTSS.ps1` (orquestração) e `OTSS.Core.psm1` (detecção, coleta, zip, CBS, guia para IA) |
| `launcher/` | Iniciador em C# que extrai os recursos embutidos e roda a coleta |
| `build/` | `build.ps1` |
| `tests/` | Testes Pester e um TSS falso para testes |
| `assets/` | Ícone |

---

## English

OTSS is a **single executable** that runs Microsoft's [TSS (Troubleshooting Script)](https://aka.ms/getTSS)
**offline**, works out on its own whether the machine is a cluster node, a Hyper-V host or a plain server, picks the
best collection and leaves a folder plus a zip in `C:\temp\OTSS`, ready for analysis, including by an AI.

Like a little pig rooting through the mud for food, OTSS roots through the logs for the error.

### Where it comes from

OTSS builds on the idea behind the `TSSCollect.ps1` and `TSSv2Collect_Offline.ps1` scripts by
**[Fabiano Inacio](https://github.com/fginacio/MS)**, which simplify TSS collection. OTSS was written from scratch on
top of that idea and takes it further:

| | Original scripts | OTSS |
|---|---|---|
| Delivery | PowerShell scripts and a menu | One `OTSS.exe` with everything embedded (requests elevation itself) |
| Choosing the collection | The technician selects cluster or Hyper-V | Automatic detection: cluster, Hyper-V host or plain server, no questions asked |
| Current TSS | `-SDP HyperV`/`S2D`, which the 2026 TSS aborts | `-SDP Cluster` (already covers Hyper-V); `-noExpire` against the 90-day expiry |
| Compression | Fails if any file is locked | Waits for `msinfo32`, zips file by file, tolerates locked files and paths over 260 characters |
| Servicing logs | — | CBS, DISM, SCCM update logs and the Setup event log, with an automatic summary of component store corruption (0x800f0831) and interrupted installs |
| Blue screens | — | Copies minidumps from the last 30 days and reports `MEMORY.DMP` |
| Analysis | The technician digs through the files | Generates `LEIA-PRIMEIRO_IA.md`, a script for the AI (see below) |
| Quality | — | 81 automated tests (Pester) |

### Ready to talk to an AI

Every collection has a **`LEIA-PRIMEIRO_IA.md`** ("read me first, AI") at its root, generated for that machine.
Hand the zip to an AI and ask it to start there. The file tells the AI to:

1. **ask for the main symptom first** (blue screen or reboot, slowness, update failure, node leaving the cluster,
   VM, storage, network or other) and when it happened, before opening any log;
2. read **the files most related to that symptom first**, listing only the files present in that collection and
   what to look for in each one (event IDs, keywords, known pitfalls);
3. separate **observed, inferred and to-be-confirmed**, citing file and time.

It also lists the collection facts (detected role, pending reboot, dumps, CBS summary) and reading notes (UTF-16
files, binary files, TSS error lines that are normal). In the field, this guide led the AI straight to cases such as
a component store corrupted by a reboot in the middle of an update, and reboots caused by a memory error logged by
iLO.

The guide and the console messages are in Portuguese.

### Usage

1. Copy `OTSS.exe` to the server (USB drive, file share or RDP).
2. Double-click it and accept the UAC prompt (administrator required).
3. Nothing to choose. Wait 20 to 30 minutes without closing the window; the server stays usable.
4. Pick up the zip at `C:\temp\OTSS\<SERVER>_<YYYYMMDD_HHMMSS>_<Cluster|HyperV|Setup>.zip`.

- Read-only: it does not change disks, VMs or the cluster. Needs 5 GB free on C:.
- Collects the local machine only; on a cluster, run it on each affected node.
- No pause at the end (remote or scheduled use): `OTSS.exe /silencioso`.
- Exit codes: `0` done · `1` done with warnings (zip created) · `2` failed (see `OTSS.log`).

| Machine | Detection | TSS collection |
|---|---|---|
| Cluster node (with or without Hyper-V) | `ClusSvc` running and `Get-Cluster` answers | `-SDP Cluster` (SDDC only when S2D is enabled) |
| Standalone Hyper-V host | `vmms` service present | `-SDP Cluster -SkipSDPList skipBPA,skipSddc` |
| Other | — | `-SDP Setup` |

### Building the executable

Microsoft's TSS is **not** included in this repository. The build script downloads the official release and embeds
it in the exe. Requirements: Windows with .NET Framework 4 (`csc.exe` ships with Windows) and PowerShell 5.1.

```powershell
powershell -ExecutionPolicy Bypass -File build\build.ps1 -Version 1.0.6
# or with a TSS.zip you already downloaded (offline machine):
powershell -ExecutionPolicy Bypass -File build\build.ps1 -Version 1.0.6 -TssZipPath C:\path\TSS.zip
```

It produces `dist\OTSS.exe` and `dist\OTSS.exe.sha256`. `-CertThumbprint` signs the exe when a certificate is
available. TSS refuses to run 90 days after its release date; OTSS passes `-noExpire`, but rebuild it periodically.

### Tests

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
Invoke-Pester tests
```

---

## Créditos / Credits

- Ideia original da coleta simplificada / original idea of the simplified collection:
  [Fabiano Inacio — fginacio/MS](https://github.com/fginacio/MS).
- TSS: Microsoft ([aka.ms/getTSS](https://aka.ms/getTSS)), sob a licença da Microsoft / under Microsoft's license.
- OTSS: Roberto Neves, licença [MIT](LICENSE).
