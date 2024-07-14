# File_Watcher

Você já precisou de uma cópia de um arquivo e não encontrou? pensando nisso eu escrevi esse script que faz copias a cada modificação relevante que houver no arquivo.

## Configurando

1. O primeiro passo é alterar o valor da variável presente no arquivo 'constants.sh':
    1. Altere o valor de 'BACKUP_FOLDER' para o local onde você deseja armazenar suas versões do backup_files.
    2. O segundo importante alterar o valor de 'PATHS_WATCH' para as pastas onde você quer procurar alterações de seus arquivos. Você pode separar por espaços para monitorar várias pastas: 'PATHS_WATCH="/home/user1/folder_to_look /srv/site1"'

## Inicando o serviço
Após configurar chegou a hora monitorar as alterações dos arquivos. Para iniciar o monitoramento dos arquivos basta executar o seguinte comando:
> bash file_watcher.sh --service

isso inicia o serviço e quando forem feitas alterações nos arquivos as cópias começaram a serem realizadas para pasta indicada no arquivo constansts.sh 

## Restaurando uma versão especifica
Para restaurar uma versão do seu arquivo utilize o seguinte commando:
> bash file_watcher.sh --restore /caminho/absoluto/do/arquivo_timestamp

**NOTA**: se você quiser utilizar a feature de autocompletion mova o arquivo completion.sh para `/usr/share/bash-completion/completions/` e abra um novo terminal. Para um melhor funcionanmento adicione também a pasta do projeto a váriavel de ambiente `PATH`.