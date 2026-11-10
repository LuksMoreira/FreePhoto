# FreePhoto — versão 1.2 com JPEG, PNG e salvamento no Fotos

App nativo em SwiftUI e AVFoundation para fotografar em DNG, JPEG ou PNG, escolher câmeras físicas e conferir a resolução realmente entregue. Nome provisório. Requer iPhone físico com iOS 17 ou posterior. Não usa REA: este é desenvolvimento de um app novo com APIs públicas.

## Estado da entrega

Configurações para build gratuito sem assinatura e teste de abertura no simulador estão incluídas. Veja [BUILD-GRATUITO.md](BUILD-GRATUITO.md). A execução na nuvem depende de conectar a conta/repositório e confirmar franquia gratuita disponível; ainda não foi executada.

Código-fonte e projeto Xcode preparados no Windows. **Ainda não compilado com o SDK da Apple nem testado no iPhone.** Não é um IPA instalável. A presença de uma API no código não comprova suporte no dispositivo. Compilar, testar RAW e validar o comportamento em cada lente são etapas pendentes.

Na versão 1.2, os três arquivos Swift passaram pela análise de sintaxe Tree-sitter, e a estrutura XML do projeto foi verificada no Windows. Isso não verifica tipos, disponibilidade de APIs, assinatura nem comportamento de câmera; essas validações dependem do Xcode e do aparelho.

## Resolução máxima e “sem processamento”

- **RAW Bayer:** salva o DNG que o iOS entrega, sem filtros, conversão ou edição do app. Solicita o maior tamanho anunciado de até 12,6 MP quando disponível, para evitar presumir suporte Bayer de 48 MP. Essa escolha conservadora não é uma afirmação de um limite universal da API. O sistema e o sensor ainda podem aplicar operações fora do controle do app.
- **ProRAW Max:** seleciona o maior tamanho de fotografia anunciado pelo dispositivo/formato. ProRAW contém processamento computacional da Apple; não é “sem processamento”. A resolução solicitada é um teto, não uma garantia de entrega.
- **JPEG:** foto processada e codificada pelo iOS, com compressão com perdas. Solicita o maior tamanho do formato ativo por padrão.
- **PNG:** foto processada pelo iOS, recebida em pixels BGRA sem compressão e codificada pelo app em PNG sRGB de 8 bits, sem JPEG intermediário ou redimensionamento. A codificação PNG é sem perdas, mas isso não significa ausência de processamento nem preservação de toda a profundidade de bits do sensor. Só fica disponível quando o output anuncia esse formato de pixels. A resolução do buffer entregue pode ser inferior ao teto pedido.
- Nenhum modo cai silenciosamente para JPEG/HEIF ou muda de RAW Bayer para ProRAW. Uma combinação sem suporte bloqueia o disparo e informa a indisponibilidade.
- A prévia é processada pelo sistema. Isso não representa uma edição do DNG salvo.
- Não há interpolação nem ampliação digital. O JSON acompanhante registra dimensões solicitadas e efetivamente entregues, modo, lente e quantidade de bytes.

No iPhone 16 Pro Max, a Apple especifica principal e ultra-angular de 48 MP, teleobjetiva 5× de 12 MP e frontal de 12 MP. O 2× é um recorte da principal; macro usa a ultra-angular. O LiDAR não é outra câmera colorida. A disponibilidade RAW deve ser verificada no iPhone e na versão de iOS em uso.

## O que a versão inclui

- Permissão de câmera e atalho para os Ajustes se negada.
- Descoberta dinâmica das câmeras físicas traseiras e de uma câmera colorida frontal, evitando duplicar a frontal TrueDepth/wide-angle.
- Seleção explícita da lente, sem troca automática por uma câmera virtual e sem zoom digital.
- Lista com identificação do dispositivo, abertura e máximo de foto anunciado.
- RAW Bayer e ProRAW, verificados ao selecionar cada combinação de lente/modo.
- Arquivo local no formato selecionado e relatório JSON; compartilhamento do original salvo. RAW permanece em DNG sem conversão automática.
- Salvamento automático de cada captura no Fotos, solicitando apenas autorização de adicionar. A importação usa o arquivo no formato selecionado.
- ISO e tempo de exposição manuais, aplicados juntos, com limites consultados no formato ativo e opção de exposição automática.
- Foco manual normalizado de 0 a 1, quando a câmera permite, e opção de foco automático.
- Temperatura (2000–15000 K) e matiz (−150 a +150), convertidos para ganhos RGB dentro dos limites do dispositivo, e opção de balanço automático. O app mostra a leitura efetiva após aplicar; os limites em Kelvin são uma escolha da interface, não uma garantia física.
- Seleção entre os tamanhos de foto anunciados pelo formato ativo, dentro do teto configurado. O tamanho solicitado pode diferir da entrega RAW.
- Abertura exibida como informação fixa, sem controle fictício de diafragma.
- Disparo bloqueado enquanto os ajustes manuais assíncronos são aplicados. As capacidades e os limites são recalculados e os controles voltam ao automático ao trocar lente ou formato.
- ISO, tempo e abertura retornados no EXIF registrados no JSON, quando presentes, separadamente do estado dos controles.
- Operação em retrato nesta versão.
- Tratamento de pausa, interrupções e erros básicos de sessão/captura.

