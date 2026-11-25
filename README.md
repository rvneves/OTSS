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
| Qualidade | — | 99 testes automatizados (Pester) |

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

1. Baixe o `OTSS.exe` em [Releases](https://github.com/rvneves/OTSS/releases/latest) e copie para o servidor
   (pen drive, compartilhamento ou RDP).
2. **O TSS da Microsoft:** o exe público não traz o TSS (a licença da Microsoft não permite redistribuí-lo).
   - **Servidor com internet:** nada a fazer. Na primeira execução o OTSS pergunta
     *"Baixar agora de https://aka.ms/getTSS?"*; responda `S` e ele salva o `TSS.zip` ao lado do exe.
   - **Servidor sem internet:** em outra máquina, baixe **https://aka.ms/getTSS**, salve com o nome **`TSS.zip`**
     na **mesma pasta do `OTSS.exe`** e leve os dois juntos para o servidor.
3. Dê dois cliques no `OTSS.exe` e confirme o "Deseja permitir...?" (precisa ser administrador).
   Se aparecer **"O Windows protegeu o computador"** (SmartScreen), veja [o aviso do Windows](#aviso-do-windows-smartscreen).
4. Não precisa escolher nada. Aguarde de 20 a 30 minutos sem fechar a janela; o servidor pode ser usado normalmente.
5. Pegue o zip em `C:\temp\OTSS\<SERVIDOR>_<AAAAMMDD_HHMMSS>_<Cluster|HyperV|Setup>.zip`.
6. Para analisar com IA: entregue o zip e peça para começar pelo `LEIA-PRIMEIRO_IA.md`.

- Só lê informações: não altera discos, VMs nem o cluster.
- Precisa de 5 GB livres. Se o C: não tiver, o OTSS propõe salvar na unidade local com mais espaço
  (ex.: *"Salvar a coleta em F:\temp\OTSS (F: tem 54 GB livres)? [S/n]"*); com `/silencioso`, escolhe sozinho.
- Coleta só a máquina local; num cluster, rode em cada nó com problema.
- Sem janela de espera no fim (uso remoto ou agendado): `OTSS.exe /silencioso`. Nesse modo, sem `TSS.zip` ao lado,
  ele baixa o TSS sem perguntar.
- Códigos de saída: `0` concluído · `1` concluído com avisos (zip gerado) · `2` falha (ver `OTSS.log`).

| Máquina | Detecção | Coleta do TSS |
|---|---|---|
| Nó de cluster (com ou sem Hyper-V) | serviço `ClusSvc` rodando e `Get-Cluster` responde | `-SDP Cluster` (SDDC só se S2D estiver habilitado) |
| Host Hyper-V fora de cluster | serviço `vmms` presente | `-SDP Cluster -SkipSDPList skipBPA,skipSddc` |
| Outra | — | `-SDP Setup` |

### Aviso do Windows (SmartScreen)

O `OTSS.exe` ainda não tem assinatura digital. Por isso, ao abrir um exe baixado da internet, o Windows pode mostrar
**"O Windows protegeu o computador"**. Isso é esperado. Para rodar:

1. confira se o arquivo é o publicado: `(Get-FileHash .\OTSS.exe -Algorithm SHA256).Hash` deve ser igual ao
   conteúdo do `OTSS.exe.sha256` da Release;
2. clique em **"Mais informações"** e depois em **"Executar assim mesmo"**;
   ou, antes de abrir, botão direito no exe → **Propriedades** → marque **"Desbloquear"** → OK;
   ou, no PowerShell: `Unblock-File .\OTSS.exe`.

Copiado por pen drive ou compartilhamento interno, o aviso normalmente não aparece.

### Montar o executável

Requisitos: Windows com .NET Framework 4 (o `csc.exe` já vem no Windows) e PowerShell 5.1.

```powershell
# exe público, sem o TSS (o mesmo publicado em Releases):
powershell -ExecutionPolicy Bypass -File build\build.ps1 -Version 1.1.0 -SemTss
# exe para uso interno da sua organização, com o TSS embutido (baixa de aka.ms/getTSS):
powershell -ExecutionPolicy Bypass -File build\build.ps1 -Version 1.1.0
# ...ou com um TSS.zip já baixado:
powershell -ExecutionPolicy Bypass -File build\build.ps1 -Version 1.1.0 -TssZipPath C:\caminho\TSS.zip
```

Gera `dist\OTSS.exe` e `dist\OTSS.exe.sha256`. `-CertThumbprint` assina o exe, se houver certificado.
A licença do TSS permite uso interno: o exe com o TSS embutido não deve ser redistribuído fora da sua organização.
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
| Quality | — | 99 automated tests (Pester) |

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

1. Download `OTSS.exe` from [Releases](https://github.com/rvneves/OTSS/releases/latest) and copy it to the server
   (USB drive, file share or RDP).
2. **Microsoft's TSS:** the public exe does not include TSS (Microsoft's license does not allow redistributing it).
   - **Server with internet access:** nothing to do. On the first run OTSS asks
     *"Baixar agora de https://aka.ms/getTSS?"* (download now?); answer `S` and it saves `TSS.zip` next to the exe.
   - **Server without internet access:** on another machine, download **https://aka.ms/getTSS**, save it as
     **`TSS.zip`** in the **same folder as `OTSS.exe`** and take both files to the server.
3. Double-click `OTSS.exe` and accept the UAC prompt (administrator required).
   If **"Windows protected your PC"** (SmartScreen) shows up, see [the Windows warning](#windows-warning-smartscreen).
4. Nothing to choose. Wait 20 to 30 minutes without closing the window; the server stays usable.
5. Pick up the zip at `C:\temp\OTSS\<SERVER>_<YYYYMMDD_HHMMSS>_<Cluster|HyperV|Setup>.zip`.
6. To analyze with an AI: hand over the zip and ask it to start with `LEIA-PRIMEIRO_IA.md`.

- Read-only: it does not change disks, VMs or the cluster.
- Needs 5 GB free. If C: does not have it, OTSS offers to save on the local drive with the most free space
  (e.g. *"Salvar a coleta em F:\temp\OTSS (F: tem 54 GB livres)? [S/n]"*); with `/silencioso` it picks one itself.
- Collects the local machine only; on a cluster, run it on each affected node.
- No pause at the end (remote or scheduled use): `OTSS.exe /silencioso`. In this mode, with no `TSS.zip` next to
  it, it downloads TSS without asking.
- Exit codes: `0` done · `1` done with warnings (zip created) · `2` failed (see `OTSS.log`).

| Machine | Detection | TSS collection |
|---|---|---|
| Cluster node (with or without Hyper-V) | `ClusSvc` running and `Get-Cluster` answers | `-SDP Cluster` (SDDC only when S2D is enabled) |
| Standalone Hyper-V host | `vmms` service present | `-SDP Cluster -SkipSDPList skipBPA,skipSddc` |
| Other | — | `-SDP Setup` |

### Windows warning (SmartScreen)

`OTSS.exe` is not digitally signed yet, so when you open an exe downloaded from the internet Windows may show
**"Windows protected your PC"**. This is expected. To run it:

1. check the file is the published one: `(Get-FileHash .\OTSS.exe -Algorithm SHA256).Hash` must match the content
   of `OTSS.exe.sha256` in the Release;
2. click **"More info"** and then **"Run anyway"**;
   or, before opening it, right-click the exe → **Properties** → tick **"Unblock"** → OK;
   or, in PowerShell: `Unblock-File .\OTSS.exe`.

When copied by USB drive or internal file share, the warning usually does not appear.

### Building the executable

Requirements: Windows with .NET Framework 4 (`csc.exe` ships with Windows) and PowerShell 5.1.

```powershell
# public exe, without TSS (the one published in Releases):
powershell -ExecutionPolicy Bypass -File build\build.ps1 -Version 1.1.0 -SemTss
# exe for your organization's internal use, with TSS embedded (downloads from aka.ms/getTSS):
powershell -ExecutionPolicy Bypass -File build\build.ps1 -Version 1.1.0
# ...or with a TSS.zip you already downloaded:
powershell -ExecutionPolicy Bypass -File build\build.ps1 -Version 1.1.0 -TssZipPath C:\path\TSS.zip
```

It produces `dist\OTSS.exe` and `dist\OTSS.exe.sha256`. `-CertThumbprint` signs the exe when a certificate is
available. TSS's license allows internal use: do not redistribute the exe with TSS embedded outside your
organization. TSS refuses to run 90 days after its release date; OTSS passes `-noExpire`, but rebuild it periodically.

### Tests

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
Invoke-Pester tests
```

---

## Code signing policy

Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).

> **Status:** pedido ao SignPath Foundation em análise; as Releases atuais ainda não são assinadas. /
> application to SignPath Foundation under review; current Releases are not signed yet.

- O exe publicado em Releases é montado pelo GitHub Actions ([`.github/workflows/build.yml`](.github/workflows/build.yml))
  a partir deste repositório, com `build\build.ps1 -SemTss`. / The exe published in Releases is built by GitHub Actions
  from this repository with `build\build.ps1 -SemTss`.
- Committers and reviewers: [@rvneves](https://github.com/rvneves)
- Approvers: [@rvneves](https://github.com/rvneves)

### Privacidade / Privacy

This program will not transfer any information to other networked systems unless specifically requested by the user
or the person installing or operating it.

O OTSS só acessa a rede para baixar o TSS de `https://aka.ms/getTSS`, e apenas quando o usuário aceita (ou usa
`/silencioso`). A coleta fica na máquina, em `C:\temp\OTSS`; enviá-la a alguém é decisão de quem opera. /
OTSS only uses the network to download TSS from `https://aka.ms/getTSS`, and only when the user accepts it (or uses
`/silencioso`). The collection stays on the machine; sending it to anyone is the operator's decision.

## Créditos / Credits

- Ideia original da coleta simplificada / original idea of the simplified collection:
  [Fabiano Inacio — fginacio/MS](https://github.com/fginacio/MS).
- TSS: Microsoft ([aka.ms/getTSS](https://aka.ms/getTSS)), sob a licença da Microsoft / under Microsoft's license.
- OTSS: Roberto Neves, licença [MIT](LICENSE).
