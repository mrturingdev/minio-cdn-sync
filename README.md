# MinIO CDN Sync Tool

This tool helps developers quickly upload and download mock CDN assets to our MinIO development server, perfectly mirroring the file structures required by your project.

## 🚀 Setup Instructions

1. **Install MinIO Client (`mc`)**
   - **Mac (Intel):** Download the binary directly into this folder:
     `curl -L -s https://dl.min.io/client/mc/release/darwin-amd64/mc -o mc && chmod +x mc`
   - **Mac (Apple Silicon):**
     `curl -L -s https://dl.min.io/client/mc/release/darwin-arm64/mc -o mc && chmod +x mc`
   - **Linux:** Download into this folder as well:
     `wget https://dl.min.io/client/mc/release/linux-amd64/mc -O mc && chmod +x mc`
   - *Alternatively, you can install it globally via Homebrew:* `brew install minio/stable/mc`
   - The script hands credentials to `mc` through the `MC_HOST_dev-cdn` environment
     variable, so it needs a reasonably recent `mc`. Verified against
     `RELEASE.2025-08-13`; any current release works.
   - **Note:** if a local `./mc` binary exists in this folder, it takes priority over a
     globally installed one. Delete the local copy if you want to use the Homebrew version.

2. **Configure Credentials**
   - Copy `minio.properties.template` to a new file named `minio.properties`.
   - Fill in the MinIO URL, access key, secret key, and bucket.
     *Credentials are issued by the Development team — ask them if you do not have them.*
   - Set `BASE_SEGMENT` to the base directory that assets live under, with
     **no trailing slash** — e.g. `BASE_SEGMENT=mock_dir`. A trailing slash produces
     a doubled path (`mock_dir//js/...`), which MinIO treats as a *different* object
     key, so your upload would land somewhere nobody else looks.
     If `BASE_SEGMENT` is left unset, the script falls back to `mock_dir`.
   - **Credential characters:** the access key and secret key must not contain
     `@ : / ? #` or whitespace. They are passed to `mc` through the `MC_HOST_dev-cdn`
     environment variable, which `mc` reads literally (it does not percent-decode),
     so those characters cannot be represented. `+` and `=` are fine. If a rotated
     key contains one of them, the script stops with a clear error rather than
     failing with a confusing signature mismatch.
   - This file holds real credentials. It is gitignored — keep it that way. It should
     be readable only by you (`chmod 600 minio.properties`); both properties files in
     this repo have already been set that way.

3. **Configure CDN Path Keys**
   - Copy `cdn_locations.properties.template` to a new file named `cdn_locations.properties`.
   - This file maps the `CDN_*` key names used on the command line to their real paths.
     The template ships only two example entries — obtain the full key list from the
     Development team.
   - **This step is not optional in practice.** If the file is missing, the script does
     *not* error: it silently treats whatever key you typed as a literal path and syncs
     `<BASE_SEGMENT>/YOUR_KEY_NAME` instead of the file you meant.
   - To find a valid key, grep this file, e.g. `grep -i <keyword> cdn_locations.properties`.

4. **Connect to VPN**
   - A VPN connection is required to reach the MinIO server.
   - Note that the script does **not** test the VPN itself. If you are disconnected,
     it fails at the bucket-access check with "Cannot access bucket", which names the
     VPN as the most likely cause.

---

## 🛠 Usage

This script resolves CDN path constants from `cdn_locations.properties` into their actual
folder structures and applies the `BASE_SEGMENT` prefix automatically.

Run it from this directory. Configuration is read relative to the script, but local files
and created folders resolve against your **current working directory** — invoking it by
absolute path from elsewhere will create a stray base-segment folder there.

### Uploading a File
If your local file is already in the correct `<BASE_SEGMENT>/` structure, upload it by
passing the key:

```bash
./minio_sync.sh upload CDN_FILE_LOCATION
```
*(This resolves the key to its configured path, finds the local file, and uploads it to the identical path on MinIO).*

⚠️ **Upload overwrites the remote object without confirmation.** There is no versioning,
prompt, or dry-run. If a teammate put a different file at that path, your upload replaces
it. Double-check the destination line the script prints before it transfers.

If your local file lives somewhere else, pass both the local path and the target key:

```bash
./minio_sync.sh upload ~/Downloads/test.json CDN_FILE_LOCATION
```
*(The local path is used exactly as you type it. The `BASE_SEGMENT` prefix is applied only to
the remote key, so the file lands at the same CDN path as the one-argument form.)*

### Downloading a File
```bash
./minio_sync.sh download CDN_FILE_LOCATION
```
*(This automatically creates the folders locally if they don't exist, and downloads the file from the MinIO server).*

Download overwrites the local file if it already exists, and is otherwise safe to re-run.

---

## Notes

- Credentials are passed to `mc` in its environment for the duration of each call. They
  do not appear in `ps` output, and nothing is written to your global `~/.mc/config.json`
  — an existing `dev-cdn` alias in your own mc config is left untouched.
- The destination server is whatever `MINIO_URL` points at in your local
  `minio.properties`. Nothing in the script restricts it to the development server —
  verify that value before uploading.
