# Kornucopia 1.0.2

A versão 1.0.2 corrige o carregamento de quadros grandes que podiam consumir memória e processamento de forma excessiva a cada abertura. O Mac e o Windows verificam o arquivo principal e o backup antes da leitura completa e limitam a construção do quadro.

- Arquivo regular, sem links ou arquivos especiais, com até 16 MiB de JSON.
- Até 10.000 notas e 8 MiB de texto UTF-8 somado, com limites por campo e por estrutura do JSON.
- Entradas recusadas ficam preservadas para recuperação quando possível. O app tenta o backup e mostra um aviso; a preservação que falha pausa o salvamento.
- Edições seguem os mesmos limites do carregamento. O editor conserva o texto recusado e oferece copiar o rascunho antes de fechar.
- No Windows, cada coluna mostra até 100 notas por página. A busca inclui o quadro inteiro e a navegação mantém a ordem dos cartões.
- O salvamento pausa quando o arquivo principal muda fora da sessão, preservando essa outra versão.
- O arquivo de preferências Windows também recebe leitura limitada e validação de recursos, com até 64 KiB.

O WIP permanece separado dessa proteção de recursos: Fazendo começa com duas notas e permite ajustar o número nas configurações. Os tutoriais e a interface continuam em português brasileiro, inglês, espanhol, francês e japonês.

## Downloads

| Computador | Arquivo | Requisito |
| --- | --- | --- |
| Mac com Apple Silicon | `Kornucopia-v1.0.2-macOS-arm64.zip` | M1 ou posterior, macOS 14 ou posterior |
| Windows x64 | `Kornucopia-1.0.2-windows-x64.zip` | Windows 11 |
| Windows ARM64 | `Kornucopia-1.0.2-windows-arm64.zip` | Windows 11 ARM64 |

Cada ZIP acompanha sua soma SHA-256. Extraia o pacote completo antes de abrir. No Windows, mantenha `Resources` junto de `Kornucopia.exe`; o runtime .NET acompanha a distribuição.

## Verificação

Os testes usam quadros fictícios para exercitar arquivos acima do orçamento, limites de texto e notas, recuperação por backup, links, arquivos especiais e repetição da abertura. O teste WPF verifica a quantidade real de controles, navegação, busca global, edição e WIP em um quadro com milhares de notas.

A revisão visual Windows usa a própria janela WPF em um runner Windows Server. A validação em dispositivo físico com Windows 11 permanece pendente. O pacote Mac usa assinatura ad hoc, sem Developer ID ou notarização da Apple; o pacote Windows não possui assinatura Authenticode. Confira a origem dos arquivos e mantenha as proteções do sistema ativas.

Dados pessoais, backups, credenciais e evidências locais de teste ficam fora da distribuição. Consulte os [limites completos e as instruções de recuperação](https://github.com/allanpscheidt/Kornucopia#salvamento-e-recuperação).
