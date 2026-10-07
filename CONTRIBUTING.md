# Como contribuir

O Kornucopia concentra o trabalho em um quadro local de quatro colunas para Mac Apple Silicon e Windows 11. Alterações devem preservar a simplicidade, o salvamento automático e a recuperação dos cartões.

## Relatar um problema

Abra uma issue com um título direto. Descreva o que você tentou fazer, o que esperava e o que aconteceu. Inclua a versão do app, o sistema operacional, o idioma escolhido e os passos para reproduzir com cartões fictícios.

Capturas ajudam a explicar problemas de interface. Revise os dados visíveis antes de anexá-las. Para vulnerabilidades, siga a [política de segurança](SECURITY.md) e use o canal privado.

## Preparar uma alteração

1. Crie um fork e uma branch para a alteração.
2. Mantenha a mudança concentrada no problema descrito.
3. Compile a plataforma afetada e execute os testes.
4. Confira no app as interações e os idiomas afetados.
5. Descreva o comportamento anterior, o resultado e a verificação realizada no pull request.

No Mac, use Apple Silicon, Xcode ou Command Line Tools, Swift 6 e SDK macOS 26 ou posterior:

```sh
./scripts/build.sh
./scripts/test.sh
```

No Windows, use o SDK .NET 10 e PowerShell:

```powershell
./Windows/build.ps1 -Runtime win-x64 -Test
./Windows/build.ps1 -Runtime win-arm64
```

Os testes do modelo também podem rodar em outros sistemas com o SDK .NET 10:

```sh
dotnet run --project Windows/Tests/Kornucopia.Core.Tests.csproj -c Release
```

Defina `KORNUCOPIA_DATA_DIR` para abrir o executável com uma pasta de dados isolada ao conferir a interface. Testes de interface usam apenas dados fictícios.

## Preservar o quadro

- Preserve identificadores, ordem, textos e datas dos cartões ao alterar o armazenamento.
- Mantenha compatibilidade com os arquivos existentes ou descreva uma migração verificável.
- Confira o limite de Fazendo na criação, na edição e no movimento entre colunas.
- Preserve as cores exclusivas: amarelo no Backlog, azul em Fazendo, roxo em Revisão e verde em Feito.
- Verifique falhas de escrita e recuperação com dados fictícios.
- Diferencie testes do modelo de verificações da interface ao relatar resultados.

## Traduções e publicação

A interface usa catálogos JSON com as mesmas chaves em português brasileiro, inglês, espanhol, francês e japonês. Preserve os marcadores como `{limit}` e `{count}` nas traduções. Use termos genéricos para as notas autoadesivas e instruções com ações concretas.

Adicione novos arquivos públicos a `release-files.txt` e rode `python3 scripts/audit-publication.py --check-index` após preparar os arquivos no Git. Quadros reais, backups, credenciais, capturas pessoais e pastas de compilação ficam fora do repositório.
