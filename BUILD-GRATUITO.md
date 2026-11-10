# Compilar o FreePhoto sem pagar pela assinatura Apple

Este pacote inclui fluxos prontos para compilação **sem assinatura**. Eles não publicam na App Store, não usam TestFlight e não precisam de certificados Apple.

## O que conseguimos validar

- Compilar o código Swift e suas chamadas ao SDK iOS em um Mac de CI.
- Gerar um `.app` sem assinatura para verificar o build de dispositivo.
- Compilar para simulador, instalar, abrir e registrar uma captura de tela. Isso valida apenas inicialização/interface, sem testar a câmera física, seus formatos, lentes ou resolução.

Um `.app` de dispositivo sem assinatura **não é instalável no iPhone**. A câmera precisa de testes em aparelho real depois.

## Opção 1 — Codemagic, conta individual com franquia gratuita

1. Envie **o conteúdo desta pasta**, incluindo `codemagic.yaml` e `scripts/`, para a raiz de um repositório privado seu.
2. Entre no Codemagic com sua conta individual e conecte esse repositório.
3. Confirme que a conta mostra os minutos gratuitos para **macOS M2** e que não há cobrança adicional habilitada para essa execução. Não selecione máquinas fora da franquia.
4. Adicione o app, selecione a configuração YAML e execute **freephoto-unsigned** para verificar a compilação.
5. Se passar, execute **freephoto-simulator** para validar abertura e gerar uma captura de tela.
6. Baixe os artefatos: logs, `.app.zip` e, no fluxo de simulador, `FreePhoto-simulator.png`.

Os fluxos não têm gatilhos automáticos, assinatura, publicação, cache ou serviços pagos adicionais. O limite de 20 minutos por execução ajuda a controlar uso, mas **não verifica o saldo gratuito nem impede sozinho cobranças da conta**. A franquia e a cobrança são controladas pelo provedor.

O Codemagic informa 500 minutos mensais gratuitos de macOS M2 para contas individuais elegíveis. Confira o saldo e os termos atuais na conta antes de executar: [preços](https://codemagic.io/pricing/), [guia iOS](https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app/).

## Opção 2 — GitHub Actions

O arquivo `.github/workflows/build-unsigned.yml` só executa pelo botão **Run workflow**. Não roda em push ou pull request.

Antes de iniciar, confira a franquia da conta para repositórios privados e mantenha bloqueada a cobrança de uso excedente, incluindo armazenamento de artefatos. No formulário, marque a confirmação apenas depois dessa conferência. O campo não consulta a cobrança automaticamente.

Escolha `device` para compilação sem assinatura ou `simulator` para compilação e teste de abertura. Cada job tem teto de 20 minutos e os artefatos expiram após um dia. Não há garantia de gratuidade se a franquia já acabou ou a cobrança excedente estiver habilitada. Não torne o código público apenas para obter execução gratuita sem decidir que quer publicá-lo.

[Regras de cobrança do GitHub Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

## Em um Mac disponível ou emprestado

Não precisa de CI. Na pasta do projeto:

```sh
bash scripts/build-unsigned.sh device
bash scripts/build-unsigned.sh simulator
```

Para testar a câmera sem uma assinatura anual Apple, abra o projeto no Xcode nesse Mac, selecione sua Personal Team e conecte o iPhone. A instalação pessoal fica sujeita aos prazos da conta gratuita da Apple.

## Se o build falhar

Envie o arquivo `build-device.log` ou `build-simulator.log`, ou traga o link da execução. Os scripts mantêm o código de erro real do `xcodebuild`; não transformam uma compilação com erros em sucesso. Ainda é necessário corrigir os erros reportados pelo SDK e repetir o build dentro da franquia.
