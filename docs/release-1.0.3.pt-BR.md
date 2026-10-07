# Kornucopia 1.0.3

A versão 1.0.3 reforça a proteção da pasta de dados. Um caminho configurado com links ou uma pasta acessível a outras contas recebe um aviso antes de o app abrir o quadro. Os arquivos permanecem no lugar.

- Verificação de proprietário, permissões e ACLs da pasta e dos componentes do caminho.
- Operações de leitura, backup, gravação e preservação vinculadas à pasta verificada.
- Recusa de links simbólicos e objetos reparse do Windows, incluindo junctions.
- Arquivos e pastas novos recebem acesso restrito; permissões herdadas inseguras impedem a gravação de conteúdo do quadro.
- No Mac, migração segura da pasta padrão antiga para acesso exclusivo da conta, com aviso e preservação dos quadros e backups.
- Avisos nos cinco idiomas. Pastas configuradas inseguras não recebem alterações automáticas de permissões.

Os limites de recursos da versão 1.0.2 continuam: até 16 MiB de JSON, 10.000 notas e 8 MiB de texto UTF-8 somado. No Windows, cada coluna mostra até 100 notas por página, com busca no quadro inteiro. O WIP continua ajustável nas configurações.

## Downloads

| Computador | Arquivo | Requisito |
| --- | --- | --- |
| Mac com Apple Silicon | `Kornucopia-v1.0.3-macOS-arm64.zip` | M1 ou posterior, macOS 14 ou posterior |
| Windows x64 | `Kornucopia-1.0.3-windows-x64.zip` | Windows 11 |
| Windows ARM64 | `Kornucopia-1.0.3-windows-arm64.zip` | Windows 11 ARM64 |

Cada ZIP acompanha sua soma SHA-256. Extraia o pacote completo antes de abrir. No Windows, mantenha `Resources` junto de `Kornucopia.exe`; o runtime .NET acompanha a distribuição.

## Verificação

Os testes usam dados fictícios para verificar a recusa de links, pastas compartilhadas, ACLs inseguras e alterações de caminho. Também conferem que a leitura, o backup, a recuperação e a substituição continuam funcionando em pastas privadas.

A revisão visual Windows usa a própria janela WPF em um runner Windows Server. A validação em dispositivo físico com Windows 11 permanece pendente. O pacote Mac usa assinatura ad hoc, sem Developer ID ou notarização da Apple; o pacote Windows não possui assinatura Authenticode.

Dados pessoais, backups, credenciais e evidências locais de teste ficam fora da distribuição. Consulte as [regras da pasta de dados](https://github.com/allanpscheidt/Kornucopia/blob/main/SECURITY.md#pasta-de-dados-como-limite-de-acesso) e as [instruções de recuperação](https://github.com/allanpscheidt/Kornucopia#salvamento-e-recuperação).
