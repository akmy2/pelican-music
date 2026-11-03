# START 0.4.0 — guia das 20 melhorias

Compilação para iPhone e sete testes automatizados aprovados no simulador: https://github.com/akmy2/pelican-music/actions/runs/41688781032 . O IPA foi baixado e verificado, incluindo o executável do widget, os tipos de documentos de áudio, a versão e os metadados de App Intents. A validação com a assinatura e o iPhone do usuário ainda é necessária.

Atualize o app com o mesmo identificador e assinatura da instalação anterior para preservar seus arquivos. Não desinstale a versão anterior antes de fazer backup dos áudios pelo app Arquivos.

| Melhoria | Onde usar |
| --- | --- |
| 1. Importação com validação, progresso e duplicatas | Início → Importar músicas. As falhas aparecem no relatório e podem ser tentadas novamente. A duplicação é verificada pelo conteúdo SHA-256, não apenas pelo nome. |
| 2. Título, artista, álbum e capa reais | Lidos dos metadados durante a importação. Arquivos antigos: Ajustes → Ler metadados ausentes. Se não houver capa no arquivo, uma ilustração é exibida. |
| 3. Busca | Biblioteca → campo de busca por nome, artista ou álbum. |
| 4. Playlists | Aba Playlists → +. Dentro da playlist, adicione músicas, renomeie ou use Editar para ordenar e remover faixas. |
| 5. Fila | Segure uma música → Tocar a seguir ou Adicionar à fila. Player → Fila → Editar para arrastar as faixas. |
| 6. Aleatório e repetição | Toque no player compacto para ampliar. Os botões de aleatório e repetição ficam junto aos controles. Repetição alterna desligada, lista e uma faixa. |
| 7. Player completo | Player compacto → toque no título. Inclui favorito, tempo restante, barra de busca, AirPlay e fila. |
| 8. Crossfade | Ajustes → Reprodução → Crossfade, de 0 a 12 segundos. Zero desativa. O fim de faixa programado e a repetição de uma faixa têm prioridade. |
| 9. Temporizador | Player ampliado → Dormir. Escolha minutos ou o fim da faixa. |
| 10. Personalização | Ajustes → Aparência. Cor de destaque, lista/grade e tamanho das capas na lista. |
| 11. Importar pastas | Início → Pastas ou Biblioteca → + → Importar pasta. As subpastas também são examinadas para formatos de áudio conhecidos. |
| 12. Compartilhar para START | App Arquivos → compartilhar/abrir áudio → START nas opções oferecidas pelo sistema. O app declara tipos de documentos de áudio e importa as URLs recebidas. A disponibilidade da opção depende do app de origem e do tipo de arquivo que ele fornece. |
| 13. Editar informações | Segure uma faixa → Editar informações. Nome, artista, álbum e imagem de capa são alterados na biblioteca; o áudio original não é reescrito. |
| 14. Histórico | Playlists → Histórico. Também aparece um resumo no Início. |
| 15. Retomar posição | Ajustes → Retomar a posição. A posição é salva durante a reprodução e ao pausar; ao reabrir o app, o player mostra a última faixa sem iniciar som automaticamente. |
| 16. Ordenação | Biblioteca → Organizar. Nome, artista, álbum, duração ou adição recente. |
| 17. Armazenamento | Ajustes → Armazenamento. Veja tamanho total, arquivos maiores e remova cópias do START. |
| 18. Backup | Ajustes → Exportar playlists e preferências. Restauração por JSON, com identificação por ID/conteúdo e opção para desfazer a última restauração. |
| 19. Modo carro | Ajustes → Abrir modo carro. Controles grandes e tela mantida acesa enquanto esse modo estiver aberto. É um modo visual do app, não integração CarPlay. |
| 20. Widgets e Atalhos | Adicione START na edição da Tela de Início. No app Atalhos, procure START para reproduzir, avançar e escolher uma playlist. Os comandos abrem o app para executar. |

## Backup

O JSON guarda playlists, favoritos, histórico, posições e preferências. Não inclui áudios, capas personalizadas ou credenciais de serviços. Copie seus áudios separadamente pelo app Arquivos. Para restaurar em outra instalação, importe primeiro os mesmos áudios; o START consegue associá-los pelo hash do conteúdo. Referências a músicas não encontradas não viram faixas fictícias.

## Widgets e assinatura

O IPA contém a extensão `com.pelican.music.widget`. Seu instalador precisa manter e assinar tanto o app quanto a extensão. Não há dependência de App Groups, push ou certificados especiais para compartilhar a biblioteca com o widget: ele funciona como acesso rápido por URL e abre o app. Ele não mostra a música atual de Spotify/SoundCloud nem oferece controle global de outros players.

## Reprodução e compatibilidade

Spotify continua usando a integração opcional já existente. Não há detecção automática de outros apps sem integração. SoundCloud e YouTube continuam como atalhos de origem. Não há sobreposição global ou Dynamic Island artificial.

Crossfade, áudio em segundo plano, compartilhamento, Siri/Atalhos, widget e instalação precisam ser conferidos no iPhone com sua assinatura. Testes no simulador não substituem essa validação. Arquivos incompletos, protegidos ou em formatos que o iOS não decodifica podem continuar sendo recusados; uma extensão `.mp3` não converte o conteúdo.
