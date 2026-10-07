# Kornucopia 1.0.1

Kornucopia organiza ideias e tarefas em um quadro de notas autoadesivas. A versão 1.0.1 acrescenta tutoriais nas quatro colunas e interface em português brasileiro, inglês, espanhol, francês e japonês.

- Backlog, Fazendo, Revisão e Feito apresentam orientações práticas para cada etapa.
- As notas acompanham a cor de sua coluna: amarelo, azul, roxo e verde.
- Fazendo começa com limite de dois cartões. Você pode ajustar o limite nas configurações. Ao atingir esse número, um alerta bloqueia a entrada de outra tarefa.
- A escolha de idioma permanece entre sessões. O texto que você escreve nos cartões conserva sua forma original.
- O app salva o quadro e as preferências no próprio computador, com recuperação por cópia do estado anterior.

## Downloads

| Computador | Arquivo | Requisito |
| --- | --- | --- |
| Mac com Apple Silicon | `Kornucopia-v1.0.1-macOS-arm64.zip` | M1 ou posterior, macOS 14 ou posterior |
| Windows x64 | `Kornucopia-1.0.1-windows-x64.zip` | Windows 11 |
| Windows ARM64 | `Kornucopia-1.0.1-windows-arm64.zip` | Windows 11 ARM64 |

Cada ZIP acompanha sua soma SHA-256: `SHA256SUMS.txt`, `SHA256SUMS-windows-x64.txt` ou `SHA256SUMS-windows-arm64.txt`. Extraia o pacote completo antes de abrir o aplicativo. No Windows, mantenha a pasta `Resources` junto de `Kornucopia.exe`. O runtime .NET já acompanha a distribuição, com seus avisos de licença.

## Verificação e limites

O CI compila os três pacotes, testa persistência, limite de WIP e traduções, confere a arquitetura dos executáveis e verifica os arquivos distribuídos. A verificação visual automatizada do Windows usa dados fictícios e captura apenas a janela WPF em um runner Windows Server. Essa evidência cobre a interface em cinco idiomas e os comandos exercitados pelo teste. A validação em um dispositivo físico com Windows 11 permanece pendente.

A distribuição inclui somente o aplicativo e seus recursos públicos. Quadros pessoais, backups e evidências de teste ficam fora dos seis arquivos de download. Os dados do usuário permanecem locais, em texto legível, com a proteção fornecida pelo sistema e pelos backups que você mantém.

O pacote Mac usa assinatura ad hoc, sem certificado Developer ID ou notarização da Apple. O pacote Windows atualmente não possui assinatura Authenticode. Os sistemas podem exibir avisos na primeira abertura. Confira a origem dos arquivos e mantenha as proteções gerais do computador ativas.

Os comandos padrão do macOS seguem o idioma do sistema. As configurações do Kornucopia traduzem os controles próprios do app, os alertas e os tutoriais.
