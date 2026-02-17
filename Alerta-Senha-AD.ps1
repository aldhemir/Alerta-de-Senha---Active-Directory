# ============================================================
#  ALERTA DE SENHA - Active Directory Notification Script
#  Versao: 1.0  |  Autor: TI  |  Data: 2025
#  Descricao: Consulta o AD e envia e-mails automaticos para
#             usuarios com senha proxima do vencimento.
# ============================================================

Import-Module ActiveDirectory

# --- CONFIGURACOES ---
$SMTPServer     = "smtp.suaempresa.com.br"
$SMTPPort       = 587
$RemetenteEmail = "ti@suaempresa.com.br"
$RemetenteNome  = "Suporte TI"
$DiasAlerta     = @(14, 7, 3, 1)     # Avisar com X dias de antecedencia
$LogPath        = "C:\Logs\AlertaSenha_$(Get-Date -Format yyyyMMdd).log"
$URLTrocaSenha  = "https://senha.suaempresa.com.br"
$RamalSuporte   = "1234"

# --- CREDENCIAIS SMTP (seguro via SecureString) ---
# Para gerar o arquivo de credencial pela primeira vez, rode:
# Get-Credential | Export-Clixml "C:\Scripts\smtp_cred.xml"
$CredPath = "C:\Scripts\smtp_cred.xml"
if (Test-Path $CredPath) {
    $SMTPCredencial = Import-Clixml $CredPath
} else {
    Write-Warning "Arquivo de credencial SMTP nao encontrado: $CredPath"
    Write-Warning "Execute: Get-Credential | Export-Clixml '$CredPath'"
    exit 1
}

