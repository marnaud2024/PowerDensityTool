Power Density Tool - como instalar e rodar
==========================================

O que distribuir desta pasta e um arquivo so:

  build/setup/MyAppInstaller.exe   (o instalador)


1. Instalando
-------------
Rode o MyAppInstaller.exe e siga o assistente. Ele instala o programa junto
com o MATLAB Runtime, que e o motor gratuito da MathWorks. Na primeira vez
voce vai precisar de internet, porque o Runtime e baixado nesse momento.

Depois de instalado, abra pelo atalho que aparece no menu Iniciar ou na area
de trabalho. Nao adianta procurar um .exe solto na pasta de instalacao e
tentar rodar direto - so o atalho funciona.

Se voce ja tinha uma versao instalada e quer atualizar, desinstale a antiga
primeiro (Configuracoes > Aplicativos > "Power Density Tool" > Desinstalar) e
so depois rode o instalador novo. Apagar a pasta na mao nao resolve.


2. Duas coisas para saber de antemao
------------------------------------
A primeira abertura depois de instalar costuma demorar - as vezes alguns
minutos - porque o Runtime descompacta os dados nessa hora. E normal, e
paciencia.

Em alguns computadores o programa empacotado nao abre de jeito nenhum. Isso e
uma limitacao do empacotamento do MATLAB, nao tem muito o que fazer. Se cair
nesse caso, use a alternativa do item 3.


3. A alternativa que sempre funciona: rodar no MATLAB
-----------------------------------------------------
Se voce tem o MATLAB (em Windows, macOS ou Linux), da para abrir a interface
na hora, sem instalar nada e sem esperar:

    cd src
    PowerDensityApp        (ou: app = PowerDensityApp;)

Abre exatamente a mesma interface. E o que eu recomendo para quem tiver
qualquer dificuldade com o instalador, e a unica opcao no Mac ou no Linux sem
compilar.


4. macOS e Linux
----------------
O instalador so serve para Windows. No Mac ou no Linux, ou voce usa o item 3
(com MATLAB), ou compila no proprio sistema com "cd src ; build_installer".
Nao da para pegar o instalador de Windows e usar em outro sistema.


5. Gerar o instalador de novo (depois de mexer no codigo)
---------------------------------------------------------
No MATLAB: cd src ; build_installer
Isso gera o build/setup/MyAppInstaller.exe e apaga a build anterior sozinho.
