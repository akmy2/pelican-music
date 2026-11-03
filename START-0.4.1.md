# START 0.4.1

## Importação que não termina

- Cada música é adicionada e salva assim que termina, sem esperar o lote inteiro.
- O status mostra o arquivo e a etapa: examinar, copiar, verificar conteúdo ou validar áudio.
- A abertura de uma seleção/pasta tem limite de 20 segundos; o processamento de cada arquivo, 45 segundos.
- A leitura opcional de informações/capa tem limite de 3 segundos. Uma capa ou tag com problema não deve descartar áudio reproduzível.
- A importação pode ser cancelada; as músicas já adicionadas permanecem.
- Operações canceladas/tardias não podem publicar entradas em uma importação nova.
- A importação não varre previamente todos os áudios antigos para calcular hashes.

Arquivos grandes ou mantidos apenas na nuvem podem ultrapassar o limite de cópia. Nesse caso, baixe o arquivo no app Arquivos e selecione a cópia local. Arquivos inválidos ou protegidos ainda podem ser recusados; o app informa o nome e o erro.

## Capas automáticas pela web

A busca é ativada por padrão e tenta completar músicas sem capa ao abrir o app e depois de importar. Ela consulta o catálogo público do iTunes pelo título e artista. Nomes no formato “Artista - Música” também são considerados. Não é necessário cadastrar Client ID, fornecer chave ou conectar conta Apple.

As buscas são espaçadas, têm limite de espera e não bloqueiam a importação nem a reprodução. Capas existentes são preservadas. Resultados de músicas diferentes ou de vários artistas com o mesmo título não são escolhidos automaticamente. Sets e títulos ausentes do catálogo podem continuar com a capa ilustrativa.

Em Ajustes → Biblioteca é possível desativar a busca, consultar seu status ou tentar as capas ausentes novamente. A faixa e o player exibem o link da música no iTunes quando uma capa dessa fonte é aplicada.

Nome e artista são enviados ao catálogo quando a busca está ativa. Os arquivos de áudio não são enviados.

## Atualização

Assine o IPA e a extensão do widget pelo mesmo instalador e preserve o identificador da instalação anterior. Atualize sem apagar o app para manter a biblioteca. Confirme a correção no seu iPhone com os arquivos que estavam parando em “Preparando” ou “Lendo”.
