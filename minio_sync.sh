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

# Parse the properties file as plain KEY=VALUE pairs.
# Deliberately not `source`d: sourcing executes the file as bash, so any shell
# metacharacter in a credential value would be evaluated instead of read literally.
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
        ''|'#'*) continue ;;
        *'='*) ;;
        *) continue ;;
    esac
    prop_key="${line%%=*}"
    prop_value="${line#*=}"
    prop_key="${prop_key#"${prop_key%%[![:space:]]*}"}"
    prop_key="${prop_key%"${prop_key##*[![:space:]]}"}"
    prop_value="${prop_value#"${prop_value%%[![:space:]]*}"}"
    if [[ "$prop_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        printf -v "$prop_key" '%s' "$prop_value"
    fi
done < "$PROPERTIES_FILE"
unset line prop_key prop_value

# 2. Required settings must be present and non-empty
for required in MINIO_URL MINIO_ACCESS_KEY MINIO_SECRET_KEY MINIO_BUCKET; do
    if [ -z "${!required}" ]; then
        echo "Error: $required is not set in $PROPERTIES_FILE" >&2
        exit 1
    fi
done
unset required

# Default base segment if not set in properties
BASE_SEG="${BASE_SEGMENT:-mock_dir}"


# 3. Check for MinIO Client tool
MC_BIN="mc"
if [ -x "$SCRIPT_DIR/mc" ]; then
    MC_BIN="$SCRIPT_DIR/mc"
elif [ -x "$SCRIPT_DIR/mc.exe" ]; then
    MC_BIN="$SCRIPT_DIR/mc.exe"
elif ! command -v mc &> /dev/null; then
    echo "MinIO Client (mc) could not be found."
    echo "Please ensure the local 'mc' (or 'mc.exe' on Windows) binary is downloaded, or install via: brew install minio/stable/mc"
    exit 1
fi

# 4. Build the MinIO connection for this run.
# Credentials reach mc through MC_HOST_<alias> in its environment rather than as
# command-line arguments, so they do not appear in `ps` output and are not written
# to the global ~/.mc/config.json.
if [ "$MINIO_URL" = "${MINIO_URL#*://}" ]; then
    echo "Error: MINIO_URL must include a scheme, e.g. http://host:port" >&2
    exit 1
fi
MINIO_SCHEME="${MINIO_URL%%://*}"
MINIO_HOSTPORT="${MINIO_URL#*://}"
MINIO_HOSTPORT="${MINIO_HOSTPORT%%/*}"

# mc reads MC_HOST_<alias> literally and does NOT percent-decode the userinfo,
# so the credentials must be inserted verbatim. That means a credential containing
# a character which is structural in a URL cannot be represented here; refuse
# rather than send a silently wrong signature.
case "$MINIO_ACCESS_KEY$MINIO_SECRET_KEY" in
    *[@:/?#]*|*[[:space:]]*)
        echo "Error: MINIO_ACCESS_KEY or MINIO_SECRET_KEY contains one of @ : / ? # or whitespace." >&2
        echo "Those cannot be passed to mc through MC_HOST. Rotate the credential to one" >&2
        echo "without them, or configure an mc alias manually and adjust this script." >&2
        exit 1
        ;;
esac
MC_HOST_VALUE="$MINIO_SCHEME://$MINIO_ACCESS_KEY:$MINIO_SECRET_KEY@$MINIO_HOSTPORT"

mc_run() {
    env "MC_HOST_dev-cdn=$MC_HOST_VALUE" "$MC_BIN" "$@"
}

echo "--> Note: A VPN connection is required to access the MinIO server."

# 5. Check Bucket Access
echo "--> Verifying access to bucket '$MINIO_BUCKET'..."
if ! mc_run ls dev-cdn/"$MINIO_BUCKET" > /dev/null 2>&1; then
    echo "Error: Cannot access bucket '$MINIO_BUCKET'." >&2
    echo "Check your VPN connection first - that is the most common cause." >&2
    echo "Then verify MINIO_URL, credentials, and bucket existence in $PROPERTIES_FILE." >&2
    exit 1
fi
echo "    [OK] Bucket is accessible."

echo "----------------------------------------"

# Helper to resolve MOCK_PATH from properties and clean it
resolve_mock_path() {
    local path="$1"
    local cdn_file="$SCRIPT_DIR/cdn_locations.properties"
    
    # If the provided path doesn't contain a slash, it might be a key.
    # Matched literally (not as a regex) and the whole remainder of the line is
    # taken, so values containing '=' are not truncated.
    if [[ ! "$path" == *"/"* ]] && [ -f "$cdn_file" ]; then
        local resolved
        resolved=$(awk -v k="$path" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$cdn_file")
        if [ -n "$resolved" ]; then
            # Print to stderr so it doesn't get captured by $(...)
            echo "--> Resolved key '$path' to path: $resolved" >&2
            path="$resolved"
        fi
    fi
    
    # Strip leading slashes to prevent writing/uploading to root filesystem path
    path="${path#/}"
    
    # Always have a default start path as $BASE_SEG
    if [[ "$path" != "$BASE_SEG/"* ]] && [[ "$path" != "$BASE_SEG" ]]; then
        path="$BASE_SEG/$path"
    fi

    # Refuse '..' segments: they would let a crafted key or path escape
    # $BASE_SEG, both for the remote object key and for the local download target.
    case "/$path/" in
        */../*)
            echo "Error: path may not contain '..' segments: $path" >&2
            return 1
            ;;
    esac

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
        RESOLVED_PATH=$(resolve_mock_path "$TARGET_ARG") || exit 1
        TARGET_FILE="$RESOLVED_PATH"
        MOCK_PATH="$RESOLVED_PATH"
    else
        # If two arguments are provided, resolve the mock path normally
        MOCK_PATH=$(resolve_mock_path "$MOCK_ARG") || exit 1
        TARGET_FILE=$TARGET_ARG
    fi

    if [ ! -f "$TARGET_FILE" ]; then
        echo "Error: Local file '$TARGET_FILE' does not exist."
        exit 1
    fi

    echo "Uploading '$TARGET_FILE'..."
    echo "Destination: dev-cdn/$MINIO_BUCKET/$MOCK_PATH"
    
    if ! mc_run cp "$TARGET_FILE" "dev-cdn/$MINIO_BUCKET/$MOCK_PATH"; then
        echo "Error: Upload failed for '$TARGET_FILE'." >&2
        exit 1
    fi
    echo "--> Upload complete!"

elif [ "$COMMAND" = "download" ]; then
    MOCK_PATH=$(resolve_mock_path "$2") || exit 1

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
    
    if ! mc_run cp "dev-cdn/$MINIO_BUCKET/$MOCK_PATH" "$MOCK_PATH"; then
        echo "Error: Download failed for 'dev-cdn/$MINIO_BUCKET/$MOCK_PATH'." >&2
        exit 1
    fi
    echo "--> Download complete!"

else
    echo "Unknown command: $COMMAND"
    show_usage
fi
