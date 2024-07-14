#!/bin/bash
if which file_watcher > /dev/null ;then
    . $(dirname $(readlink -f $(which file_watcher)))/constants.sh
    _file_watcher()
    {
        local prefix="$3"
        local filter="$2"
        local backup_files=""
        local compfilter=""
        local file_dir=""

        [ "$filter" != "" ] && compfilter="-- $filter"

        if [ -d $BACKUP_FOLDER ];then
            for file in $(find $BACKUP_FOLDER -type f);do
                backup_file=$(echo $(basename $file) | sed 's|\\|/|' | sed 's|\\|/|g')
                backup_files+="$backup_file "
            done
        fi


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
fi
