#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
find "$DIR/../src" \( -name "*.cpp" -o -name "*.c" -o -name "*.h" \) -exec uncrustify -c "$DIR/uncrustify.cfg" --replace --no-backup {} +
