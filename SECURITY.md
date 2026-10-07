# Segurança

## Dados locais

O Kornucopia guarda o quadro em arquivos JSON na pasta `~/Library/Application Support/Kornucopia/`. Títulos e anotações ficam em texto legível. O app usa salvamento atômico e uma cópia do estado anterior para recuperação, mas a proteção desses arquivos depende também da conta, das permissões e das medidas de segurança do macOS.

Evite anexar seu quadro real a relatos públicos. Use cartões fictícios para demonstrar um problema. Antes de compartilhar uma captura de tela ou um arquivo de diagnóstico, revise os títulos, as anotações e os caminhos que aparecem nele.

## Distribuição

Baixe os pacotes pela [página de releases do repositório](https://github.com/allanpscheidt/Kornucopia/releases). A distribuição atual tem assinatura ad hoc local, sem certificado Developer ID ou notarização da Apple. Essas condições devem fazer parte da sua decisão de instalar.

As instruções de primeira abertura ficam no [README](README.md#instalação) e seguem a [documentação da Apple](https://support.apple.com/pt-br/102445). Preserve as proteções gerais do sistema. Se o macOS alertar sobre software danificado ou capaz de causar danos, consulte a orientação da Apple antes de continuar.

## Relatar uma vulnerabilidade

Quando o repositório habilitar o reporte privado de vulnerabilidades, use **Security → Advisories → Report a vulnerability** no GitHub. Esse canal permite enviar detalhes aos responsáveis pelo projeto sem publicá-los em uma issue. O GitHub explica o procedimento em sua [documentação de reporte privado](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately).

Se essa opção estiver indisponível, abra uma issue solicitando um canal privado. Informe apenas que deseja relatar uma possível vulnerabilidade. Aguarde a definição do canal antes de enviar instruções de exploração, arquivos sensíveis ou dados pessoais.

Inclua no relato privado:

- Versão do Kornucopia e versão do macOS.
- Descrição do comportamento e do impacto observado.
- Passos para reprodução com dados fictícios.
- Arquivos mínimos para reproduzir o problema, quando necessário.
- Eventual sugestão de correção.

A avaliação considera as evidências do relato. Use a versão mais recente disponível em Releases ao verificar se o problema continua presente. A existência desta política ou dos testes do projeto não oferece uma garantia absoluta de segurança.
