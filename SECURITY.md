# Segurança

## Dados locais

O Kornucopia guarda títulos e anotações em arquivos JSON com texto legível. No Mac, a pasta é `~/Library/Application Support/Kornucopia/`. No Windows, é `%LOCALAPPDATA%\Kornucopia\`. A proteção depende também da conta, das permissões e das medidas de segurança do sistema.

O app salva de forma atômica e mantém uma cópia do estado anterior para recuperação. Inclua a pasta de dados em seu backup habitual quando precisar manter versões antigas.

Use cartões fictícios para demonstrar problemas. Revise títulos, anotações e caminhos antes de anexar uma captura ou um diagnóstico a um relato público.

## Distribuição

Baixe os pacotes pela [página de releases](https://github.com/allanpscheidt/Kornucopia/releases). Confira a arquitetura do seu computador e a soma SHA-256 correspondente.

A versão Mac possui assinatura ad hoc local, sem Developer ID ou notarização. A versão Windows não possui assinatura Authenticode. As instruções de instalação ficam no [README](README.md#instalação). Preserve as proteções gerais do sistema ao avaliar avisos de primeira abertura.

O código público usa uma lista explícita de arquivos em `release-files.txt`. Dados de quadros, backups, credenciais e arquivos locais de teste ficam fora dessa lista. Os pacotes de distribuição passam por uma conferência de conteúdo e arquitetura antes da publicação.

## Relatar uma vulnerabilidade

Use [Security, Advisories, Report a vulnerability](https://github.com/allanpscheidt/Kornucopia/security/advisories/new) para enviar um relato privado aos responsáveis. Esse canal está habilitado no repositório. Consulte a [documentação do GitHub sobre reporte privado](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately) se precisar de orientação.

Inclua no relato:

- Versão do Kornucopia e versão do sistema operacional.
- Descrição do comportamento e do impacto observado.
- Passos para reprodução com dados fictícios.
- Arquivos mínimos para reproduzir o problema, quando necessário.
- Eventual sugestão de correção.

Use a versão mais recente disponível em Releases ao verificar se o problema continua presente. A avaliação considera as evidências do relato. A política e os testes do projeto não oferecem uma garantia absoluta de segurança.
