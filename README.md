# eSewa Local CDN Sync Tool

This tool helps developers quickly upload and download mock CDN assets to our MinIO development server, perfectly mirroring the file structures required by the eSewa Android project.

## 🚀 Setup Instructions

1. **Install MinIO Client (`mc`)**
   - **Mac (Intel):** Download the binary directly into this folder:
     `curl -L -s https://dl.min.io/client/mc/release/darwin-amd64/mc -o mc && chmod +x mc`
   - **Mac (Apple Silicon):**
     `curl -L -s https://dl.min.io/client/mc/release/darwin-arm64/mc -o mc && chmod +x mc`
   - **Linux:**
     `wget https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc`
   - *Alternatively, you can install it globally via Homebrew:* `brew install minio/stable/mc`

2. **Configure Credentials**
   - Copy `minio.properties.template` to a new file named `minio.properties`.
   - Open `minio.properties` and fill in the `MINIO_ACCESS_KEY` and `MINIO_SECRET_KEY` for the development server.

3. **Connect to VPN**
   - Make sure your **GlobalProtect VPN (ESEWA-SECURE-GATEWAY)** is connected, otherwise the script will safely block the transfer.

---

## 🛠 Usage

This script automatically resolves CDN path constants from the Android project (like `CASH_POINT_LOCATION_API`) into their actual folder structures and manages the `esewa_gprs/` prefixing automatically.

### Uploading a File
If your local file is already in the correct `esewa_gprs/` mock structure, simply upload it by passing the API key!

```bash
./minio_sync.sh upload ACADEMY_DATA_COLLECT_INFO
```
*(This automatically resolves the key to `esewa_gprs/academy/academy_message.json`, finds the local file, and uploads it to the identical path on MinIO).*

If your local file is in a random location, you can specify both the local file and the target key/path:
```bash
./minio_sync.sh upload ~/Downloads/test.json ACADEMY_DATA_COLLECT_INFO
```

### Downloading a File
```bash
./minio_sync.sh download CASH_POINT_LOCATION_API
```
*(This automatically creates the `esewa_gprs/cash_point/` folders locally if they don't exist, and downloads the file from the MinIO server).*

---

### Reference
Check `cdn_locations.properties` to see all 114 supported keys!
