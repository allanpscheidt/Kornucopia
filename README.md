# Kornucopia

<img src="Resources/Cornucopia.png" width="140" alt="Ícone do Kornucopia: uma cornucópia">

Kornucopia organiza seu trabalho em um quadro Kanban com notas autoadesivas. Cada coluna ensina o próximo passo enquanto você registra ideias, produz, revisa e conclui. O app salva as alterações no próprio computador.

[English](docs/README.en.md) · [Español](docs/README.es.md) · [Français](docs/README.fr.md) · [日本語](docs/README.ja.md)

**[Baixar a versão mais recente](https://github.com/allanpscheidt/Kornucopia/releases/latest)**

## Versão 1.0.1

- Tutorial prático em cada coluna, com ações e orientação para avançar.
- Interface em português brasileiro, inglês, espanhol, francês e japonês.
- Escolha de idioma nas configurações, preservada entre sessões.
- Aplicativo para Mac com Apple Silicon e versão portátil para Windows 11, em x64 e ARM64.

A tradução muda a interface e os tutoriais. Seus títulos, anotações e nome do quadro permanecem como você os escreveu.

## O quadro

Cada coluna tem sua própria cor. O cartão muda de cor quando você o move.

| Coluna | O que fazer | Cor |
| --- | --- | --- |
| Backlog | Registre uma ideia e descreva a próxima ação. Espere uma vaga em Fazendo. | Amarelo |
| Fazendo | Trabalhe no que já começou. Termine uma etapa antes de começar outra ideia. | Azul |
| Revisão | Confira o resultado, corrija os detalhes e reúna feedback. | Roxo |
| Feito | Registre o trabalho concluído e o que você aprende com ele. | Verde |

Backlog, Revisão e Feito aceitam cartões sem um limite artificial de quantidade. Cada coluna tem rolagem independente. A capacidade prática acompanha a memória e o armazenamento disponíveis no computador.

Fazendo começa com espaço para **dois cartões ao mesmo tempo**. Esse limite de WIP, ou trabalho em progresso, ajuda a concentrar a produção. Ao atingir o número configurado, o app bloqueia a entrada de outro cartão e mostra um alerta. A ideia nova pode esperar no Backlog enquanto você termina algo e o move para Revisão.

Você pode aumentar o limite em Configurações. Para reduzi-lo, o novo número precisa acomodar os cartões que já estão em Fazendo. A regra vale na criação, no arraste e na mudança pelo editor.

## Instalação

Escolha o pacote que corresponde ao seu computador na [página de releases](https://github.com/allanpscheidt/Kornucopia/releases/latest).

| Computador | Pacote | Requisito |
| --- | --- | --- |
| Mac com Apple Silicon | `Kornucopia-v1.0.1-macOS-arm64.zip` | M1 ou posterior, macOS 14 ou posterior |
| PC com processador x64 | `Kornucopia-1.0.1-windows-x64.zip` | Windows 11 |
| PC com processador ARM64 | `Kornucopia-1.0.1-windows-arm64.zip` | Windows 11 ARM64 |

### Mac

1. Abra o ZIP no Finder.
2. Copie `Kornucopia.app` para a pasta Aplicativos.
3. Abra o Kornucopia pela pasta Aplicativos.

Os comandos padrão do macOS, como Fechar, seguem o idioma do sistema. A escolha nas configurações traduz os controles, alertas e tutoriais do Kornucopia.

O pacote usa assinatura ad hoc local, sem certificado Developer ID ou notarização da Apple. O macOS pode bloquear a primeira abertura. Se você conferir a origem e decidir executar o app, consulte as [orientações oficiais da Apple](https://support.apple.com/pt-br/102445). Elas explicam a opção **Abrir Mesmo Assim** em Ajustes do Sistema, Privacidade e Segurança. Mantenha as proteções gerais do sistema ativas.

### Windows

1. Extraia o ZIP completo para uma pasta de sua escolha.
2. Mantenha `Kornucopia.exe` e a pasta `Resources` juntos.
3. Abra `Kornucopia.exe`.

O pacote inclui o runtime necessário e funciona sem instalar o .NET separadamente. A distribuição atual não possui assinatura Authenticode. O Windows pode exibir um aviso sobre o editor. Confira a origem do download e preserve as proteções do sistema.

Cada pacote acompanha um arquivo `SHA256SUMS`. No Mac, use `shasum -a 256 -c SHA256SUMS.txt` na pasta do ZIP. No Windows, execute `Get-FileHash .\Kornucopia-1.0.1-windows-x64.zip -Algorithm SHA256` no PowerShell, ajustando o nome para ARM64 quando necessário. Compare o resultado com o arquivo de soma correspondente.

## Como usar

- Crie uma nota no Backlog e escreva uma ação concreta no título.
- Abra o cartão para editar o título e as anotações. O salvamento acompanha suas alterações.
- Leia o tutorial da coluna e avance conforme o trabalho muda de etapa.
- Mova os cartões por arraste ou pelo campo Coluna do editor.
- Busque palavras do título ou das anotações no campo de busca.
- Abra Configurações para escolher o idioma, renomear o quadro e ajustar o limite de Fazendo.
- Use Desfazer para recuperar uma alteração durante a mesma execução do app.

| Ação | Mac | Windows |
| --- | --- | --- |
| Criar cartão no Backlog | `⌘N` | `Ctrl+N` |
| Focar a busca | `⌘F` | `Ctrl+F` |
| Desfazer | `⌘Z` | `Ctrl+Z` |
| Refazer | `⇧⌘Z` | `Ctrl+Shift+Z` |

O histórico guarda até 100 etapas durante a execução. Ao reabrir, o app restaura os cartões, o nome do quadro, o idioma, o limite de Fazendo e a geometria da janela.

## Salvamento e recuperação

| Sistema | Pasta de dados |
| --- | --- |
| macOS | `~/Library/Application Support/Kornucopia/` |
| Windows | `%LOCALAPPDATA%\Kornucopia\` |

Cada alteração grava `board.json` de forma atômica. `board.backup.json` guarda o estado imediatamente anterior. Se o arquivo principal ficar ilegível, o app tenta recuperar a cópia e avisa você. Arquivos corrompidos que consegue preservar recebem `.corrupt-` no nome.

Uma falha de escrita aparece com a opção de tentar salvar novamente. Ao encerrar com alterações pendentes, o app oferece manter a sessão aberta. Para preservar versões antigas, inclua a pasta de dados em seu backup habitual.

Os arquivos contêm texto legível, sem criptografia própria do app. O app trabalha localmente, sem contas ou sincronização em nuvem. Consulte a [política de segurança](SECURITY.md) antes de relatar uma vulnerabilidade.

## Desenvolvimento

A versão Mac usa SwiftUI. A versão Windows usa WPF e .NET 10. Ambas usam os mesmos cinco catálogos de tradução em `Resources/Localization`.

Para compilar no Mac, use Apple Silicon, Swift 6 e SDK macOS 26 ou posterior. O app mantém macOS 14 como versão mínima de execução:

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/package-release.sh
```

A compilação cria `build/Kornucopia.app`. Para instalar em Aplicativos, execute `./scripts/build.sh --install`.

No Windows, use o SDK .NET 10 e PowerShell:

```powershell
./Windows/build.ps1 -Runtime win-x64 -Test
./Windows/build.ps1 -Runtime win-arm64
```

Os testes usam dados fictícios em pastas temporárias. A variável `KORNUCOPIA_DATA_DIR` permite abrir uma sessão isolada para conferir a interface. O fluxo de CI compila os pacotes, testa persistência e WIP, confere os catálogos e audita o conteúdo distribuído. A verificação da interface Windows em CI usa um runner Windows Server, conforme identificado no nome da etapa.

`release-files.txt` define os arquivos públicos permitidos. A auditoria rejeita arquivos fora dessa lista, caminhos pessoais e padrões de credenciais. Quadros, backups, arquivos de teste e pastas de compilação ficam fora do código publicado.

Veja [como contribuir](CONTRIBUTING.md).
