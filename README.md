# 🔐 Alerta de Senha - Active Directory
> Script PowerShell que consulta o Active Directory e envia e-mails automáticos para usuários com senha próxima do vencimento.

---

## 📋 Pré-requisitos

Antes de começar, verifique se o ambiente atende os seguintes requisitos:

| Requisito | Versão mínima | Como verificar |
|---|---|---|
| Windows Server | 2016 | `winver` |
| PowerShell | 5.1 | `$PSVersionTable.PSVersion` |
| Módulo ActiveDirectory | Qualquer | `Get-Module -ListAvailable ActiveDirectory` |
| Acesso SMTP | — | Confirmar com equipe de infra |

### Instalando o módulo ActiveDirectory (se não tiver)
```powershell
# Em Windows Server
Install-WindowsFeature RSAT-AD-PowerShell

# Em Windows 10/11
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

---

## 📁 Estrutura de arquivos

```
C:\Scripts\
│
├── Alerta-Senha-AD.ps1     ← Script principal
├── smtp_cred.xml           ← Credencial SMTP criptografada (gerada no passo 2)
│
C:\Logs\
└── AlertaSenha_YYYYMMDD.log  ← Logs gerados automaticamente a cada execução
```

---

## 🚀 Passo a Passo para Configurar

### 1. Copiar o script para o servidor

Coloque o arquivo `Alerta-Senha-AD.ps1` em:
```
C:\Scripts\Alerta-Senha-AD.ps1
```
> 💡 Se preferir outro caminho, lembre de atualizar o `$CredPath` e o `$LogPath` dentro do script.

---

### 2. Configurar as variáveis no script

Abra o arquivo `Alerta-Senha-AD.ps1` e edite o bloco de configurações no topo:

```powershell
$SMTPServer     = "smtp.suaempresa.com.br"   # Endereço do servidor SMTP
$SMTPPort       = 587                         # Porta (587 = TLS, 465 = SSL, 25 = sem criptografia)
$RemetenteEmail = "ti@suaempresa.com.br"      # E-mail remetente
$RemetenteNome  = "Suporte TI"                # Nome exibido no e-mail
$DiasAlerta     = @(14, 7, 3, 1)             # Dias de antecedência para avisar
$URLTrocaSenha  = "https://senha.suaempresa.com.br"  # Link do portal de troca
$RamalSuporte   = "1234"                      # Ramal do suporte
```

> ⚠️ **Office 365 / Microsoft 365?** Use `smtp.office365.com` na porta `587`.
> ⚠️ **Gmail corporativo (Workspace)?** Use `smtp.gmail.com` na porta `587`.

---

### 3. Gerar o arquivo de credencial SMTP

Para não deixar a senha exposta no script, execute **uma única vez** no servidor:

```powershell
Get-Credential | Export-Clixml "C:\Scripts\smtp_cred.xml"
```

Uma janela vai aparecer pedindo usuário e senha — insira as credenciais da conta de e-mail remetente. O arquivo gerado é criptografado e só pode ser lido pelo mesmo usuário/máquina que o criou.

> 🔒 **Importante:** Execute esse comando logado com a mesma conta de serviço que vai rodar o script no Task Scheduler.

---

### 4. Liberar a política de execução do PowerShell

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```

Confirme com `S` quando solicitado.

---

### 5. Testar manualmente

Antes de agendar, rode o script manualmente para validar:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Alerta-Senha-AD.ps1"
```

Verifique o log gerado em `C:\Logs\AlertaSenha_YYYYMMDD.log` e confirme se os e-mails chegaram corretamente.

---

### 6. Agendar a execução automática (Task Scheduler)

1. Abra o **Agendador de Tarefas** → `taskschd.msc`
2. Clique em **"Criar Tarefa"** (não "Tarefa Básica")
3. Configure as abas:

**Aba Geral:**
- Nome: `Alerta Senha AD`
- Marque: ✅ *Executar estando o usuário conectado ou não*
- Marque: ✅ *Executar com privilégios mais altos*
- Configurar para: `Windows Server 2016` (ou a versão do seu servidor)

**Aba Disparadores:**
- Novo → Diariamente → Horário: `08:00`

**Aba Ações:**
- Novo → Iniciar um programa
  - Programa: `powershell.exe`
  - Argumentos: `-NonInteractive -ExecutionPolicy Bypass -File "C:\Scripts\Alerta-Senha-AD.ps1"`

**Aba Condições:**
- Desmarque: ❌ *Iniciar a tarefa somente se o computador estiver com alimentação CA*

4. Clique em **OK** e informe as credenciais da conta de serviço.

---

## 📄 Entendendo os Logs

Cada execução gera um arquivo de log diário em `C:\Logs\`. Exemplo de saída:

```
2025-06-10 08:00:01 [INFO] ===== INICIO DA EXECUCAO =====
2025-06-10 08:00:02 [INFO] Politica de senha: 90 dias
2025-06-10 08:00:03 [INFO] Usuarios ativos encontrados para verificacao: 342
2025-06-10 08:00:04 [INFO] ENVIADO | joao.silva | joao.silva@empresa.com | 7 dias restantes
2025-06-10 08:00:05 [INFO] ENVIADO | maria.souza | maria.souza@empresa.com | 1 dias restantes
2025-06-10 08:00:06 [ERROR] ERRO ao enviar para carlos.lima (carlos.lima@empresa.com): ...
2025-06-10 08:00:07 [INFO] ===== EXECUCAO CONCLUIDA | Enviados: 2 | Erros: 1 =====
```

---

## ❓ Problemas Comuns

**O script roda mas não envia e-mails:**
- Verifique se o `$SMTPServer` e a porta estão corretos
- Confirme se o arquivo `smtp_cred.xml` foi criado com a mesma conta que executa o script
- Teste conectividade: `Test-NetConnection -ComputerName smtp.suaempresa.com.br -Port 587`

**Erro: "Cannot find module ActiveDirectory":**
- Instale o RSAT conforme indicado nos pré-requisitos

**Nenhum usuário encontrado:**
- Verifique se os usuários do AD têm o campo `EmailAddress` preenchido
- Teste manualmente: `Get-ADUser -Filter {Enabled -eq $true} -Properties EmailAddress | Select Name, EmailAddress`

**Senha expirada não aparece nos alertas:**
- Usuários com `PasswordNeverExpires = $true` são ignorados intencionalmente
- Verifique se o `PasswordLastSet` está preenchido no AD

---

## 🔧 Customizações Úteis

**Alterar os dias de alerta:**
```powershell
$DiasAlerta = @(30, 15, 7, 3, 1)  # Adicione ou remova dias conforme necessário
```

**Filtrar apenas uma OU (Unidade Organizacional) específica:**
```powershell
$Usuarios = Get-ADUser -Filter {Enabled -eq $true} -SearchBase "OU=Colaboradores,DC=empresa,DC=com" ...
```

**Excluir contas de serviço ou grupos específicos:**
```powershell
$Usuarios = $Usuarios | Where-Object { $_.SamAccountName -notlike "svc_*" }
```

---

## 📞 Suporte

Em caso de dúvidas ou problemas na configuração, contate a equipe de TI pelo ramal **1234** ou abra um chamado no portal de suporte.

---

*Projeto de Automação — Departamento de TI | v1.0 | 2025*
