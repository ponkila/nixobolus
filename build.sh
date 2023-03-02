#!/bin/bash
# Nixobolus - Automated creation of bootable NixOS images
# https://github.com/ponkila/Nixobolus

# Define variables
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
output_dir="$SCRIPT_DIR/result"
keep_configs=false
prompt=false

# Check main dependencies (nix, python, jinja2)
check_deps() {
    # Check if nix-build is available
    if ! command -v nix-build >/dev/null 2>&1; then
        echo "[-] Nix package manager is not installed."
        exit 1
    fi

    # Check if python is installed
    if command -v python3 >/dev/null 2>&1 ; then
        python_cmd="python3"
    elif command -v python >/dev/null 2>&1 ; then
        python_cmd="python"
    else
        echo "[-] Python is not installed."
        exit 1
    fi

    # Check that python can import jinja2
    if ! $python_cmd -c "import jinja2" >/dev/null 2>&1; then
        echo "[-] Jinja2 is not installed."
        exit 1
    fi
}

# Parse the command line options
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--prompt) prompt=true;;
            -k|--keep-configs) keep_configs=true ;;
            -o|--output) output_dir="$2"; shift ;;
            *.yml|*.yaml|*.json)
                config_file="$1"
                ;;
            *) echo "[-] Unknown parameter passed: $1" >&2
            exit 1 ;;
        esac
        shift
    done
}

# Read standard input
get_stdin() {
    # Read from stdin and store it in the temporary file
    temp_file="$(mktemp)"
    cat > "$temp_file"
    config_file="$temp_file"
}

# Get filetype (yaml or json)
get_filetype() {
    local file=$1
    local basename="${file##*/}"
    local firstline
    filetype="${basename##*.}"

    # Try to detect the filetype by first line
    if ! [[ "$filetype" =~ ^(yaml|yml|json)$ ]]; then
        firstline=$(head -n1 "$file")
        # Check for YAML
        if [[ "$firstline" == "---"* ]]; then
            filetype="yaml"
        # Check for JSON
        elif [[ "$firstline" == "{"* ]]; then
            filetype="json"
        else
            echo "[-] Unable to detect the data format as YAML or JSON."
            exit 1
        fi
    fi
}

# Get hostnames from config file
get_hostnames() {
    local config_file=$1
    local filetype=$2

    case "$filetype" in
        yaml|yml)
            # Check if yq is installed
            if ! command -v yq >/dev/null 2>&1; then
                echo "[-] yq is not installed."
                exit 1
            fi
            # Extract the names of the hosts from the YAML file
            hostnames=$(yq -r '.hosts[].name' "$config_file")
            ;;
        json)

            # Check if jq is installed
            if ! command -v jq >/dev/null 2>&1; then
                echo "[-] jq is not installed."
                exit 1
            fi
            # Extract the host names from the JSON file
            hostnames=$(jq -r '.hosts[].name' "$config_file")
            ;;
        *)
            echo "[-] Invalid file format. Only YAML and JSON files are supported."
            exit 1
            ;;
    esac

    # Check if hosts are empty
    if [ -z "$hostnames" ]; then
        echo "[-] No hosts found in $config_file"
        exit 1
    fi
}

