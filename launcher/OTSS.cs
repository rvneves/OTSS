// OTSS.exe - Over Troubleshooting Script: iniciador da coleta offline do TSS.
// Extrai os recursos embutidos (TSS.zip, Invoke-OTSS.ps1, OTSS.Core.psm1, TSSVersion.txt) para
// C:\temp\OTSS\_tss_<guid>, executa o Invoke-OTSS.ps1 no mesmo console e apaga a pasta no fim.
// Uso: OTSS.exe [/silencioso]
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

namespace OTSS
{
    internal static class Program
    {
        private const string OutputRoot = @"C:\temp\OTSS";
        private static readonly string[] Recursos = { "TSS.zip", "Invoke-OTSS.ps1", "OTSS.Core.psm1", "TSSVersion.txt" };

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
                foreach (string nome in Recursos)
                {
                    using (Stream s = asm.GetManifestResourceStream(nome))
                    {
                        if (s == null) throw new InvalidOperationException("Recurso ausente no executavel: " + nome);
                        using (FileStream f = File.Create(Path.Combine(workDir, nome))) { s.CopyTo(f); }
                    }
                }
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
                string tssVersion = File.ReadAllText(Path.Combine(workDir, "TSSVersion.txt")).Trim();
                string otssVersion = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
                string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                                         @"WindowsPowerShell\v1.0\powershell.exe");
                // O script sempre roda com -Silencioso; quem pausa no fim e o iniciador. Assim a janela
                // nao fecha sem aviso se o PowerShell falhar antes do script (GPO AllSigned, erro de carga).
                string argumentos = string.Format(
                    "-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -TssZip \"{1}\" -WorkDir \"{2}\" -OtssVersion \"{3}\" -TssVersion \"{4}\" -Silencioso",
                    Path.Combine(workDir, "Invoke-OTSS.ps1"), Path.Combine(workDir, "TSS.zip"), workDir,
                    otssVersion, tssVersion);

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