Uma cópia de cada foto e seu JSON ficam em **Arquivos → No Meu iPhone → FreePhoto → Capturas**. Não há exclusão automática: monitore o espaço livre e exporte seus arquivos. Não há coleta de localização, servidor próprio ou dependência externa. Se o Fotos do iCloud estiver habilitado, o iOS pode sincronizar a biblioteca conforme as configurações do usuário.

## JPEG, PNG e Fotos

Escolha **JPEG** ou **PNG** junto aos modos RAW na tela principal e dispare. Na primeira captura, permita que o app adicione imagens ao Fotos. O salvamento é automático para todos os quatro modos, inclusive DNG; não é necessário usar o menu a cada disparo.

O disparo fica ocupado até concluir a gravação local e a tentativa de importação. Se a permissão for negada ou o Fotos retornar erro, a imagem local é preservada e a interface informa a falha. Conceda acesso nos Ajustes e use **Original → Tentar salvar no Fotos**. Após importação bem-sucedida, a ação é desabilitada para a última captura e não cria uma segunda cópia pela repetição do comando na mesma sessão. O compartilhamento continua disponível independentemente da permissão de Fotos.

PNGs de alta resolução podem exigir mais memória e espaço. Não há ampliação para simular uma resolução maior. O JSON informa as dimensões de pixels realmente recebidas/codificadas; a orientação é preservada nos metadados. JPEG e PNG são imagens reveladas/processadas, enquanto RAW Bayer preserva o caminho DNG.

## Como usar os controles

1. Selecione a lente e o formato (RAW Bayer, ProRAW, JPEG ou PNG) na tela principal.
2. Toque no ícone de controles (três barras) no canto superior.
3. Desative **Exposição automática** para ajustar ISO e obturador. O obturador usa escala logarítmica, adequada para tempos curtos e longos; a faixa vem da câmera, sem prometer exposições que ela não suporta.
4. Desative **Foco automático** para ajustar a posição da lente. Esse número não é uma distância em metros.
5. Desative **Balanço de branco automático** para ajustar Kelvin e matiz.
6. Escolha o teto de resolução e toque em **Aplicar**. Aguarde a aplicação antes de fechar o painel e disparar.

**Restaurar exposição, foco e balanço automáticos** altera o formulário; toque em **Aplicar** para confirmar. **Atualizar leituras da câmera** substitui os valores do formulário pela leitura atual e descarta alterações ainda não aplicadas. Em modo automático, os números são uma leitura pontual, não um monitor contínuo.

Para respeitar ISO e tempo manuais na fotografia, o app usa a prioridade `.speed`, conforme a documentação da Apple. Esse caminho pode reduzir a resolução entregue, inclusive em ProRAW; a prioridade é manter a exposição solicitada. Confira o EXIF e as dimensões reais no JSON, sem presumir 48 MP com qualquer exposição.

Em RAW Bayer, o balanço de branco pode ser interpretado pelo revelador RAW; ajustar os ganhos da câmera não equivale a aplicar uma edição destrutiva ao DNG. O processamento interno do sensor e o pipeline ProRAW continuam sujeitos ao iOS.

## Como compilar e instalar

O Windows pode editar e guardar este projeto. Para compilá-lo é necessário um ambiente macOS com Xcode e o SDK iOS, local ou remoto. Um site/PWA não oferece acesso equivalente a RAW e às câmeras físicas. Assinatura válida é necessária para instalar no iPhone; um build sem assinatura não é instalável.

