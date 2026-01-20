#!/bin/bash

# Colors
NC='\033[0m'
RED='\033[0;31m'
LRD='\033[1;31m'
LGR='\033[1;32m'
YLW='\033[0;33m'

# Device
DEVICE="$1"
ZIP_FLAG="$2"

# Output usage help
if [ -z "$DEVICE" ]; then
  echo -e "${RED}Error: No device specified!${NC}"
  echo -e "Usage: ./build.sh <device_name> [-z]"
  echo -e "Example: ./build.sh alioth (just compiles)"
  echo -e "Example: ./build.sh alioth -z (compiles and generates the zip file.)"
  exit 1
fi

# Dependency Check
check_deps() {
    echo -e "${YLW}########### Checking Dependencies ############${NC}"
    local deps=("zip" "curl" "git" "make" "python3" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}Error: $dep is not installed. Please install it to continue.${NC}"
            exit 1
        fi
    done
    echo -e "${LGR}Dependencies: OK!${NC}"
}

# Date
TM=$(date '+%Y%m%d-%H%M')

kernel_dir="${PWD}"
objdir="${kernel_dir}/out"
anykernel=$HOME/anykernel
kernel_name="Mimir"
zip_name="$kernel_name-${DEVICE}-${TM}.zip"
TC_DIR="${PWD}/tc"
LOG_FILE="${PWD}/build_log.txt"

# Clang
export PATH="$TC_DIR/bin:$PATH"
if ! [ -d "$TC_DIR" ]; then
	echo "AOSP clang not found! Cloning to $TC_DIR..."
	if ! git clone --depth=1 https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r498229 "$TC_DIR"; then
		echo "Cloning failed! Aborting..."
		exit 1
	fi
fi

echo -e "${LGR}######### Clang version #########${NC}"
$TC_DIR/bin/clang --version

# Exports
export CONFIG_FILE="vendor/${DEVICE}_defconfig"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_HOST=viktor
export KBUILD_BUILD_USER=vhmit

clean_all() {
    echo -e "${YLW}########### Cleaning Output Directory ############${NC}"
    rm -rf "${objdir}"
    rm -f "$LOG_FILE"
}

make_defconfig() {
    SECONDS=0
    echo -e "${LGR}########### Generating Defconfig ############${NC}"
    # English: Ensure the config file exists before trying to make
    if [ ! -f "arch/arm64/configs/vendor/${DEVICE}_defconfig" ]; then
        echo -e "${RED}Error: vendor/${DEVICE}_defconfig not found!${NC}"
        exit 1
    fi
    make -s ARCH=arm64 O=${objdir} CC=clang HOSTCC=clang vendor/${DEVICE}_defconfig LLVM=1 LLVM_IAS=1 -j$(nproc --all)
}

compile_headers() {
    echo -e "${YLW}########### Compiling Headers ############${NC}"
    local HDR_PATH="${objdir}/arch/arm64/boot/usr"
    make -j$(nproc --all) O=${objdir} ARCH=${ARCH} CC=clang HOSTCC=clang LLVM=1 LLVM_IAS=1 \
         INSTALL_HDR_PATH="$HDR_PATH" headers_install
    find "$HDR_PATH" -type f \( -name ".install" -o -name "..install.cmd" \) -delete
    echo -e "${LGR}Compiled and cleaned headers in: $HDR_PATH${NC}"
}

compile() {
    cd "${kernel_dir}"
    echo -e "${LGR}########### Compiling kernel ############${NC}"
    local TEMP_LOG=$(mktemp)
    set -o pipefail
    make -j$(nproc --all) \
        O=${objdir} \
        ARCH=${ARCH} \
        CC=clang \
        HOSTCC=clang \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        LLVM=1 \
        LLVM_IAS=1 2>&1 | tee "$TEMP_LOG"
        
    # # Captures the error status for manual handling if necessary.
    local exit_status=$?
    if [ $exit_status -ne 0 ]; then
        echo -e "${RED}Error: Compilation failed! Generating log...${NC}"
        mv "$TEMP_LOG" "$LOG_FILE"
        echo -n "Katbin Log: "
        jq -n --rawfile c "$LOG_FILE" '{"paste":{"content":$c}}' | curl -sL -d @- 'https://katb.in/api/paste' -H "Content-Type: application/json" | jq -r '"https://katb.in/\(.id)"'
        exit $exit_status
    else
        # If the build was successful, we delete the temporary log without creating the build_log.txt file.
        rm -f "$TEMP_LOG"
        echo -e "${LGR}Kernel compiled successfully! No log file needed.${NC}"
    fi
}