# --- FUNCAO: REGISTRO DE LOG ---
function Write-Log {
    param([string]$Mensagem, [string]$Nivel = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Linha = "$Timestamp [$Nivel] $Mensagem"
    $Linha | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host $Linha
}

# --- FUNCAO: TEMPLATE DE E-MAIL HTML ---
function Get-EmailHTML {
    param($NomeUsuario, $DiasRestantes, $DataExpiracao)

    $CorAlerta = switch ($DiasRestantes) {
        1       { "#C0392B" }  # Vermelho
        3       { "#E67E22" }  # Laranja
        default { "#2E75B6" }  # Azul
    }

    return @"
<!DOCTYPE html>
<html lang="pt-br">
<head><meta charset="UTF-8"></head>
<body style="font-family: Arial, sans-serif; background:#f4f4f4; padding:20px;">
  <div style="max-width:600px; margin:auto; background:#fff; border-radius:8px; overflow:hidden; box-shadow:0 2px 8px rgba(0,0,0,0.1);">

    <!-- Cabecalho -->
    <div style="background:#1F4E79; padding:24px; text-align:center;">
      <h2 style="color:#fff; margin:0;">⚠️ Aviso de Senha</h2>
      <p style="color:#BDD7EE; margin:8px 0 0;">Notificacao Automatica - Suporte TI</p>
    </div>

    <!-- Corpo -->
    <div style="padding:28px;">
      <p style="font-size:16px;">Olá, <strong>$NomeUsuario</strong>!</p>

      <div style="background:#FFF8E1; border-left:4px solid $CorAlerta; padding:16px; border-radius:4px; margin:16px 0;">
        <p style="margin:0; font-size:15px;">
          Sua senha corporativa expira em
          <strong style="color:$CorAlerta; font-size:18px;"> $DiasRestantes dia(s)</strong>,
          no dia <strong>$DataExpiracao</strong>.
        </p>
      </div>

      <p>Para evitar interrupcoes no acesso aos sistemas, troque sua senha antes dessa data.</p>

      <p><strong>Como trocar sua senha:</strong></p>
      <ul>
        <li>Pressione <strong>CTRL + ALT + DEL</strong> e selecione <em>"Alterar senha"</em></li>
        <li>Ou acesse o portal: <a href="$URLTrocaSenha" style="color:#2E75B6;">$URLTrocaSenha</a></li>
      </ul>

      <div style="background:#f0f0f0; padding:12px; border-radius:4px; margin-top:20px; font-size:13px; color:#666;">
        Em caso de duvidas, contate o Suporte TI pelo ramal <strong>$RamalSuporte</strong>
        ou responda este e-mail.
      </div>
    </div>

    <!-- Rodape -->
    <div style="background:#1F4E79; padding:12px; text-align:center;">
      <p style="color:#BDD7EE; font-size:12px; margin:0;">
        Esta e uma mensagem automatica. Por favor, nao a ignore.<br>
        Departamento de Tecnologia da Informacao
      </p>
    </div>

  </div>
</body>
</html>
"@
}

# --- FUNCAO: ENVIO DE E-MAIL ---
function Enviar-AlertaSenha {
    param($Usuario, $DiasRestantes, $DataExpiracao)

    $Email = $Usuario.EmailAddress
    $Nome  = if ($Usuario.GivenName) { $Usuario.GivenName } else { $Usuario.SamAccountName }

    $Assunto = "⚠️ Sua senha expira em $DiasRestantes dia(s) - Acao necessaria"
    $CorpoHTML = Get-EmailHTML -NomeUsuario $Nome -DiasRestantes $DiasRestantes -DataExpiracao $DataExpiracao

    try {
        Send-MailMessage `
            -SmtpServer $SMTPServer `
            -Port $SMTPPort `
            -UseSsl `
            -Credential $SMTPCredencial `
            -From "$RemetenteNome <$RemetenteEmail>" `
            -To $Email `
            -Subject $Assunto `
            -Body $CorpoHTML `
            -BodyAsHtml

        Write-Log "ENVIADO | $($Usuario.SamAccountName) | $Email | $DiasRestantes dias restantes"
        return $true
    }
    catch {
        Write-Log "ERRO ao enviar para $($Usuario.SamAccountName) ($Email): $_" "ERROR"
        return $false
    }
}

# ============================================================
# --- LOGICA PRINCIPAL ---
# ============================================================

Write-Log "===== INICIO DA EXECUCAO ====="

# Garante que o diretorio de log existe
$LogDir = Split-Path $LogPath
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

# Busca politica de senha do dominio
try {
    $MaxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.Days
    Write-Log "Politica de senha: $MaxPasswordAge dias"
}
catch {
    Write-Log "Erro ao obter politica de senha do dominio: $_" "ERROR"
    exit 1
}

# Busca todos os usuarios ativos com e-mail cadastrado
$Usuarios = Get-ADUser -Filter {
    Enabled -eq $true -and
    PasswordNeverExpires -eq $false
} -Properties DisplayName, GivenName, EmailAddress, PasswordLastSet, PasswordNeverExpires |
Where-Object { $_.EmailAddress -and $_.PasswordLastSet }

Write-Log "Usuarios ativos encontrados para verificacao: $($Usuarios.Count)"

$Enviados = 0
$Erros    = 0
$Hoje     = Get-Date

foreach ($User in $Usuarios) {
    $DataExpiracao  = $User.PasswordLastSet.AddDays($MaxPasswordAge)
    $DiasRestantes  = [math]::Floor(($DataExpiracao - $Hoje).TotalDays)

    if ($DiasRestantes -in $DiasAlerta) {
        $DataFormatada = $DataExpiracao.ToString("dd/MM/yyyy")
        $Resultado = Enviar-AlertaSenha -Usuario $User -DiasRestantes $DiasRestantes -DataExpiracao $DataFormatada

        if ($Resultado) { $Enviados++ } else { $Erros++ }
    }
}

Write-Log "===== EXECUCAO CONCLUIDA | Enviados: $Enviados | Erros: $Erros ====="

# ============================================================
# INSTRUCOES PARA AGENDAMENTO NO TASK SCHEDULER:
#
# 1. Abra o Task Scheduler (taskschd.msc)
# 2. Crie uma nova tarefa basica
# 3. Trigger: Diariamente as 08:00
# 4. Acao: powershell.exe
#    Argumentos: -NonInteractive -ExecutionPolicy Bypass -File "C:\Scripts\Alerta-Senha-AD.ps1"
# 5. Execute como conta de servico com permissao de leitura no AD
# ============================================================
