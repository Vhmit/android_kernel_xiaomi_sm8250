#!/bin/bash
#
# Copyright (C) 2020-2021 Adithya R.
# Copyright (C) 2026 Vhmit.

# Colors
RED='\033[0;31m'
NC='\033[0m' # No Color

export PATH="$TC_DIR/bin:$PATH"

# Check if no arguments were provided
if [[ $# -eq 0 ]]; then
    echo -e "${RED}\n[!] Error: No arguments provided.${NC}"
    echo -e "Usage: $0 [flag] <defconfig_name>"
    echo -e "Example: $0 -r alioth_defconfig"
    exit 1
fi

# Logic to capture the defconfig from arguments
if [[ $1 =~ ^- ]] && [[ -n "$2" ]]; then
    DEFCONFIG="$2"
elif [[ -n "$1" && ! "$1" =~ ^- ]]; then
    DEFCONFIG="$1"
fi

# Validation: If not a clean command, check if DEFCONFIG exists and is specified
if [[ "$1" != "-c" && "$1" != "--clean" ]]; then
    if [[ -z "$DEFCONFIG" ]]; then
        echo -e "${RED}\n[!] Error: Please specify a defconfig file.${NC}"
        exit 1
    elif [[ ! -f "arch/arm64/configs/$DEFCONFIG" ]]; then
        echo -e "${RED}\n[!] Error: Config '$DEFCONFIG' not found in arch/arm64/configs/${NC}"
        exit 1
    fi
fi

# Actions
if [[ $1 = "-r" || $1 = "--regen" ]]; then
    make O=out ARCH=arm64 $DEFCONFIG savedefconfig
    cp out/defconfig arch/arm64/configs/$DEFCONFIG
    echo -e "\nSuccessfully regenerated (minimal) defconfig at $DEFCONFIG"
    rm -rf out
    exit
fi

if [[ $1 = "-rf" || $1 = "--regen-full" ]]; then
    make O=out ARCH=arm64 $DEFCONFIG
    cp out/.config arch/arm64/configs/$DEFCONFIG
    echo -e "\nSuccessfully regenerated (full) defconfig at $DEFCONFIG"
    rm -rf out
    exit
fi

echo -e "${RED}\n[!] Error: You must specify an action flag (-r or -rf).${NC}"
exit 1
