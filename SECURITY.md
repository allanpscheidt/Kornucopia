# Segurança

## Dados locais

O Kornucopia guarda títulos e anotações em arquivos JSON com texto legível. No Mac, a pasta é `~/Library/Application Support/Kornucopia/`. No Windows, é `%LOCALAPPDATA%\Kornucopia\`. A proteção depende também da conta, das permissões e das medidas de segurança do sistema.

O app salva de forma atômica e mantém uma cópia do estado anterior para recuperação. Inclua a pasta de dados em seu backup habitual quando precisar manter versões antigas.

Use cartões fictícios para demonstrar problemas. Revise títulos, anotações e caminhos antes de anexar uma captura ou um diagnóstico a um relato público.

## Proteção ao carregar quadros

A partir da versão 1.0.2, o app confere o tipo e o tamanho do arquivo principal e do backup antes de ler o conteúdo. A leitura limita a quantidade de bytes mesmo quando o arquivo cresce durante a operação. Links, arquivos especiais e aliases por hard link são recusados.

O orçamento compartilhado entre Mac e Windows permite 16 MiB de JSON, 10.000 notas e 8 MiB de texto UTF-8 somado. O nome do quadro aceita 1 KiB, cada título aceita 4 KiB e cada campo de anotações aceita 256 KiB. A varredura inicial limita o JSON a 32 níveis e 250.000 tokens. As mesmas regras valem antes de aceitar alterações no quadro.

Uma entrada recusada permanece preservada quando o app consegue movê-la com segurança para um nome `.corrupt-` na própria pasta de dados. O app tenta o backup e mostra um aviso recuperável. Se a preservação falhar, o salvamento fica pausado. Diretórios e arquivos especiais permanecem no lugar, sem leitura de conteúdo ou substituição. Um link nunca autoriza ler ou alterar seu alvo.

O Windows monta até 100 controles de cartões por coluna a cada página. A pesquisa percorre o conjunto aceito e oferece páginas dos resultados. Esses limites reduzem o custo de arquivos transferidos manualmente ou presentes em uma pasta configurada por `KORNUCOPIA_DATA_DIR`. A pasta de dados deve continuar sob controle do usuário, com as permissões do sistema.

O arquivo de preferências Windows também tem leitura limitada e verificação de arquivo regular. Seu orçamento é de 64 KiB, 8 níveis e 512 tokens JSON; a busca salva aceita 4 KiB UTF-8. O Mac usa UserDefaults para essas preferências.

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
