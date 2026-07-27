# Power Density Tool

Ferramenta desenvolvida no GPEC/UFC para estimar a densidade de potência (W/L) e o
rendimento (%) de um conversor CC–CC isolado. A ideia é simples: varrer combinações
de semicondutores de SiC, elementos magnéticos e dissipadores e encontrar o conjunto
com o melhor compromisso entre volume e perdas.

Cada família de componentes tem seu próprio gráfico de volume contra perdas, e a
última aba junta tudo para mostrar o diagrama de eficiência contra densidade. Todo o
cálculo fica num pacote MATLAB separado (`+pdpwr`), com uma bateria de testes, para
que qualquer pessoa consiga ler, reproduzir e melhorar o que está aqui. A teoria
completa, com a dedução de cada equação, está em
[`docs/teoria/teoria_densidade.pdf`](docs/teoria/teoria_densidade.pdf).

## 1. Como usar

Tem dois caminhos. Se você já tem o MATLAB, o segundo é o mais tranquilo.

### A) Instalador para Windows (não precisa de MATLAB)

Baixe o `MyAppInstaller.exe` na
[página de Releases](https://github.com/marnaud2024/PowerDensityTool/releases), rode
ele e siga o assistente — ele instala o programa junto com o MATLAB Runtime (gratuito,
mas precisa de internet na hora da instalação). Depois é só abrir pelo atalho que foi
criado.

Para atualizar, desinstale a versão anterior antes (Configurações → Aplicativos) e
só então rode o instalador novo.

Vale ser honesto sobre duas coisas: a primeira abertura depois de instalar costuma
demorar bastante, às vezes alguns minutos, porque o Runtime precisa descompactar os
dados. E em alguns computadores o programa empacotado simplesmente não abre — é uma
limitação do empacotamento do próprio MATLAB. Se isso acontecer com você, vá pelo
caminho B. Não existe um `.exe` avulso que rode sem instalar; é por isso que a pasta
`build/` traz só o instalador.

### B) Rodar direto no MATLAB (Windows, macOS ou Linux)

Quem tem MATLAB abre a interface na hora, sem instalar nada:

```matlab
cd PowerDensityTool/src
PowerDensityApp            % ou:  app = PowerDensityApp;
```

É o jeito que sempre funciona, e o único no macOS e no Linux sem ter que compilar.

O instalador da opção A é só para Windows. No Mac ou no Linux, ou você usa a opção B
(com MATLAB), ou compila no próprio sistema com `cd src; build_installer`, o que gera
um app nativo daquele sistema mais o Runtime correspondente. Não dá para pegar o
instalador de Windows e usar em outro sistema.

### Onde ficam as planilhas de resultado

Cada aba salva o que calculou em `.xlsx` e `.csv` (o CSV abre em Excel, LibreOffice,
Python, R, o que você preferir). Rodando pelo MATLAB, os arquivos vão para `output/`;
rodando pelo `.exe`, vão para `Documentos\PowerDensityTool\output`. Na aba Power
Density tem um botão "Open results folder" que abre essa pasta direto.

## 2. O que a ferramenta calcula

| Família | O que avalia |
|---|---|
| MOSFET-I / MOSFET-II | Perdas de condução e comutação (Eon/Eoff dos modelos PLECS) e dimensiona o dissipador. |
| Diodo | Perdas de condução (SiC Schottky, sem recuperação reversa) mais o dissipador. |
| Indutor | Projeto iterativo — espiras, roll-off de permeabilidade, perdas de núcleo e cobre, ΔT — em núcleos de pó Magnetics e Magmattec. |
| Transformador | Projeto por Faraday (com a constante `k` ajustável), Steinmetz ou rede neural, Ku e ΔT, em ferrites Magnetics, TDK e Magmattec. |
| Power Density | Combina um componente de cada família e calcula eficiência e densidade do conversor inteiro. |

Todos os semicondutores do catálogo são de SiC (Wolfspeed e GeneSiC). O gráfico
colore os pontos por material — já deixando espaço para Si e GaN no futuro — e mostra
o fabricante no datatip. Como o dissipador é o que domina o volume, o eixo usa o
volume do dissipador. Nas abas de componente, o eixo X é o volume e o Y são as
perdas, então o melhor ponto é o mais próximo da origem.

## 3. Passo a passo na interface

Nas abas de componente (os dois MOSFETs, o diodo, o indutor e o transformador), você
ajusta os parâmetros e clica em Calculate, que roda todas as possibilidades. Depois
marca o que interessa nas árvores (material, fabricante, encapsulamento, tipo de
convecção) e clica em Filter / Plot para refinar. Se o filtro não deixar nada, o
gráfico e a tabela são limpos.

Duas observações sobre as abas de magnéticos:

- O indutor e o transformador têm um dropdown "Show". "All designs" (o padrão) plota
  todos os projetos gerados; "Best per core" mostra só o melhor de cada núcleo. No
  modo "All", o gráfico é limitado a 15 mil pontos para não travar.
- No transformador, o campo "Faraday Constant (k)" é o `k` da equação
  `Np = Vd·1e4/(k·Bm·fs·Ae)`. Use 4 para onda quadrada, 4,44 para senoidal e 9 para o
  inversor de 3 níveis (que é o padrão).

Na aba Power Density, clique em Refresh cached counts, ajuste os multiplicadores,
escolha a vista e o modo de combinação, e clique em Calculate. Clicando numa linha da
tabela, o painel à direita mostra todos os detalhes construtivos daquela combinação.

### As duas vistas de análise

Nas duas, o eixo X é a eficiência (%), na mesma orientação do aplicativo original:

- Loss / Vol (padrão) — eficiência contra densidade de perdas (`TotalL/Vol`),
  reproduzindo o gráfico do app antigo. Os filtros são Max Total Losses e Max Loss
  Density.
- P_out / Vol — eficiência contra densidade de potência (`P_out/Vol`). Os filtros são
  Min Efficiency e Min Power Density.

O rendimento é `η = (P_out − perdas) / P_out`. O par de filtros que não está em uso
fica cinza.

### Quantas combinações testar

O dropdown Combinations tem três opções:

- Spread (fast), o padrão, pega 10 projetos por família espalhados pela faixa de
  perdas. Mantém a nuvem de trade-off inteira e é rápido.
- Top 10 best pega só os 10 de menor perda de cada família.
- All (slow) combina todos os projetos, até um milhão. Serve para achar um projeto
  específico, mesmo que ele esteja entre os piores. A interface avisa que é lento.

A exportação da aba salva os melhores resultados primeiro, limitados a 50 mil linhas,
para a planilha não ficar grande demais.

### Modelo de quantidade

A unidade de um semicondutor é um dissipador com os "Devices per HS" dies em cima
dele. A perda dessa unidade é a do conjunto (Q vezes a perda de um die), e o
multiplicador na aba de densidade é o número de braços do conversor. Por exemplo, um
dissipador com 2 MOSFETs em 4 braços dá multiplicador 4. Essa noção de quantidade só
existe na aba Power Density.

## 4. Organização das pastas

```
PowerDensityTool/
  README.md                  este guia
  LICENSE                    licença MIT
  build/                     (gerado por build_installer; o instalador é publicado nos Releases)
    READ_ME_FIRST.txt           instruções de instalação
  src/                       código-fonte
    PowerDensityApp.m           classe principal (monta as 7 abas)
    build_installer.m           gera o instalador num comando só
    pdpwr_demo.m                teste rápido de sanidade
    +test/regression.m          bateria de 12 testes
    +pdpwr/                     todo o cálculo, reaproveitável:
      density.m                   combinação 5-D e métricas
      +util/  load_catalog, data_root, output_dir, save_table, awg_props,
              plecs_load, plecs_load_body, load_neural_net
      +loss/  mosfet, diode, core, pcore_magmattec
      +design/ inductor, transformer, heatsink
      +ui/    layout, spinner_row, tab_mosfet, tab_diode,
              tab_inductor, tab_transformer, tab_density
  data/                      Catalog.xlsx, XMLs PLECS e a rede neural (.mat)
  assets/                    logos
  docs/
    teoria/                   relatório LaTeX da teoria (fonte + PDF)
    THEORY.txt               teoria em texto corrido
    DEVELOPER_GUIDE.txt      guia do back-end
  reference/                 planilhas-fonte dos coeficientes (Curve-Fit, Steinmetz)
  output/                    resultados gerados pelo app (vem vazia)
  PowerDensityApp.prj        projeto do deploytool (opcional, específico da máquina)
```

Todo o cálculo mora no pacote `+pdpwr`, usado pelo app, pelos testes e pelo
compilador — sem nenhum estado global. Os detalhes de implementação estão no
[`docs/DEVELOPER_GUIDE.txt`](docs/DEVELOPER_GUIDE.txt).

## 5. Para desenvolver (precisa de MATLAB)

```matlab
cd PowerDensityTool/src
app = PowerDensityApp;              % abre a janela com as 7 abas
```

Para rodar os testes:

```matlab
cd src
matlab -batch "test.regression"    % espera "Total failures: 0"
```

A bateria tem 12 testes e cobre a carga do catálogo, a tabela AWG, o Eon dos MOSFETs
GeneSiC e Wolfspeed, a perda de condução do diodo, o despacho por material do
Magmattec, o Bpk com `le`, o mapeamento dos coeficientes de Steinmetz, a
diferenciação do curve-fit por material, a combinação de densidade, a cadeia térmica
do dissipador e a constante de Faraday.

Para regerar o instalador depois de mexer no código:

```matlab
cd src
build_installer            % gera build/setup/MyAppInstaller.exe
```

O script apaga a build anterior e limpa os intermediários, deixando só o instalador.
Existe também `build_installer('included')`, que embute o Runtime e gera um instalador
offline (~2–4 GB), mas o download do Runtime é lento e quase nunca compensa; use a
versão padrão ('web'). Se preferir a interface gráfica, dá para usar o `deploytool`.

Para compilar você precisa do MATLAB Compiler (`license('test','Compiler')` deve
retornar 1). Foi tudo testado no MATLAB R2023b, no Windows. O `.exe` só serve para
Windows; para Mac ou Linux, compile no próprio sistema. O código `.m` roda em qualquer
sistema que tenha MATLAB.

## 6. O que mudou em relação ao app antigo (`app2.mlapp`)

| Problema no código antigo | O que foi feito |
|---|---|
| O `Bpk` usava o comprimento médio de espira no lugar de `le` e ignorava N, subestimando as perdas em 4 a 5 vezes | passou a usar a identidade exata `B = L·I/(N·Ae)` |
| A curva `pcore002` era chamada para todo material Magmattec | `pcore_magmattec(material,…)` escolhe a curva certa |
| Todos os materiais Magnetics usavam um único coeficiente de Steinmetz (o do MPP μ40) | coeficientes por material e permeabilidade (`Magnetics_CurveFit`) |
| No transformador, `alpha` e `k` de Steinmetz estavam trocados, o que estourava as perdas e rejeitava todos os projetos | ordem correta: `k, alpha, beta` |
| A fórmula do rendimento tinha sido alterada | voltou à do original: `η = (P_out − perdas)/P_out` |
| A densidade só tinha a vista `Loss/Vol` | mantida a `Loss/Vol` (padrão) e acrescentada a `P_out/Vol` |
| MOSFET-I e II dividiam variáveis no workspace base | viraram funções puras, `pdpwr.loss.mosfet(model, op)` |
| `evalin('base','run(…)')` impedia o standalone | tudo foi para `+pdpwr`, com caminhos via `data_root`/`output_dir` que funcionam no `.exe` |
| A constante 9 da equação de Faraday estava fixa no código | agora é o campo "Faraday Constant (k)", informado pelo usuário |

## 7. Documentação

- [`docs/teoria/teoria_densidade.pdf`](docs/teoria/teoria_densidade.pdf) — relatório no
  template ABNT/UFC com cada equação deduzida e cada constante justificada. Para
  recompilar: `pdflatex teoria_densidade.tex` (rode duas vezes).
- [`docs/THEORY.txt`](docs/THEORY.txt) — a teoria de eletrônica de potência em texto
  corrido, incluindo a dedução da equação de Faraday e um resumo de todas as equações.
- [`docs/DEVELOPER_GUIDE.txt`](docs/DEVELOPER_GUIDE.txt) — guia do back-end: estrutura
  das pastas, esquema do `Catalog.xlsx`, estruturas de dados, arquitetura da interface,
  armadilhas conhecidas e como estender ou compilar.

## Créditos

Trabalho do GPEC/UFC. Autores: Adolfo José M. F. Araújo, João Felipe X. P. Lima,
Davi C. Amorim, João Rodrigo Arnaud da Cruz, Samanta Gadelha Barbosa e Demercil de S.
Oliveira Júnior.

Os modelos PLECS em `data/plecs_mosfets/` são da Wolfspeed e da GeneSiC, derivados dos
datasheets dos fabricantes, e estão aqui apenas para permitir reproduzir os resultados.
Os direitos são dos respectivos fabricantes.
