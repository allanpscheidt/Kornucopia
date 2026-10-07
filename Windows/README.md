# Kornucopia para Windows

Aplicativo WPF nativo para Windows 11, em versões x64 e ARM64. A distribuição portátil contém o runtime .NET 10. O usuário abre `Kornucopia.exe` sem instalar .NET, servidor ou navegador. O executável usa os privilégios normais do usuário.

A interface acompanha o idioma do sistema, com escolha persistente em Configurações: português do Brasil, inglês, espanhol, francês ou japonês. Títulos e anotações dos cartões permanecem exatamente como o usuário os escreve. As quatro colunas têm orientações visíveis. Fazendo começa com limite de dois cartões; Configurações permite aumentá-lo.

Os dados ficam em `%LOCALAPPDATA%\Kornucopia`: `board.json`, `board.backup.json` e `preferences.json`. O formato do quadro conserva o esquema e os identificadores usados pelo app macOS. Datas numéricas usam a época de 1 de janeiro de 2001. A transferência entre plataformas é manual; o app não envia dados pela rede. Os arquivos locais não têm criptografia própria.

Na versão 1.0.3, cada coluna mostra até 100 notas por página. A busca considera todas as notas aceitas, inclusive as outras páginas. O carregamento confere arquivo regular, tamanho e orçamento do JSON antes de construir o quadro. O principal e o backup seguem os [limites compartilhados](../README.md#salvamento-e-recuperação). Arquivos recusados são preservados quando possível, e o app avisa sobre a recuperação. O editor conserva textos acima do orçamento e permite copiá-los antes de fechar.

A pasta de dados recebe verificação de proprietário, ACLs e componentes do caminho. Leituras, arquivos temporários, backups e substituições usam referências abertas à pasta verificada. Pastas inseguras ou caminhos com objetos reparse, incluindo junctions, são recusados antes de abrir seus arquivos. Use a pasta padrão ou uma pasta local privada da sua conta. Arquivos novos têm acesso restrito à conta atual e às contas administrativas do sistema. Consulte as [regras de acesso](../SECURITY.md#pasta-de-dados-como-limite-de-acesso).

O pacote não tem assinatura Authenticode. Windows e SmartScreen podem exibir avisos de editor desconhecido. A conferência do SHA-256 permite detectar alterações em relação ao arquivo publicado; o checksum não autentica a identidade do editor. Não desative proteções do Windows para abrir o app.

## Compilar

Requer SDK .NET 10. Os projetos não têm pacotes NuGet de terceiros. O SDK obtém os componentes oficiais .NET/WPF durante a restauração e a publicação.

```powershell
./Windows/build.ps1 -Runtime win-x64 -Test
./Windows/build.ps1 -Runtime win-arm64
```

Saída: `dist/windows/win-x64` ou `dist/windows/win-arm64`. Mantenha a pasta `Resources` junto ao executável. Ela contém os catálogos de idiomas e os avisos de licença originais do runtime .NET/WPF 10.0.12 redistribuído. Esses avisos se aplicam às dependências, sem definir uma licença para o código do Kornucopia. O app não precisa de acesso administrativo.

## Verificações

```powershell
dotnet run --project Windows/Tests/Kornucopia.Core.Tests.csproj -c Release
./dist/windows/win-x64/Kornucopia.exe --smoke-test ./qa/windows-smoke
```

O teste do modelo usa pastas temporárias. O teste visual abre a própria janela WPF com dados fictícios isolados, exerce campos nativos do editor e comandos de cartões, verifica WIP, gravação e reabertura, e gera cinco imagens da própria janela e `smoke-report.json`. O modo de teste não lê o quadro pessoal nem captura outras janelas. Gestos de mouse não são simulados. Uma execução no runner Windows do GitHub registra a versão efetiva do sistema; ela não equivale a uma revisão manual no Windows 11.
