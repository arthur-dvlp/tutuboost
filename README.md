<div align="center">

# `TUTUBOOST`

**Otimizador de Windows para CS2 — simples, direto e 100% reversível.**

![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-00ff41?style=flat-square&labelColor=020a04)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-00ff41?style=flat-square&labelColor=020a04)
![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-00ff41?style=flat-square&labelColor=020a04)
![Grátis](https://img.shields.io/badge/pre%C3%A7o-gr%C3%A1tis-00ff41?style=flat-square&labelColor=020a04)

Sem instalação · Código aberto e legível · Feito no Brasil

</div>

---

## O que é

O TutuBoost aplica, com um clique, os ajustes de Windows que mais ajudam no CS2: energia, CPU, timer, GPU, mouse, rede, privacidade e visual. Cada mudança é anotada antes de ser feita, então dá para **desfazer tudo** e voltar exatamente ao que você tinha.

É um único script PowerShell. Sem instalador, sem servidor, sem conta, sem internet.

## Recursos

| Aba | O que faz |
|---|---|
| **Painel** | Resumo do PC (CPU, GPU, RAM, disco, Windows) e status das otimizações. |
| **Otimizações** | Cards com liga/desliga por módulo, busca e filtro por categoria. |
| **Experimental** | Ajustes de efeito não comprovado. Vêm desligados e você testa um de cada vez. |
| **Limpeza** | Temporários, caches e lixo do sistema, com seleção do que apagar. |
| **Restauração** | Ponto de restauração do Windows e **REVERTER TUDO**. |
| **Apps** | Remoção de apps pré-instalados que você escolher. |
| **Diagnóstico** | Verificação do PC com lembretes de BIOS (XMP/DOCP/EXPO, Above 4G, Resizable BAR). |

### Módulos de otimização

- **Energia:** plano de energia Máximo
- **CPU e prioridade de jogos**
- **Boot e kernel (timer)**
- **GPU e tela:** taxa de atualização máxima do monitor
- **Mouse e menus**
- **Rede**
- **Privacidade**
- **Notificações e sugestões**
- **Sistema** e **Visual do Windows**
- **Avançados, com aviso de risco:** desligar Isolamento de Núcleo e desligar o Defender em tempo real (desligados por padrão)

## Como usar

1. Baixe o último release e **extraia o .zip** numa pasta.
2. Dê dois cliques em **`Abrir_TutuBoost.bat`**.
3. Aceite o pedido de administrador. O programa precisa dele para mudar configurações do sistema.
4. Na aba **Restauração**, crie um **ponto de restauração** (recomendado).
5. Na aba **Otimizações**, clique em **MARCAR RECOMENDADOS** e depois em **OTIMIZAR TUDO**.
6. **Reinicie o PC** para tudo entrar em vigor.

> Para voltar ao estado original: **Restauração → REVERTER TUDO**.

## Segurança

- **Backup antes de alterar:** o valor original de cada chave, serviço e configuração é salvo em `backups\tutuboost_baseline.json`.
- **Reversão completa:** REVERTER TUDO restaura esses valores.
- **Nada de rede:** o programa não conecta à internet nem envia dados.
- **Código legível:** é um `.ps1` aberto. Leia antes de rodar, se quiser.
- **Itens de risco** ficam separados e desligados por padrão.

## Aviso do Windows SmartScreen / antivírus

Como é um programa novo e independente, o Windows pode mostrar *"O Windows protegeu seu computador"* ou o antivírus pode desconfiar, já que o TutuBoost altera configurações do sistema. Isso é esperado.

Para abrir mesmo assim: **Mais informações → Executar assim mesmo**.

Se preferir conferir o arquivo, compare o hash:

```powershell
Get-FileHash .\TutuBoost.ps1 -Algorithm SHA256
```

O SHA256 oficial de cada versão está na página do release.

## Requisitos

- Windows 10 ou 11 (64 bits)
- PowerShell 5.1 (já vem no Windows)
- Conta com permissão de administrador

## Dúvidas rápidas

**Vai estragar meu Windows?** Todas as mudanças são registradas e reversíveis. Mesmo assim, crie o ponto de restauração antes.

**Preciso reiniciar?** Sim, alguns ajustes (boot e kernel) só valem depois de reiniciar.

**Dá VAC ou ban?** O TutuBoost só altera configurações do Windows. Não toca no processo, na memória nem nos arquivos do jogo.

**Posso usar com o CSBoost ou outro programa?** Pode, mas aplicar ajustes duplicados não traz ganho extra.

## Aviso

Este programa altera configurações do Windows. Use por sua conta e risco. É fornecido "como está", sem garantia, conforme a licença MIT. O ganho de desempenho varia de PC para PC.

## Licença

[MIT](LICENSE) © 2026 — grátis para usar, modificar e redistribuir.

---

<div align="center">

Gostou? Deixe uma ⭐ no repositório.

</div>