completion() {
    LOCAL_BOOT="${objdir}/arch/arm64/boot"
    
    if [[ -f "${LOCAL_BOOT}/Image" ]]; then
        echo -e "${LGR}######### Packaging AnyKernel3 #########${NC}"

        # # Clear the old folder if it exists and clone it
        rm -rf "$anykernel"
        git clone --depth=1 https://github.com/Vhmit/AnyKernel3.git -b ${DEVICE} "$anykernel"

        # # 1. Treats DTB (as per its 'mv' reference)
        if [[ -f "${LOCAL_BOOT}/dtb.img" ]]; then
            mv "${LOCAL_BOOT}/dtb.img" "${LOCAL_BOOT}/dtb"
        fi

        # # 2. Copy the necessary files to the AnyKernel root directory
        cp -f "${LOCAL_BOOT}/Image" "$anykernel/"
        [[ -f "${LOCAL_BOOT}/dtb" ]] && cp -f "${LOCAL_BOOT}/dtb" "$anykernel/"
        [[ -f "${LOCAL_BOOT}/dtbo.img" ]] && cp -f "${LOCAL_BOOT}/dtbo.img" "$anykernel/"

        # # Enter the directory to generate the zip file
        cd "$anykernel"
        
        # # Remove old zip files and create a new one
        find . -name "*.zip" -type f -delete
        zip -r9 AnyKernel.zip * -x .git README.md *placeholder
        
        # # Move to the kernel folder with the final name
        cp AnyKernel.zip "$kernel_dir/$zip_name"
        
        # cleaning
        cd "$kernel_dir"
        rm -rf "$anykernel"

        echo -e "${LGR}#############################################${NC}"
        echo -e "${LGR}####### Kernel packaged successfully! #######${NC}"
        echo -e "${LGR}#############################################${NC}"

	# Upload to Gofile    
        echo -e "${YLW}Checking Gofile status...${NC}"
        SERVER=$(curl -s https://api.gofile.io/servers | jq -r '.data.servers[0].name // "store1"')
        echo -e "${YLW}Uploading ZIP to ${SERVER}...${NC}"
        RESPONSE=$(curl -# -L -F "file=@$zip_name" "https://${SERVER}.gofile.io/contents/uploadfile")

        echo -ne "${LGR}Kernel Download Link: ${NC}"
        if echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
            echo "$RESPONSE" | jq -r '.data.downloadPage'
        else
            echo -e "${RED}Upload failed! Response:${NC}"
            echo "$RESPONSE"
        fi
        
        echo -e "\n"
    fi
}

# Execution
check_deps
clean_all
SECONDS=0
make_defconfig
compile

# Only run completion (AnyKernel3) if the -z flag is present
if [ -f "${objdir}/arch/arm64/boot/Image" ]; then
    # Compile the headers only if the kernel was successful
    compile_headers
    if [ "$ZIP_FLAG" == "-z" ]; then
        completion
    else
        echo -e "\n${YLW}Info: Flag -z not detected. Compilation finished without generating ZIP.${NC}"
        echo -e "The generated files are located in: ${objdir}/arch/arm64/boot/"
    fi

    echo -e "\n${LGR}-------------------------------------------------------"
    echo -e "Completed in: $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!"
    echo -e "-------------------------------------------------------${NC}"
else
    echo -e "\n${RED}#############################################${NC}"
    echo -e "${RED}######## Kernel compilation failed! ########${NC}"
    echo -e "${RED}#############################################${NC}"
    exit 1
fi

cd ${kernel_dir}
