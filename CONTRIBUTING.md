# Como contribuir

O Kornucopia concentra o trabalho em um quadro local de quatro colunas para Mac Apple Silicon. Alterações devem preservar essa simplicidade, o salvamento automático e a recuperação dos cartões.

## Relatar um problema

Abra uma issue com um título direto. Descreva o que você tentou fazer, o que esperava e o que aconteceu. Inclua a versão do app, a versão do macOS e os passos para reproduzir com cartões fictícios.

Capturas de tela ajudam quando o problema envolve a interface. Revise os dados visíveis antes de anexá-las. Para possíveis vulnerabilidades, siga a [política de segurança](SECURITY.md) e use um canal privado quando disponível.

## Propor uma alteração

Para mudanças maiores de interface ou de funcionamento, apresente a proposta em uma issue antes de começar. Explique a situação concreta que a mudança resolve e como ela afeta quem já usa o quadro.

Ao preparar um pull request:

1. Crie um fork e uma branch para a alteração.
2. Mantenha a mudança concentrada no problema descrito.
3. Compile o app e execute os testes na raiz do repositório.
4. Verifique no app as interações afetadas pela mudança.
5. Descreva o comportamento anterior, o resultado da alteração e a verificação realizada.

```sh
./scripts/build.sh
./scripts/test.sh
```

O desenvolvimento requer Mac Apple Silicon, Xcode ou Command Line Tools, Swift 6 e SDK macOS 26 ou posterior. Para testar a interface com um quadro separado, defina `KORNUCOPIA_DATA_DIR` com o caminho de uma pasta de teste antes de iniciar o executável.

## Cuidados com o quadro

- Preserve os identificadores, a ordem, os textos e as datas dos cartões ao alterar o armazenamento.
- Mantenha compatibilidade de leitura com os arquivos existentes ou descreva uma migração verificável.
- Teste o limite de Fazendo na criação, na edição e no movimento entre colunas.
- Preserve as cores exclusivas: amarelo no Backlog, azul em Fazendo, roxo em Revisão e verde em Feito.
- Verifique falhas de escrita e recuperação com dados fictícios.
- Diferencie testes do modelo de verificações da interface ao descrever os resultados.

A interface e a documentação usam português brasileiro. Prefira mensagens curtas, com ações concretas e informação suficiente para a pessoa decidir o próximo passo.
