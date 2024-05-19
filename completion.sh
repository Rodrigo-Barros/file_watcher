#!/bin/bash
. constants.sh
_file_watcher()
{
local prefix="$3"
local filter="$2"
local backup_files=""
local compfilter=""
local file_dir=""

[ "$filter" != "" ] && compfilter="-- $filter"

    for file in $(find $BACKUP_FOLDER -type f);do
        backup_file=$(echo $(basename $file) | sed 's|\\|/|' | sed 's|\\|/|g')
        backup_files+="$backup_file "

        # lista os arquivos *.default
        for file in $(find $(dirname $backup_file) -type f -name '*.default');do
            echo $backup_files | grep -F $file > /dev/null
            # so adiciona arquivos unicos 
            if [ $? -ne 0 ];then
                backup_files+="$file "
            fi
        done
    done


    COMPREPLY=()

    case $prefix in
        --restore*)
            COMPREPLY+=($prefix)
            COMPREPLY=($(compgen -W "$backup_files" $compfilter));;
    esac

    case $filter in
        --*)
            COMPREPLY=($(compgen -W "--help --service --restore" $compfilter));;
    esac
}

complete -F _file_watcher file_watcher