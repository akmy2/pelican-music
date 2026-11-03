# Pelican Music — iOS pessoal

Primeira versão nativa em SwiftUI, para iPhone/iPad com iOS 17 ou superior.

## O que está implementado

- Biblioteca local persistente; importação múltipla pelo app Arquivos.
- Reprodução offline, em segundo plano e com tela bloqueada via AVAudioSession.
- Play, pausa, anterior, próxima, avanço pela barra e AirPlay.
- Controles do sistema via MPRemoteCommandCenter; tratamento de interrupções e remoção de fones.
- Spotify: login OAuth com PKCE, validação de state, tokens no Keychain, renovação e comandos para o dispositivo ativo via Web API.
- Spotify: reprodução por link de faixa, álbum ou playlist, além de play/pausa/anterior/próxima.
- Configuração de compilação na nuvem para gerar IPA sem assinatura.

## Limites desta entrega

O código foi criado no Windows e **compilado com sucesso para iPhone pelo Xcode no GitHub Actions em 03/11/2026**. O IPA foi baixado e seu executável Mach-O, identificador e configuração de áudio em segundo plano foram conferidos. **Ainda não foi executado em um iPhone**; assinatura, instalação, reprodução e conexão Spotify precisam ser validadas no aparelho.

Build inicial: https://github.com/akmy2/pelican-music/actions/runs/41676179108

SoundCloud e YouTube têm apenas atalhos externos nesta versão. Não há login SoundCloud, streaming SoundCloud, busca remota, sincronização de playlists, player YouTube incorporado nem fila misturando serviços. A interface informa essas limitações. Não são conexões simuladas.

Spotify usa o dispositivo já ativo: abra o Spotify e reproduza uma música antes de usar os comandos. O áudio e seus controles de tela bloqueada ficam sob responsabilidade do Spotify. Não há SDK App Remote nesta versão nem ativação automática de dispositivo. O controle via Web API exige rede, Premium e permissões de acesso do app. O app não baixa arquivos do Spotify. Ao iniciar áudio local, o iOS pode interromper outro player; ao enviar play ao Spotify, o app libera a sessão local.

## Gerar IPA usando somente Windows

1. Crie um repositório privado no GitHub e envie os arquivos desta pasta, incluindo `.github/workflows/ios.yml`.
2. Na aba **Actions**, abra **Gerar IPA iOS** e clique **Run workflow**. O GitHub pode exigir habilitar Actions ou configurar cobrança conforme sua conta e cota.
3. Aguarde o build em macOS terminar. Em **Artifacts**, baixe **PelicanMusic-unsigned-IPA**.
4. Extraia o ZIP baixado. Dentro está `PelicanMusic-unsigned.ipa`.
5. Importe no seu instalador do iPhone. Ele precisa **assinar ou reassinar** o IPA com um certificado/perfil compatível. Um instalador que apenas instala IPAs já assinados não consegue usar este arquivo diretamente.

O fluxo gera um binário real para iPhone, sem assinatura. Ele não gera certificados, não publica na App Store e não instala o app sozinho. Não envie sua senha Apple, certificado ou chaves privadas para este repositório.

Se houver conflito de identificador no seu instalador, altere `PRODUCT_BUNDLE_IDENTIFIER` em `project.yml` e execute novamente o workflow.

## Conectar Spotify

1. Acesse https://developer.spotify.com/dashboard com sua conta.
2. Crie um app com acesso à Web API, conforme as opções disponíveis na sua conta.
3. Cadastre exatamente o Redirect URI `pelicanmusic://spotify-callback`.
4. Se o app estiver em modo de desenvolvimento, adicione sua conta em usuários autorizados, conforme as exigências do Dashboard.
5. Copie o **Client ID** para a aba **Conexões** do Pelican Music e toque **Conectar conta**. Não há Client Secret no app.
6. Abra o Spotify instalado no iPhone e inicie uma música. Volte ao Pelican Music para controlar a reprodução ou colar um link.

As regras de acesso e endpoints disponíveis dependem do Spotify. Uma conexão OAuth bem-sucedida não garante acesso a todos os recursos. Erros de dispositivo ativo, permissões e limites aparecem na interface.

## Teste no iPhone

- Importe dois arquivos de áudio válidos pelo app Arquivos.
- Reproduza, bloqueie a tela, espere uma faixa terminar e confirme a passagem para a próxima.
- Teste play/pausa, anterior/próxima e busca pela tela bloqueada e pelo app.
- Saia do app e confirme continuidade; force encerrar o app apenas quando quiser interromper sua execução.
- Teste interrupção por chamada e desconexão de fones.
- Feche e reabra o app; confirme que a biblioteca permanece.
- Apague uma música; confirme que ela saiu da biblioteca.
- Conecte o Spotify, ative o iPhone no Spotify e teste cada comando e links.
- Desconecte e reconecte o Spotify para conferir o fluxo de login.

## Compilar em um Mac

Instale Xcode e XcodeGen. Execute `xcodegen generate`, abra `PelicanMusic.xcodeproj`, selecione sua equipe de assinatura e rode no iPhone. O workflow usa o mesmo projeto gerado pelo arquivo `project.yml`.

## Documentação

- Spotify PKCE: https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow
- Spotify playback: https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback
- Áudio de fundo Apple: https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback
- SoundCloud: https://developers.soundcloud.com/docs
- YouTube: https://developers.google.com/youtube/terms/developer-policies-guide

Nenhum serviço externo foi cadastrado ou publicado automaticamente. O projeto não inclui músicas, credenciais nem dados de contas.
