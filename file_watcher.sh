#!/bin/bash
. $(dirname $(readlink -f $0))/constants.sh

clean()
{
    echo "não use o parametro --clear se estiver em produção isso vai gerar problemas"
    if [ ! -z $DEBUG  -a ! -z $ALLOW_DELETE ];then
        for path in $PATHS_WATCH;do
            rm -rf -i $path/*
        done
        rm -rf -i $BACKUP_FOLDER
    fi
}

debug()
{
    local message="$1"
    local level="$2"
    if [ ! -z $DEBUG  ];then
        if [ "$DEBUG" -ge "$level" ];then
            echo $message
        fi
        
    fi
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
        debug "arquivo $(basename $file) já existe pulando backup" $DEBUG_INFO
    fi
}

file_backup()
{
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
                debug "Nenhuma diferença foi encontrada" $DEBUG_INFO
            else
                debug "Diferenças foram encontradas movendo o arquivo temporário para a pasta de backups" $DEBUG_INFO
                mv "$TEMP_FOLDER/$file_temp" "$BACKUP_FOLDER/$file_temp"
            fi
        else
            backup_file=$(echo $file_src | sed "s|$file_dir|$BACKUP_FOLDER|" | sed -r "s|/|\\\\|g")
            debug "Arquivo não tem versão anterior provalvelmente não foi aberto antes de iniciar o serviço" $DEBUG_INFO
            debug "Tentando buscar diferenças com o ultimo arquivo disponivel na pasta de backups" $DEBUG_INFO
            backup_file_last=$(ls $BACKUP_FOLDER | grep -F "$backup_file" | tail -n 1)

            if [ "$backup_file_last" != "" ];then

                diff "$file_src" "$BACKUP_FOLDER/$backup_file_last" > /dev/null
                if [ $? -eq 0 ];then
                    debug "Nenhuma diferença foi encontrada" $DEBUG_INFO
                else
                    debug "bf:Diferenças foram encontradas movendo o arquivo temporário para a pasta de backups" $DEBUG_INFO
                    cp "$BACKUP_FOLDER/$backup_file_last" "$file_dest"
                fi
            else
                file_dest=$(echo $file_dest | sed "s|$TEMP_FOLDER|$BACKUP_FOLDER|")
                debug "nenhum arquivo de backup foi encontrado provalvelmente foi a criação do arquivo" $DEBUG_INFO
                if [[ $file_dest == *.default ]];then
                    cp "$file_src" "$BACKUP_FOLDER/$(basename $file_src)"
                else
                    cp "$file_src" "$file_dest"
                fi
            fi
        fi

    fi

}

# faz uma copia do arquivo para a pasta temporaria para comparar os arquivos
file_open()
{
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
                debug "arquivo $file aberto" $DEBUG_INFO 
                file_temp "$file"
            fi
            EVENTS=()
        fi

    fi
}

# procura pela copia na pasta temporario e se houverem alterações entre os arquivos faz o backup
file_save()
{
    local event="$1"
    local file="$2"
    local events="OPEN MODIFY CLOSE_WRITE,CLOSE"
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
            debug "arquivo $file salvo" $DEBUG_INFO
            file_backup "$file"
            # EVENTTYPE="SAVE"
            EVENTS=()
        fi

    fi
}

file_restore()
{
    echo $BACKUP_FOLDER
    if [ ! -d $BACKUP_FOLDER ];then
        echo "A pasta de backup não existe"
        exit 1
    fi

    local file_dir=$(dirname $@)
    local file=$(basename $@ | cut -d '_' -f1)
    local new_file=$(echo $@ | sed 's|/|\\|g')

    for path in $PATHS_WATCH;do
        canonical_path=$(readlink -f $path) 

        if [[ $(echo $file_dir | grep $canonical_path ) ]] then
            # verifica se o arquivo existe
            if [[ -f "$file_dir/$file" && $file != *.default ]];then
                mv "$file_dir/$file" "$file_dir/$file.default"
                cp "$BACKUP_FOLDER/$new_file" "$file_dir/$file"
            else
                echo mv "$file_dir/$file" "$file_dir/$(echo $file | sed 's|.default||')"
            fi
            
        fi
    done

    exit $?
}

service_bootstrap()
{
    debug "TEMP_FOLDER:$(readlink -f $TEMP_FOLDER)" $DEBUG_INFO 
    debug "BACKUP_FOLDER:$(readlink -f $BACKUP_FOLDER)" $DEBUG_INFO
    debug "PATHS_WATCH: $(readlink -f $PATHS_WATCH)" $DEBUG_INFO
    debug "---" $DEBUG_INFO

    mkdir -p $TEMP_FOLDER $BACKUP_FOLDER
    trap service_teardown EXIT
}

service_start()
{
    service_bootstrap

    EVENTSFILTER="-e create -e open -e modify -e close_write -e close_nowrite"
    EVENTS=()
    EVENTTYPE=""
    inotifywait -m -r --format '%e %w%f' $PATHS_WATCH --exclude $PATHS_EXCLUDE $EVENTSFILTER  | while read event file; do
        case $ALGO in
            bash) 
                debug "EVENT: $event" $DEBUG_EVENT
                
                # condição necessária para funcionar com o vim 
                if [ "$EVENTTYPE" = "SAVE" -a "$event" = "OPEN" ];then
                    continue
                else
                    EVENTTYPE=""
                fi

                if [ "$file" != "" -a "$EVENTTYPE" != "COPY" ];then


                    file_save "$event" "$(readlink -f $file)"
                    file_open "$event" "$(readlink -f $file)"
                    
                    # debug "EVENTS: ${EVENTS[@]}" "$DEBUG_EVENT"
                    # debug "EVENTTYPE: ${EVENTTYPE}" "$DEBUG_EVENT"
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