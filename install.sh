#!/bin/sh
CWD=$(dirname $(readlink -f "$0"))
BIN_DIR=${BIN_DIR:-$HOME/.local/bin}
COMPLETIONS_DIR=${COMPLETIONS_DIR:-/usr/share/bash/completions/}

[ -f "$BIN_DIR/file_watcher" ] && echo o arquivo file_watcher já existe cancelando instalação. && exit 1

[ ! -d "$BIN_DIR" ] && mkdir -p "$BIN_DIR"

cp -r $CWD/file_watcher.sh $BIN_DIR/file_watcher
chmod +x $BIN_DIR/file_watcher

[ -d "$COMPLETIONS_DIR" ] && cp $CWD/completion.sh $COMPLETIONS_DIR/file_watcher
[ ! -d "$COMPLETIONS_DIR" ] && cat<<EOF
Não foi possível encontrar o caminho especificado na variavel COMPLETIONS_DIR.
Tente incluir o arquivo completion.sh diretamente no seu arquivo .basrhrc.
Exemplo:

. $CWD/completion.sh
EOF