# Check if previous config files exist
check_prev_config() {
    local dir=$1
    if [ -d "$dir" ] && [ "$(ls -A "$dir")" ]; then
        if [ "$prompt" == true ]; then
            read -r -p "[?] Delete previous config files and render again? (y/n)" choice
        else
            choice="y"
        fi
        if [ "$choice" != "y" ]; then
            echo "[+] Exiting..."
            exit 1
        fi
        rm -rf "${dir:?}"/*
    fi
}

# Decrypt file encrypted with SOPS
sops_decrypt() {
    local file=$1
    local filetype=$2

    # Check if sops is installed
    if ! command -v sops &> /dev/null; then
        echo "[-] Decryption failed, SOPS not installed."
        exit 1
    fi

    # Check if config file is encrypted with sops
    if ! sops --input-type "$filetype" --output-type "$filetype" -d "$file" >/dev/null 2>&1;then
        return
    fi

    # Create a temporary file for the decrypted output
    decrypted_temp_file=$(mktemp)

    # Decrypt file and write output to temporary file
    if ! sops --input-type "$filetype" --output-type "$filetype" -d "$file" > "$decrypted_temp_file"; then
        echo "[-] Decryption failed."
        exit 1
    else
        echo "[+] Decryption successful."
        config_file="$decrypted_temp_file"
    fi
}

# Check if previous build files exists
build_images() {
    local total_hosts
    total_hosts=$(echo "$hostnames" | wc -w)

    # Check if output directory exists and prompt user if necessary
    if [ -d "$output_dir" ] && [ "$(ls -A "$output_dir")" ]; then
        if [ "$prompt" == true ]; then
            read -r -p "[?] Delete previous images and rebuild? (y/n)" choice
        else
            choice="y"
        fi
        if [ "$choice" != "y" ]; then
            echo "[+] Exiting..."
            exit 1
        fi
        rm -rf "${output_dir:?}"/*
    else
        if [ "$prompt" == true ]; then
            read -r -p "[?] Proceed with building? (y/n)" choice
        else
            choice="y"
        fi
        if [ "$choice" != "y" ]; then
            echo "[+] Exiting..."
            exit 1
        fi
    fi

    # Start the timer
    SECONDS=0

    # Initialize host building counter
    counter=0

    # Loop through the hosts and build the images
    declare -A symlink_paths
    for host in $hostnames; do
        
        # Print host name
        (( counter++ ))
        echo -e "\n[+] Building images for $host [$counter/$total_hosts]"
        
        # Build images for $host using nix-build command
        time nix-build \
            -A pix.ipxe "$SCRIPT_DIR"/configs/nix_configs/hosts/"$host"/default.nix \
            -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/refs/heads/nixos-unstable.zip \
            -I home-manager=https://github.com/nix-community/home-manager/archive/master.tar.gz \
            -o "$output_dir"/"$host" ;
            #--show-trace ;

        # Check if building images for $host was successful
        if [ $? -ne 0 ]; then
            echo -e "[-] Build failed for $host"
            if [ "$prompt" == true ]; then
                read -r -p "[?] Continue? (y/n)" choice
            fi
            if [ "$choice" != "y" ]; then
                rm -rf "${output_dir:?}"/"$host"
                echo "[+] Exiting..."
                exit 1
            fi
        else
            echo "[+] Succesfully built images for $host"
            
            # Add the symlink paths to the array
            symlink_paths[$host]=$(readlink -f "$output_dir"/"$host"/* | sort -u)
        fi
    done

    # Print the symlink paths (fancy)
    for host in $(echo "${!symlink_paths[@]}" | tr ' ' '\n' | sort); do
        echo "[+] $host - result"
        # Split the string into an array
        IFS=$'\n' read -rd '' -a paths <<< "${symlink_paths[$host]}"
        for path in "${paths[@]}"; do
            if [[ "${path}" == "${paths[-1]}" ]]; then
                echo " └── ${path}"
            else
                echo " ├── ${path}"
            fi
        done
    done

    # End the timer
    secs=$SECONDS

    # Print the message with the time in the desired format
    hrs=$(( secs/3600 )); mins=$(( (secs-hrs*3600)/60 )); secs=$(( secs-hrs*3600-mins*60 ))
    printf "\n[+] Build(s) completed in: %02d:%02d:%02d\n" $hrs $mins $secs
}

# Clean up
cleanup() {
    # Remove mktemp files
    temp_files=("$temp_file" "$decrypted_file")
    for file in "${temp_files[@]}"; do
        if [ -e "$file" ]; then
            rm -f "$file"
        fi
    done

    # Remove configuration files
    if [ "$keep_configs" == false ]; then
        if [ "$prompt" == true ]; then
            read -r -p "[?] Delete rendered config files? (y/n)" choice
        else
            choice="y"
        fi
        if [ "$choice" != "y" ]; then
            echo "[+] Exiting..."
            exit 1
        fi
        rm -rf "$SCRIPT_DIR"/configs/nix_configs/hosts/*
    fi
}

main() {
    # set signal handlers to call cleanup function on exit or SIGINT
    trap cleanup EXIT
    trap cleanup SIGINT

    # Check main dependencies (nix, python, jinja2)
    check_deps

    # Parse the command line options
    parse_args "$@"

    # Check if stdin was piped
    if [[ ! -t 0 ]]; then
        # Get stdin and save to temporary file (sets config_file)
        get_stdin  
        if [[ ${prompt} == true ]]; then
            echo "[-] Prompt needs to be disabled when data is piped to the script."
            exit 1
        fi
    fi
    
    # Check if config_file is set and exists
    if [[ ! -n "$config_file" && ! -e "$config_file" ]]; then
        echo "[-] No given config file or piped data found."
        exit 1
    fi

    # Get filetype (yaml or json)
    get_filetype "$config_file"

    # Get hostnames from config file
    get_hostnames "$config_file" "$filetype"
    
    # Create required directories if they don't exist
    directories=( "$output_dir" "$SCRIPT_DIR/configs/nix_configs/hosts" )
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
    done

    # Check if previous config files exist
    check_prev_config "$SCRIPT_DIR/configs/nix_configs/hosts"

    # Decrypt if file is encrypted with SOPS
    sops_decrypt "$config_file" "$filetype"

    # Render the Nix config files using the python script
    if ! $python_cmd "$SCRIPT_DIR/configs/render_configs.py" "$config_file"; then
        echo "[-] Rendering failed."
        exit 1
    fi

    # Check if previous build files exists
    build_images
}

main "$@"