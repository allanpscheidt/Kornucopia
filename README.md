# Kornucopia

<img src="Resources/Cornucopia.png" width="140" alt="Ícone do Kornucopia: uma cornucópia">

Kornucopia é um Kanban nativo para Mac com cartões estilo post-it. Você organiza ideias, acompanha a produção e separa o que já concluiu em um quadro simples, com salvamento automático no próprio computador.

**[Baixar a versão mais recente](https://github.com/allanpscheidt/Kornucopia/releases/latest)**

## O quadro

Cada coluna tem sua própria cor. O cartão muda de cor quando você o move.

| Coluna | Uso | Cor |
| --- | --- | --- |
| Backlog | Ideias esperando para serem trabalhadas | Amarelo |
| Fazendo | Produção ativa | Azul |
| Revisão | Edição e feedback | Roxo |
| Feito | Trabalho concluído | Verde |

Backlog, Revisão e Feito aceitam cartões sem um limite artificial de quantidade. Cada coluna tem rolagem independente. A capacidade prática acompanha a memória e o armazenamento disponíveis no Mac.

Fazendo começa com espaço para **dois cartões ao mesmo tempo**. Esse limite de WIP, ou trabalho em progresso, ajuda a concentrar a produção. Ao atingir o número configurado, o app bloqueia a entrada de outro cartão e mostra um alerta. Você pode aumentar o limite em Configurações. Para reduzi-lo, o novo número precisa acomodar os cartões que já estão em Fazendo.

## Instalação

O app requer um **Mac com Apple Silicon, M1 ou posterior, e macOS 14 Sonoma ou posterior**. O pacote de distribuição contém o executável arm64.

1. Abra a [página de releases](https://github.com/allanpscheidt/Kornucopia/releases/latest) e baixe o arquivo ZIP para macOS arm64.
2. Abra o ZIP no Finder.
3. Copie `Kornucopia.app` para a pasta Aplicativos.
4. Abra o Kornucopia pela pasta Aplicativos.

A distribuição atual usa assinatura ad hoc local, sem certificado Developer ID ou notarização da Apple. O macOS pode bloquear a primeira abertura. Se você conferir a origem do download e decidir executar o app, siga o procedimento descrito pela Apple:

1. Tente abrir o Kornucopia e feche o aviso.
2. Abra Ajustes do Sistema e entre em Privacidade e Segurança.
3. Localize o aviso sobre o Kornucopia e escolha **Abrir Mesmo Assim**, quando essa opção estiver disponível.
4. Confirme a abertura na próxima janela.

Esse procedimento cria uma exceção para o app. Mantenha as proteções gerais do macOS ativas. Consulte as [orientações oficiais da Apple sobre abertura de apps](https://support.apple.com/pt-br/102445), especialmente se o aviso indicar software danificado ou capaz de causar danos.

## Como usar

- Clique em **Novo cartão** para adicionar uma ideia ao Backlog. O botão `+` de cada coluna cria um cartão nela, respeitando o limite de Fazendo.
- Clique no cartão para editar título e anotações. As alterações salvam automaticamente.
- Mova os cartões por arraste, pelo campo Coluna do editor ou pelo menu do botão direito.
- Use o menu do botão direito para colocar um cartão no início ou no fim da coluna.
- Busque palavras do título ou das anotações no campo de busca.
- Abra Configurações para renomear o quadro e ajustar o limite de Fazendo.
- Exclua cartões pelo editor ou pelo menu do botão direito. Desfazer permite recuperá-los durante a mesma execução do app.

| Atalho | Ação |
| --- | --- |
| `⌘N` | Criar cartão no Backlog |
| `⌘F` | Focar a busca |
| `⌘Z` | Desfazer |
| `⇧⌘Z` | Refazer |

O histórico guarda até 100 etapas durante a execução. Edições consecutivas de título e anotações do mesmo cartão se agrupam em uma etapa. Ao reabrir, o app restaura os cartões, o nome do quadro, o limite de Fazendo e a posição e o tamanho da janela. Se o editor estava aberto, ele retorna ao mesmo cartão quando esse cartão ainda existe.

## Salvamento e recuperação

Os cartões ficam em `~/Library/Application Support/Kornucopia/board.json`. Cada alteração grava um novo arquivo de forma atômica, substituindo o anterior após a escrita. `board.backup.json` guarda o estado imediatamente anterior.

Se o app encontrar um arquivo ilegível, ele tenta recuperar a cópia de segurança e mostra um aviso. Os arquivos que consegue preservar ficam na mesma pasta com `.corrupt-` no nome. Essa cópia automática guarda apenas um estado anterior. Para manter versões antigas, inclua a pasta de dados em seu backup habitual.

Uma falha de escrita aparece no app com a opção **Tentar salvar**. Os cartões continuam na memória enquanto ele permanece aberto. Ao encerrar com alterações pendentes, o Kornucopia oferece manter o app aberto para tentar novamente.

O quadro trabalha com arquivos locais. Esses arquivos contêm texto legível, sem criptografia própria do app. Consulte a [política de segurança](SECURITY.md) antes de relatar uma vulnerabilidade.

## Compilar, testar e empacotar

Para trabalhar no código, use um Mac Apple Silicon com Xcode ou Command Line Tools, compilador Swift 6 e SDK macOS 26 ou posterior. O SDK permite compilar os recursos de arraste mais recentes, enquanto o app mantém macOS 14 como versão mínima de execução. Execute os comandos na raiz do repositório:

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/package-release.sh
```

A compilação cria `build/Kornucopia.app`. O empacotamento produz o ZIP em `dist/`, com arquitetura e versão no nome, como `Kornucopia-v1.0.0-macOS-arm64.zip`. Os scripts usam as ferramentas de desenvolvimento do macOS.

Para compilar e instalar diretamente na pasta Aplicativos:

```sh
./scripts/build.sh --install
```

Os testes do modelo usam diretórios temporários. Eles verificam persistência, reordenação, WIP configurável, cores exclusivas, Desfazer/Refazer, recuperação de arquivos, falhas de escrita e um quadro com 1.201 cartões. A variável `KORNUCOPIA_DATA_DIR` permite escolher uma pasta isolada para testes da interface.

Veja [como contribuir](CONTRIBUTING.md) para relatar problemas ou propor alterações.
