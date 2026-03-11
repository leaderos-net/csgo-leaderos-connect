#!/bin/bash
set -e

SP="scripting/spcomp"
SOURCE="leaderos_connect.sp"
OUT="upload/leaderos_connect.smx"

echo "Compiling $SOURCE..."

if [ ! -f "$SP" ]; then
    echo "ERROR: $SP not found."
    echo "Download SourceMod and place spcomp in the scripting/ folder."
    exit 1
fi

chmod +x "$SP"
mkdir -p upload

"$SP" "$SOURCE" -o"$OUT"

echo ""
echo "Done: $OUT"
