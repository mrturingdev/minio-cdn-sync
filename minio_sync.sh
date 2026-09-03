#!/bin/bash

COMMAND=$1

show_usage() {
    echo "Usage for Upload:   $0 upload <local_file> <mock_folder_path_on_cdn_or_key>"
    echo "Usage for Download: $0 download <mock_folder_path_on_cdn_or_key>"
    echo "Example Upload:     $0 upload ../eruda/eruda.min.js js/vendor/eruda/eruda.min.js"
    echo "Example Download:   $0 download js/vendor/eruda/eruda.min.js"
    exit 1
}

if [ -z "$COMMAND" ]; then
    show_usage
fi

# 1. Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROPERTIES_FILE="$SCRIPT_DIR/minio.properties"

if [ ! -f "$PROPERTIES_FILE" ]; then
    echo "Error: $PROPERTIES_FILE not found!"
    exit 1
fi

# Source the properties file
set -a
source "$PROPERTIES_FILE"
set +a

# 2. Check if GlobalProtect VPN is on
echo "--> Checking GlobalProtect VPN status..."
VPN_ON=false

# Check if the GlobalProtect background process is running
if pgrep -i "GlobalProtect" > /dev/null; then
    # Additionally, check if a VPN interface (gpd or utun) is active
    if ifconfig | grep -qE "^gpd[0-9]+|^utun[0-9]+"; then
        VPN_ON=true
    fi
fi

if [ "$VPN_ON" = false ]; then
    echo "Error: GlobalProtect VPN does not appear to be connected."
    echo "Please connect to ESEWA-SECURE-GATEWAY and try again."
    exit 1
fi
echo "    [OK] VPN appears to be active."

# 3. Check for MinIO Client tool
MC_BIN="mc"
if [ -x "$SCRIPT_DIR/mc" ]; then
    MC_BIN="$SCRIPT_DIR/mc"
elif ! command -v mc &> /dev/null; then
    echo "MinIO Client (mc) could not be found."
    echo "Please ensure the local 'mc' binary is downloaded or install via: brew install minio/stable/mc"
    exit 1
fi

# 4. Check if login access is needed and apply credentials
echo "--> Applying MinIO login credentials..."
$MC_BIN alias set dev-cdn "$MINIO_URL" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"
if [ $? -ne 0 ]; then
    echo "Error: Failed to configure MinIO credentials. Please check minio.properties."
    exit 1
fi
echo "    [OK] Credentials applied."

# 5. Check Bucket Access
echo "--> Verifying access to bucket '$MINIO_BUCKET'..."
if ! $MC_BIN ls dev-cdn/"$MINIO_BUCKET" > /dev/null 2>&1; then
    echo "Error: Cannot access bucket '$MINIO_BUCKET'."
    echo "Please verify your MinIO URL, credentials, and bucket existence."
    exit 1
fi
echo "    [OK] Bucket is accessible."

echo "----------------------------------------"

# Helper to resolve MOCK_PATH from properties and clean it
resolve_mock_path() {
    local path="$1"
    local cdn_file="$SCRIPT_DIR/cdn_locations.properties"
    
    # If the provided path doesn't contain a slash, it might be a key
    if [[ ! "$path" == *"/"* ]] && [ -f "$cdn_file" ]; then
        local resolved
        resolved=$(grep "^${path}=" "$cdn_file" | cut -d'=' -f2)
        if [ -n "$resolved" ]; then
            # Print to stderr so it doesn't get captured by $(...)
            echo "--> Resolved key '$path' to path: $resolved" >&2
            path="$resolved"
        fi
    fi
    
    # Strip leading slashes to prevent writing/uploading to root filesystem path
    path="${path#/}"
    
    # Always have a default start path as esewa_gprs
    if [[ "$path" != "esewa_gprs/"* ]] && [[ "$path" != "esewa_gprs" ]]; then
        path="esewa_gprs/$path"
    fi

    echo "$path"
}

# 6. Execute Upload or Download with Mock Directory Structure
if [ "$COMMAND" = "upload" ]; then
    TARGET_ARG=$2
    MOCK_ARG=$3

    if [ -z "$TARGET_ARG" ]; then
        show_usage
    fi
    
    if [ -z "$MOCK_ARG" ]; then
        # If only one argument is provided, we assume it's the key (or path) for both local and remote.
        RESOLVED_PATH=$(resolve_mock_path "$TARGET_ARG")
        TARGET_FILE="$RESOLVED_PATH"
        MOCK_PATH="$RESOLVED_PATH"
    else
        # If two arguments are provided, resolve the mock path normally
        MOCK_PATH=$(resolve_mock_path "$MOCK_ARG")
        TARGET_FILE=$TARGET_ARG
        
        # Prepend esewa_gprs/ to the local file path if it doesn't already have it
        if [[ "$TARGET_FILE" != "esewa_gprs/"* ]] && [[ "$TARGET_FILE" != "esewa_gprs" ]]; then
            TARGET_FILE="esewa_gprs/$TARGET_FILE"
        fi
    fi

    if [ ! -f "$TARGET_FILE" ]; then
        echo "Error: Local file '$TARGET_FILE' does not exist."
        exit 1
    fi

    echo "Uploading '$TARGET_FILE'..."
    echo "Destination: dev-cdn/$MINIO_BUCKET/$MOCK_PATH"
    
    $MC_BIN cp "$TARGET_FILE" "dev-cdn/$MINIO_BUCKET/$MOCK_PATH"
    echo "--> Upload complete!"

elif [ "$COMMAND" = "download" ]; then
    MOCK_PATH=$(resolve_mock_path "$2")

    if [ -z "$MOCK_PATH" ]; then
        show_usage
    fi

    # Create the mock directory structure locally before downloading
    LOCAL_MOCK_DIR=$(dirname "$MOCK_PATH")
    if [ "$LOCAL_MOCK_DIR" != "." ]; then
        echo "Creating local mock directory structure: $LOCAL_MOCK_DIR"
        mkdir -p "$LOCAL_MOCK_DIR"
    fi

    echo "Downloading 'dev-cdn/$MINIO_BUCKET/$MOCK_PATH'..."
    echo "Destination: $MOCK_PATH"
    
    $MC_BIN cp "dev-cdn/$MINIO_BUCKET/$MOCK_PATH" "$MOCK_PATH"
    echo "--> Download complete!"

else
    echo "Unknown command: $COMMAND"
    show_usage
fi
