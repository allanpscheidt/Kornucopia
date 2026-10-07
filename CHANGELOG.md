# Histórico de versões

## 1.0.3

- Verificação do proprietário, das permissões e das ACLs da pasta de dados antes de abrir arquivos.
- Recusa de links nos componentes de caminhos configurados e de pastas compartilhadas inseguras.
- Leitura, criação temporária, backup, substituição e preservação vinculados à pasta verificada nas duas plataformas.
- Arquivos novos recebem acesso restrito; objetos com permissões herdadas inseguras são recusados antes de receber conteúdo do quadro.
- Migração segura das permissões da pasta padrão antiga no Mac, com aviso e preservação do conteúdo.
- Aviso de pasta recusada nos cinco idiomas, sem tentar recuperar ou mover arquivos dessa pasta.

## 1.0.2

- Limites de arquivo, notas, texto, profundidade e trabalho de leitura antes de desserializar quadros no Mac e no Windows.
- Verificação de arquivo regular, recusa de links e leitura limitada para o principal e o backup.
- Preservação segura de entradas recusadas e recuperação por backup, com aviso ao usuário.
- Proteção para impedir que edições gerem quadros que o próprio app não consegue reabrir.
- Paginação de 100 notas por coluna no Windows, com busca em todo o quadro.
- Textos recusados permanecem no editor e podem ser copiados antes de fechar.
- Salvamento pausado quando outra sessão altera o arquivo principal.
- Leitura limitada e validação de recursos no arquivo de preferências do Windows.

## 1.0.1

- Tutorial prático em cada coluna, com orientação sobre o próximo passo no fluxo.
- Interface em português brasileiro, inglês, espanhol, francês e japonês.
- Seleção de idioma nas configurações, com preferência salva.
- Versão nativa para Windows 11, em x64 e ARM64, com armazenamento local.
- Descrição dos cartões como notas autoadesivas.

## 1.0.0

- App nativo para Mac Apple Silicon, com macOS 14 ou posterior.
- Quadro com Backlog, Fazendo, Revisão e Feito.
- Notas autoadesivas amarelas, azuis, roxas e verdes, com uma cor exclusiva por coluna.
- Limite inicial de dois cartões em Fazendo, ajustável nas configurações.
- Alerta que bloqueia a entrada de cartões acima do limite.
- Edição de título e anotações, busca e movimentação de cartões.
- Salvamento automático, backup local e recuperação da sessão.
- Ações para desfazer, refazer e reorganizar cartões.
- Ícone de cornucópia.
