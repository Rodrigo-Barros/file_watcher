#!/bin/bash
. $(dirname $(readlink -f $0))/constants.sh

clean()
{
    echo "não use o parametro --clear se estiver em produção isso pode gerar problemas se não souber o que está fazendo"
    if [ ! -z $DEBUG  -a ! -z $ALLOW_DELETE ];then
        for path in $PATHS_WATCH;do
            rm -rf  $path/*
        done
        rm -rf  $BACKUP_FOLDER
    fi
}

debug()
{
    local message="$1"
    local level=${2:-$DEBUG_INFO}

    if [[ $(echo $2 | grep -E "[a-zA-Z]") ]];then
        level=$(echo $@ | cut -d ' ' -f$(echo $@ | wc -w))
    fi

    if [ ! -z $DEBUG  ];then
        if [ $DEBUG -ge $level ];then
            echo $message
        fi
    fi
}

deduplicate_files()
{
    while true;do
        sleep $DEDUPLICATE_LOOP_TIME
        rdfind -deleteduplicates true $BACKUP_FOLDER
    done
}

# cria o arquivo temporario com as barras no padrão do windows
file_mktmp()
{
    local file_src="$@"
    local path_separator=$(echo $file_src | sed -r 's|/|\\|g')
    local file_dest="$TEMP_FOLDER/${path_separator}_$(date +$BACKUP_FILE_NAME_SUFFIX)"
    echo $file_dest
}

file_temp()
{
    local file_src="$@"
    local file_dest=$(file_mktmp "$file_src")

    if [ ! -f $file_dest ];then
        debug "cp '$file_src' '$file_dest' " $DEBUG_TRACE
        cp "$file_src" "$file_dest"
        EVENTTYPE="COPY"
    else
        debug "arquivo $(basename $file) já existe pulando backup"
    fi
}

file_backup()
{
    debug "--- file_backup: start ---" $DEBUG_TRACE
    local file_src="$1"
    local file_dir=$(readlink -f $(dirname $file_src))
    local file_dest=$(file_mktmp "$file_src")
    local file_temp_grep=$(basename $file_dest)
    local file_temp_grep=$(echo $file_temp_grep | sed -r "s|^(.+)_([0-9]{2}_[0-9]{2}_[0-9]{4}_[0-9]{6})|\1|g")
    local backup_file=""
    # local file_temp=$(echo $file_temp_suffix | sed "s|$file_temp_suffix||")


    file_temp=$(ls "$TEMP_FOLDER" | grep -F "$file_temp_grep" | tail -n 1)

    if [[ $file_src != *.default ]];then

        if [ -f "$TEMP_FOLDER/$file_temp" ];then
            diff "$file_src" "$TEMP_FOLDER/$file_temp" > /dev/null
            if [ $? -eq 0 ];then
                debug "Nenhuma diferença foi encontrada temp"
            else
                debug "Diferenças foram encontradas movendo o arquivo temporário para a pasta de backups"
                mv "$TEMP_FOLDER/$file_temp" "$BACKUP_FOLDER/$file_temp"
            fi
        else
            backup_file=$(echo $file_src | sed -r "s|/|\\\\|g")
            backup_file=$(ls $BACKUP_FOLDER | grep -v .default | grep -F "$backup_file" | tail -n 1)

            
            debug "Tentando buscar diferenças com o ultimo arquivo disponivel na pasta de backups"

            debug "file_src: $file_src" $DEBUG_TRACE

            debug "backup_file: $BACKUP_FOLDER/$backup_file" $DEBUG_TRACE
            # killall inotifywait
            # exit 0

            if [ -f "$BACKUP_FOLDER/$backup_file" ];then

                diff "$file_src" "$BACKUP_FOLDER/$backup_file" > /dev/null
                if [ $? -eq 0 ];then
                    debug "Nenhuma diferença foi encontrada backup"
                else
                    debug "Diferenças foram encontradas copiando o arquivo para a pasta temporária"
                    file_temp "$file_src"
                fi
            else
                debug "nenhum arquivo de backup foi encontrado provalvelmente foi a criação do arquivo realizando cópia do arquivo"
                file_temp $file_src
            fi
        fi
    fi
    debug "--- file_backup: end ---" $DEBUG_TRACE
}

# faz uma copia do arquivo para a pasta temporaria para comparar os arquivos
file_open()
{
    debug "--- file_open: start ---" $DEBUG_TRACE
    local event="$1"
    local file="$2"
    local events="OPEN CLOSE_NOWRITE,CLOSE"
    local length=${#EVENTS[@]}
    length=$(expr $length + 1)
    local current_word=$(echo $events | cut -d ' ' -f$length)

    if [ "$EVENTTYPE" = "OPEN" -o "$EVENTTYPE" = "" ];then

        if [ "$event" = "$current_word" ];then
            EVENTTYPE="OPEN"
            EVENTS+=($current_word)
        fi

        if [[ "${EVENTS[@]}" = "$events" ]];then
            if [ ! -f "$(file_mktmp $file)" ];then
                debug "arquivo $file aberto"
                file_temp "$file"
            fi
            EVENTS=()
        fi

    fi
    debug "--- file_open: end ---" $DEBUG_TRACE
}

# procura pela copia na pasta temporario e se houverem alterações entre os arquivos faz o backup
file_save()
{
    local event="$1"
    local file="$2"
    local events=("OPEN MODIFY CLOSE_WRITE,CLOSE")
    local length=${#EVENTS[@]}
    length=$(expr $length + 1)
    local current_word=$(echo $events | cut -d ' ' -f$length)


    if [ "$EVENTTYPE" = "SAVE" -o "$EVENTTYPE" = "" ];then
        if [ "$event" = "$current_word" ];then
            EVENTS+=($current_word)
            if [ $length -eq 2 -a $current_word = "MODIFY" ];then
                EVENTTYPE="SAVE"
            fi
        fi

        if [[ "${EVENTS[@]}" = "$events" ]];then
            file_backup "$file"
            # EVENTTYPE="SAVE"
            EVENTTYPE=""
            EVENTS=()
        fi
    fi
}

# Detectado modificados via UPLOAD
# Nota: O Teste foi realizado utilizado vscode como editor
# possivelmente o conjunto de eventos mude utilizando um outro editor
file_upload()
{
    local event="$1"
    local file="$2"
    local events="OPEN MODIFY MODIFY CLOSE_WRITE,CLOSE"
    local total_events=$(echo $events | wc -w)
    local length=${#EVENTS[@]}
    length=$(expr $length + 1)
    local current_word=$(echo $events | cut -d ' ' -f$length)


    if [ "$EVENTTYPE" = "OPEN_UPLOAD" -o "$EVENTTYPE" = "" ];then

        if [ "$event" = "$current_word" ];then
            EVENTS+=($current_word)

            if [ $length -eq 2 -a $current_word = "$(echo $events | cut -d ' ' -f2 )" ];then
                EVENTTYPE="OPEN_UPLOAD"
            fi
        fi

        if [[ "${EVENTS[@]}" = "$events" ]];then
            file_backup $file
        fi

        if [ $length -eq $total_events ];then
            EVENTTYPE=""
            EVENTS=()
        fi
    fi
}

file_restore()
{
    if [ $# -eq 0 ];then
        echo "Você precisa informar um arquivo para restaurar"
        exit 1;
    fi

    if [ ! -d $BACKUP_FOLDER ];then
        echo "A pasta de backup não existe"
        exit 1
    fi
    # cria uma trava no loop de eventos para não detectar uma restauração como uma alteração
    # e realizar uma cópia desnecessária

    [ -f $TEMP_FOLDER/.stop ] && echo "ERROR: Existe um backup em progresso" && exit 1
    [ ! -f $TEMP_FOLDER/.stop ] && touch $TEMP_FOLDER/.stop

    local file_dir=$(dirname $@)
    local file_src=$(basename $@ | cut -d '_' -f1)
    local file_dest=$(echo $@ | sed 's|/|\\|g')
    local file_name=$(echo $file_src | sed 's|.default||g')

    local file_backup_default="$BACKUP_FOLDER/$(echo $file_dir/$file_src | sed 's|/|\\|g' | sed 's|.default||').default"
    local file_backup="$BACKUP_FOLDER/$file_dest"

    if [[ ! -f $file_backup_default ]];then
        cp "$file_dir/$file_name" "$file_backup_default"
    fi


    if [[ "$file_src" != *.default ]];then
        rm "$file_dir/$file_src"
        cp "$file_backup" "$file_dir/$file_src"
    else
        rm "$file_dir/$file_name"
            cp "$file_backup_default" "$file_dir/$file_name"
    fi

    [ -f $TEMP_FOLDER/.stop ] && rm "$TEMP_FOLDER/.stop"

    exit $?
}

service_bootstrap()
{
    debug "TEMP_FOLDER:$(readlink -f $TEMP_FOLDER)"
    debug "BACKUP_FOLDER:$(readlink -f $BACKUP_FOLDER)"
    debug "PATHS_WATCH: $(readlink -f $PATHS_WATCH)"
    debug "SCRIPT PID: $$"
    debug "---"

    mkdir -p $TEMP_FOLDER $BACKUP_FOLDER
    trap service_teardown EXIT
}

service_start()
{
    service_bootstrap

    EVENTSFILTER="-e create -e open -e modify -e close_write -e close_nowrite"
    EVENTS=()
    EVENTTYPE=""
    if which rdfind > /dev/null;then
        deduplicate_files &
    fi
    inotifywait -m -r --format '%e %w%f' $PATHS_WATCH --exclude $PATHS_EXCLUDE $EVENTSFILTER  | while read event file; do
        case $ALGO in
            bash)

                if [ -f "$TEMP_FOLDER/.stop" ];then
                    debug "BACKUP EM PROGRESSO IGNORANDO PRÓXIMOS EVENTOS..." $DEBUG_INFO
                    continue
                fi

                # condição necessária para funcionar com o vim
                if [ "$EVENTTYPE" = "SAVE" -a "$event" = "OPEN" ];then
                    continue
                else
                    EVENTTYPE=""
                fi

                if [ "$file" != "" -a "$EVENTTYPE" != "COPY" ];then

                    file_save "$event" "$(readlink -f $file)"
                    file_upload "$event" "$(readlink -f $file)"
                    file_open "$event" "$(readlink -f $file)"

                    eventos=${EVENTS[@]}
                    debug "EVENTS: $eventos" $DEBUG_EVENT
                    debug "EVENTTYPE: ${EVENTTYPE}" $DEBUG_EVENT
                else
                    EVENTTYPE=""
                fi
            ;;
            php)
                php events.php $file $timestamp
            ;;
        esac

        find $TEMP_FOLDER -mmin +10 -exec rm {} ';'
    done
}

service_teardown()
{
    rm -r $TEMP_FOLDER
}

usage()
{
cat<<EOF
Comandos:

--help          Exibe a ajuda.
--restore       Lista os arquivos disponíveis para realizar um backup.
--service       Inicia o serviço procurando por alterações no sistema de arquivos.
EOF
}


for arg in $@;do
    case $arg in
        --service) service_start;;
        --restore) file_restore $2;;
        --clear) clean;;
        --help) usage;;
    esac
done

[ $# -eq 0 ] && usage
