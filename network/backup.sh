#!/usr/bin/env bash
set -Eeuo pipefail

# ---- CONFIG ----
PI_HOST="gooral@192.168.1.252"
DEVICE="/dev/mmcblk0"             # SD usually: /dev/mmcblk0 ; USB SSD: /dev/sda ; NVMe: /dev/nvme0n1
OUTDIR="$HOME/pi-backups/images"
KEEP_LAST=2

ZSTD_LEVEL=19
ZSTD_THREADS=0

STOP_DOCKER=0                     # 1 = stop docker during imaging (recommended)

# Estimation (sampling)
DO_ESTIMATE=1                     # 0 = skip estimate
SAMPLE_CHUNKS=6                   # how many chunks to sample
CHUNK_MIB=128                     # size of each chunk in MiB (SAMPLE_CHUNKS*CHUNK_MIB total read)
SAFETY_BUFFER_PCT=20              # require +20% free space beyond estimate

# Prompt control (for cron)
AUTO_YES="${AUTO_YES:-0}"         # AUTO_YES=1 skips prompt
# ---- END CONFIG ----

mkdir -p "$OUTDIR"

ts="$(date +%F_%H%M%S)"
img="$OUTDIR/pi-${ts}.img.zst"
meta="$OUTDIR/pi-${ts}.meta.txt"

human() { numfmt --to=iec-i --suffix=B "${1:-0}"; }

confirm_or_exit() {
  if [[ "$AUTO_YES" == "1" ]]; then return 0; fi
  read -r -p "Continue? [y/N] " ans
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]] || { echo "[INFO] Aborted."; exit 0; }
}

echo "[INFO] Target: $PI_HOST  device: $DEVICE"
echo "[INFO] Output: $img"

# Collect metadata useful during restore/debug
{
  echo "=== DATE ==="
  date -Is
  echo
  echo "=== lsblk ==="
  ssh "$PI_HOST" "lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT,MODEL,SERIAL"
  echo
  echo "=== mount ==="
  ssh "$PI_HOST" "mount"
  echo
  echo "=== sfdisk -d $DEVICE ==="
  ssh "$PI_HOST" "sudo sfdisk -d '$DEVICE' || true"
} > "$meta"

# Best-effort reduce write churn
if [[ "$STOP_DOCKER" == "1" ]]; then
  echo "[INFO] Stopping docker (best-effort)..."
  ssh "$PI_HOST" "sudo systemctl stop docker 2>/dev/null || true; sudo systemctl stop containerd 2>/dev/null || true"
fi
ssh "$PI_HOST" "sudo sync"

cleanup() {
  if [[ "$STOP_DOCKER" == "1" ]]; then
    echo "[INFO] Starting docker (best-effort)..."
    ssh "$PI_HOST" "sudo systemctl start containerd 2>/dev/null || true; sudo systemctl start docker 2>/dev/null || true" || true
  fi
}
trap cleanup EXIT

# Real raw device size
size_bytes="$(ssh "$PI_HOST" "sudo blockdev --getsize64 '$DEVICE'")"
echo "[INFO] Remote raw device size: $(human "$size_bytes") ($size_bytes bytes)"

# Free space check
avail_bytes="$(df -PB1 "$OUTDIR" | awk 'NR==2{print $4}')"
echo "[INFO] Free space at OUTDIR: $(human "$avail_bytes")"

# Heuristic compressed-size estimate
est_bytes=""
if [[ "$DO_ESTIMATE" == "1" ]]; then
  echo "[INFO] Estimating compressed size via sampling (${SAMPLE_CHUNKS}x${CHUNK_MIB}MiB)..."

  chunk_bytes=$((CHUNK_MIB * 1024 * 1024))

  # Spread sample offsets across the disk (percent)
  # Will take first SAMPLE_CHUNKS values.
  offsets_pct=(3 10 20 35 50 65 80 90 97)

  total_in=0
  total_out=0

  for pct in "${offsets_pct[@]:0:$SAMPLE_CHUNKS}"; do
    skip=$(( size_bytes * pct / 100 ))
    # align skip to 4MiB boundaries
    align=$((4 * 1024 * 1024))
    skip=$(( (skip / align) * align ))

    out_bytes="$(
      ssh "$PI_HOST" "sudo dd if='$DEVICE' iflag=skip_bytes,count_bytes skip=$skip count=$chunk_bytes status=none" \
        | zstd -T"$ZSTD_THREADS" -"${ZSTD_LEVEL}" -c \
        | wc -c
    )"

    total_in=$((total_in + chunk_bytes))
    total_out=$((total_out + out_bytes))
  done

  if [[ "$total_in" -gt 0 ]]; then
    ratio_ppm=$(( total_out * 1000000 / total_in ))   # ppm
    est_bytes=$(( size_bytes * ratio_ppm / 1000000 ))
    echo "[INFO] Estimated compressed size: ~$(human "$est_bytes")"
  fi
fi

# Required space = estimate (or raw) + buffer
need_bytes="${est_bytes:-$size_bytes}"
need_bytes=$(( need_bytes + (need_bytes * SAFETY_BUFFER_PCT / 100) ))
echo "[INFO] Required free space (+${SAFETY_BUFFER_PCT}% buffer): $(human "$need_bytes")"

if [[ "$avail_bytes" -lt "$need_bytes" ]]; then
  echo "[ERROR] Not enough free space in $OUTDIR"
  exit 1
fi

confirm_or_exit

echo "[INFO] Imaging... (this can take a while)"

if command -v pv >/dev/null 2>&1; then
  ssh "$PI_HOST" "sudo dd if='$DEVICE' bs=4M status=none" \
    | pv -s "$size_bytes" \
    | zstd -T"$ZSTD_THREADS" -"${ZSTD_LEVEL}" -o "$img"
else
  echo "[WARN] pv not found; continuing without pv progress bar"
  ssh "$PI_HOST" "sudo dd if='$DEVICE' bs=4M status=progress" \
    | zstd -T"$ZSTD_THREADS" -"${ZSTD_LEVEL}" -o "$img"
fi

echo "[INFO] Done: $img"
ls -lh "$img" "$meta"

# Rotation
echo "[INFO] Rotating to keep last $KEEP_LAST..."
ls -1t "$OUTDIR"/pi-*.img.zst 2>/dev/null | tail -n +$((KEEP_LAST+1)) | xargs -r rm -f
ls -1t "$OUTDIR"/pi-*.meta.txt 2>/dev/null | tail -n +$((KEEP_LAST+1)) | xargs -r rm -f

echo "[OK] Backup complete."
