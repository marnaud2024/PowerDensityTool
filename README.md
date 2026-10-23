# Power Density Tool

Interface em MATLAB para estimar perdas, volume, rendimento e densidade de potência
(W/L) de um conversor CC-CC isolado. A ferramenta varre MOSFETs e diodos de SiC com
seus dissipadores, indutores de filtro e transformadores de alta frequência, e depois
combina os projetos viáveis de cada família num mapa de rendimento contra densidade.

Foi desenvolvida no GPEC/UFC e validada num conversor CC-CC isolado trifásico de 10 kW
com comutação suave. A teoria, com a dedução das equações, está em
[`docs/teoria/teoria_densidade.pdf`](docs/teoria/teoria_densidade.pdf).

## Como rodar

**No MATLAB** (Windows, macOS ou Linux), sem instalar nada:

```matlab
cd PowerDensityTool/src
PowerDensityApp
```

Testado no MATLAB R2023b. Não precisa de toolbox além do MATLAB base.

**No Windows, sem MATLAB:** baixe o `MyAppInstaller.exe` na
[página de Releases](https://github.com/marnaud2024/PowerDensityTool/releases) e
instale. O instalador baixa o MATLAB Runtime (gratuito), então precisa de internet. Para
atualizar, desinstale a versão anterior antes. A primeira abertura costuma levar alguns
minutos, e em algumas máquinas o programa empacotado não abre; nesse caso, use o
MATLAB.

## O que cada aba faz

| Aba | Modelo |
|---|---|
| MOSFET-I e MOSFET-II | Perdas de condução (Vdrop interpolado) e de comutação (Eon e Eoff dos modelos PLECS), com opção de ZVS. Dimensiona o dissipador de cada grupo. |
| Diode | Perda de condução do diodo SiC Schottky, com V_TO e R_d dependentes de Tj. |
| Dissipador (nas duas abas acima) | Cadeia térmica em regime permanente (Rjc, Rcs, Rha). Convecção natural e forçada pelas curvas de catálogo; as duas opções são geradas. |
| Inductor | Espiras com roll-off da permeabilidade, perda de núcleo por Steinmetz de cada material e permeabilidade, perda no cobre na temperatura do enrolamento, elevação de temperatura e volume. Núcleos de pó Magnetics e Magmattec. |
| Transformer | Espiras pela lei de Faraday com constante k informada, perda de núcleo pela GSE sobre a forma de onda real (grupos superior e inferior), rede neural para ferrites TDK, fator Fr de perda CA no cobre, perdas acopladas à temperatura do núcleo e volume com as camadas do enrolamento. |
| Power Density | Combina um projeto de cada família, aplica os multiplicadores e calcula perdas, volume, rendimento η = P_out/(P_out + perdas) e densidade P_out/volume. |

Nas abas de componente o eixo X é o volume e o Y são as perdas; o melhor projeto fica
perto da origem. O botão Calculate varre todo o catálogo; Filter / Plot restringe pelo
que está marcado nas árvores, e essa seleção é a que entra na combinação final.

## Valores padrão

Os campos abrem com os dados do conversor de referência (600 V de entrada, 920 V de
saída, 10 kW, 50 kHz):

- indutor: Vd = 300 V, corrente média 4,76 A, ripple de 1,5 A pico a pico, o que dá
  L = 1 mH;
- transformador: 600 V no primário, relação 1,2, 8 A RMS, k = 9, fio Litz AWG 38;
- Power Density: P_out = 10 kW e multiplicadores 1, 1, 1, 3 e 6 (MOSFET-I, MOSFET-II,
  diodo, indutor, transformador).

O ripple do indutor é em ampères (pico a pico) e é o mesmo valor usado no cálculo de L,
da corrente RMS e da excursão de fluxo. No transformador, o multiplicador é o número
total de transformadores, metade em cada ponte.

## Resultados

Cada aba grava o que calculou em `.xlsx` e `.csv`. Rodando no MATLAB, os arquivos vão
para `output/`; no programa instalado, para `Documentos\PowerDensityTool\output`. O
botão "Open results folder" da aba Power Density abre essa pasta.

## Estrutura

```
src/
  PowerDensityApp.m      janela principal (7 abas)
  build_installer.m      gera o instalador para Windows
  pdpwr_demo.m           verificação rápida sem abrir a interface
  +test/regression.m     bateria de testes
  +pdpwr/
    density.m            combinação e métricas
    +loss/               mosfet, diode, core, pcore_magmattec
    +design/             inductor, transformer, heatsink
    +util/               catálogo, modelos PLECS, rede neural, caminhos, exportação
    +ui/                 uma função por aba
data/                    Catalog.xlsx, modelos PLECS e pesos da rede neural
docs/                    teoria (LaTeX e PDF), THEORY.txt, DEVELOPER_GUIDE.txt
reference/               planilhas de onde saíram os coeficientes do catálogo
assets/                  logos
build/                   instruções do instalador
```

Todo o cálculo está no pacote `+pdpwr`, que pode ser usado sem a interface. O
[`docs/DEVELOPER_GUIDE.txt`](docs/DEVELOPER_GUIDE.txt) descreve o catálogo, as
estruturas de dados e os cuidados para estender o código.

## Testes

```matlab
cd src
test.regression          % espera "Total failures: 0"
```

São 16 testes. Além da leitura do catálogo e de valores calculados à mão para MOSFET,
diodo, dissipador e combinação, eles conferem o coeficiente k1 da GSE contra a definição
de Li (2001), a GSE do transformador contra uma integração independente do fluxo
montado pela lei de Faraday, a perda de núcleo das ferrites TDK e, no indutor, o Bpk e a
temperatura do cobre.

## Instalador

```matlab
cd src
build_installer          % gera build/setup/MyAppInstaller.exe
```

Precisa do MATLAB Compiler (`license('test','Compiler')` deve retornar 1). O instalador
gerado só serve para Windows; em macOS ou Linux, rode pelo MATLAB ou compile no próprio
sistema.

## Versões

**1.1 (outubro de 2026)**

- Indutor: ripple em ampères e o mesmo valor no L, na corrente RMS e no fluxo; Bpk como
  metade da excursão de fluxo; roll-off sem a dupla multiplicação por 100, que anulava
  a queda de permeabilidade; resistência do cobre na temperatura ambiente mais a
  elevação.
- Transformador: perda total pela GSE com o coeficiente k1 (antes somava o Steinmetz
  clássico e usava k no lugar de k1); cada trecho de B(t) integrado no seu intervalo de
  tempo, com integral em forma fechada; perdas acopladas à temperatura do núcleo com
  iteração convergente; fator Fr; perda de núcleo das ferrites TDK, que estava zerada;
  volume do toroide com as camadas do enrolamento; números de peça Magmattec no lugar de
  "R-Ae".
- Power Density: rendimento P_out/(P_out + perdas); multiplicadores em todas as
  famílias; o filtro de cada aba vale na combinação.

**1.0 (julho de 2026):** primeira versão pública.

Os resultados da versão 1.1 diferem dos da 1.0 no indutor e no transformador por causa
dessas correções.

## Créditos

GPEC, Universidade Federal do Ceará. Autores: Adolfo José M. F. Araújo, João Felipe X.
P. Lima, Davi C. Amorim, João Rodrigo Arnaud da Cruz, Samanta Gadelha Barbosa e
Demercil de S. Oliveira Júnior. Licença MIT (ver [`LICENSE`](LICENSE)).

Os modelos PLECS em `data/plecs_mosfets/` foram derivados dos datasheets da Wolfspeed e
da GeneSiC e continuam sendo dos fabricantes. Estão aqui só para permitir reproduzir os
resultados.