Em um Mac com Xcode compatível com a versão de iOS do aparelho:

1. Abra `FreePhoto.xcodeproj`.
2. Em **Signing & Capabilities**, selecione sua equipe/Apple Account e altere `com.example.FreePhoto` para um identificador próprio.
3. Conecte o iPhone, confie no computador e habilite o Modo de Desenvolvedor quando solicitado.
4. Selecione o iPhone como destino e execute **Run**. O simulador não valida as câmeras nem RAW.

Para verificar a compilação sem assinatura no Mac, na pasta do projeto:

```sh
xcodebuild -project FreePhoto.xcodeproj -scheme FreePhoto \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

Isso só verifica a compilação; não cria um app instalável com assinatura. Sem Mac próprio, a próxima etapa é escolher um Mac remoto/serviço de build, executar a compilação e configurar a assinatura. Nenhuma conta foi criada, nenhum serviço pago foi contratado e nenhum código foi publicado.

## Validação pendente no iPhone 16 Pro Max

1. Compilar no Xcode e corrigir qualquer incompatibilidade do SDK instalado.
2. Testar permissão aceita/negada e retorno dos Ajustes.
3. Conferir principal, ultra-angular, teleobjetiva e frontal na lista; conferir que 2× e macro não aparecem como lentes extras.
4. Selecionar cada lente em cada modo. Confirmar que indisponibilidade bloqueia captura, sem substituição silenciosa.
5. Fotografar um alvo iluminado, conferir dimensões reais no JSON e com um leitor de DNG. Não assumir 48 MP a partir da seleção do modo.
6. Testar nitidez, foco e resolução em baixa luz; comparar RAW Bayer e ProRAW em um revelador RAW.
7. Conferir que DNG compartilhado e adicionado ao Fotos preserva o original, a orientação e os metadados. O app não gera JPEG acompanhante.
8. Testar interrupção por chamada, segundo plano/retorno, falta de espaço e disparos repetidos.
9. Em cada lente, testar ISO e obturador nos extremos da faixa. Comparar os valores escolhidos com o EXIF retornado; repetir em RAW Bayer e ProRAW.
10. Testar foco manual nos dois extremos e retorno ao automático. Confirmar que câmeras sem suporte mantêm o controle indisponível.
11. Testar Kelvin/matiz nos extremos. Confirmar ganhos dentro da faixa aceita, leitura após aplicar e retorno ao balanço automático.
12. Testar cada resolução anunciada e registrar o tamanho entregue. Trocar lente/formato após aplicar controles e conferir restauração dos modos automáticos.
13. Testar pausa/retorno enquanto aplica os ajustes e confirmar que o disparo só é liberado após conclusão.
14. Capturar JPEG e PNG em todas as lentes, conferir tipo real do arquivo, tamanho, orientação, cores e metadados. Validar a compatibilidade da configuração de pixels não comprimidos com as dimensões escolhidas no aparelho.
15. Confirmar que as quatro opções aparecem automaticamente no Fotos após autorizar. Negar permissão e conferir preservação da cópia local; conceder acesso nos Ajustes e tentar novamente pelo menu.
16. Verificar que o comando de tentar novamente não duplica uma captura já importada na sessão. Testar falha do Fotos e insuficiência de espaço durante captura/conversão de PNG.

## Fontes técnicas

- [Apple — especificações do iPhone 16 Pro Max](https://support.apple.com/en-us/121032)
- [Apple — captura RAW e Apple ProRAW](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats)
- [Apple — processamento parcial do ProRAW](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/isappleprorawenabled)
- [Apple — limite solicitado de dimensões](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxphotodimensions)
- [Apple — dimensões efetivamente entregues em RAW](https://developer.apple.com/documentation/avfoundation/avcaptureresolvedphotosettings/rawphotodimensions)
- [Apple — exposição manual e prioridade de captura](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setexposuremodecustom(duration:iso:completionhandler:))
- [Apple — foco manual](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setfocusmodelocked(lensposition:completionhandler:))
- [Apple — suporte a ganhos manuais de balanço de branco](https://developer.apple.com/documentation/avfoundation/avcapturedevice/islockingwhitebalancewithcustomdevicegainssupported)
- [Apple — criação de ativos do Fotos](https://developer.apple.com/documentation/photos/phassetcreationrequest/forasset())
- [Apple — formatos de pixels para captura processada](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/availablephotopixelformattypes)
