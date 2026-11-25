// OTSS.exe - Over Troubleshooting Script: iniciador da coleta com o TSS da Microsoft.
// Extrai os recursos embutidos para C:\temp\OTSS\_tss_<guid>, executa o Invoke-OTSS.ps1 no mesmo console
// e apaga a pasta no fim. TSS.zip e TSSVersion.txt so existem na montagem interna; o exe publico vem sem
// o TSS da Microsoft, e o script usa o TSS.zip da pasta do exe ou propoe o download de aka.ms/getTSS.
// Uso: OTSS.exe [/silencioso]   (/silencioso: sem pausa no fim e, sem TSS, baixa sem perguntar)
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

namespace OTSS
{
    internal static class Program
    {
        private const string OutputRoot = @"C:\temp\OTSS";
        private static readonly string[] Obrigatorios = { "Invoke-OTSS.ps1", "OTSS.Core.psm1" };
        private static readonly string[] Opcionais = { "TSS.zip", "TSSVersion.txt" };

        private static int Main(string[] args)
        {
            bool silencioso = false;
            foreach (string a in args)
            {
                string x = a.Trim().ToLowerInvariant();
                if (x == "/silencioso" || x == "-silencioso" || x == "/s") silencioso = true;
            }

            string workDir = Path.Combine(OutputRoot, "_tss_" + Guid.NewGuid().ToString("N"));
            try
            {
                Directory.CreateDirectory(workDir);
                Assembly asm = Assembly.GetExecutingAssembly();
                foreach (string nome in Obrigatorios)
                    if (!Extrair(asm, nome, workDir)) throw new InvalidOperationException("Recurso ausente no executavel: " + nome);
                foreach (string nome in Opcionais) Extrair(asm, nome, workDir);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("ERRO: nao foi possivel preparar a coleta em " + workDir + ": " + ex.Message);
                TentarApagar(workDir);
                if (!silencioso) Pausar();
                return 2;
            }

            try
            {
                Assembly asm = Assembly.GetExecutingAssembly();
                string otssVersion = asm.GetName().Version.ToString(3);
                // Sem barra no fim (ela escaparia a aspa do argumento); na raiz de um drive (E:\) vira E:\.
                string exeDir = Path.GetDirectoryName(asm.Location).TrimEnd('\\');
                if (exeDir.EndsWith(":")) exeDir += @"\.";
                string tssZip = Path.Combine(workDir, "TSS.zip");
                string verFile = Path.Combine(workDir, "TSSVersion.txt");
                string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                                         @"WindowsPowerShell\v1.0\powershell.exe");
                // O script sempre roda com -Silencioso; quem pausa no fim e o iniciador. Assim a janela
                // nao fecha sem aviso se o PowerShell falhar antes do script (GPO AllSigned, erro de carga).
                string argumentos = string.Format(
                    "-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -WorkDir \"{1}\" -ExeDir \"{2}\" -OtssVersion \"{3}\" -Silencioso",
                    Path.Combine(workDir, "Invoke-OTSS.ps1"), workDir, exeDir, otssVersion);
                if (File.Exists(tssZip)) argumentos += " -TssZip \"" + tssZip + "\"";
                if (File.Exists(verFile)) argumentos += " -TssVersion \"" + File.ReadAllText(verFile).Trim() + "\"";
                if (silencioso) argumentos += " -SemPergunta";

                ProcessStartInfo psi = new ProcessStartInfo(ps, argumentos);
                psi.UseShellExecute = false;
                int codigo;
                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit();
                    codigo = p.ExitCode;
                }
                if (codigo != 0 && codigo != 1 && codigo != 2)
                    Console.Error.WriteLine("ERRO: o PowerShell terminou com codigo inesperado " + codigo + ". Veja C:\\temp\\OTSS.");
                if (!silencioso) Pausar();
                return codigo;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("ERRO: falha ao executar a coleta: " + ex.Message);
                if (!silencioso) Pausar();
                return 2;
            }
            finally
            {
                TentarApagar(workDir);
            }
        }

        private static bool Extrair(Assembly asm, string nome, string destino)
        {
            using (Stream s = asm.GetManifestResourceStream(nome))
            {
                if (s == null) return false;
                using (FileStream f = File.Create(Path.Combine(destino, nome))) { s.CopyTo(f); }
                return true;
            }
        }

        private static void TentarApagar(string dir)
        {
            try { if (Directory.Exists(dir)) Directory.Delete(dir, true); } catch { }
        }

        private static void Pausar()
        {
            Console.WriteLine("Pressione Enter para fechar.");
            try { Console.ReadLine(); } catch { }
        }
    }
}
