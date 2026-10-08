#!/bin/bash

# Pastikan gcloud CLI sudah terinstal
if ! command -v gcloud &> /dev/null; then
    echo "❌ Error: gcloud CLI belum terinstal. Silakan instal terlebih dahulu."
    exit 1
fi

# Fungsi untuk menampilkan petunjuk penggunaan
usage() {
    echo "Penggunaan: $0 -i <INSTANCE_NAME> [-p <PROJECT_ID>]"
    echo "  -i  : Nama instance Cloud SQL (Wajib)"
    echo "  -p  : Project ID Google Cloud (Opsional)"
    exit 1
}

# Parsing argumen input
while getopts "i:p:" opt; do
    case ${opt} in
        i ) INSTANCE_NAME=$OPTARG ;;
        p ) PROJECT_ID=$OPTARG ;;
        \? ) usage ;;
    esac
done

# Validasi parameter wajib
if [ -z "$INSTANCE_NAME" ]; then
    echo "❌ Error: Nama instance Cloud SQL harus diisi!"
    usage
fi

# Tentukan project flag jika PROJECT_ID diberikan
PROJECT_FLAG=""
if [ ! -z "$PROJECT_ID" ]; then
    PROJECT_FLAG="--project=$PROJECT_ID"
fi

echo "=========================================================================="
echo "🔍 Mengambil Semua Backup ON-DEMAND untuk instance: $INSTANCE_NAME"
echo "=========================================================================="

# 1. Mendapatkan list Backup ID yang hanya bertipe ON_DEMAND
# Diurutkan berdasarkan waktu pembuatan terbaru (~windowStartTime)
echo "⌛ Mengambil data dari Google Cloud..."
BACKUP_IDS=$(gcloud sql backups list \
    --instance="$INSTANCE_NAME" \
    $PROJECT_FLAG \
    --filter="type=ON_DEMAND" \
    --sort-by="~windowStartTime" \
    --format="value(id)")

if [ -z "$BACKUP_IDS" ]; then
    echo "⚠️  Tidak ditemukan backup dengan tipe ON-DEMAND pada instance ini."
    echo "=========================================================================="
    exit 0
fi

# Cetak header tabel output
echo -e "\n📊 DAFTAR DETAIL BACKUP ON-DEMAND:"
printf "%-15s | %-25s | %-12s | %-20s\n" "BACKUP ID" "CREATED TIME (UTC)" "STATUS" "CHARGEABLE SIZE"
echo "--------------------------------------------------------------------------"

# 2. Iterasi untuk setiap Backup ID guna mendapatkan detail maxChargeableBytes
for BACKUP_ID in $BACKUP_IDS; do
    # Jalankan describe untuk mendapatkan startTime, status, dan maxChargeableBytes secara bersamaan (lebih efisien)
    BACKUP_DETAIL=$(gcloud sql backups describe "$BACKUP_ID" \
        --instance="$INSTANCE_NAME" \
        $PROJECT_FLAG \
        --format="value(windowStartTime, status, maxChargeableBytes)")
    
    # Parsing hasil output query (dipisahkan oleh tab/spasi)
    CREATED_TIME=$(echo "$BACKUP_DETAIL" | awk '{print $1}')
    STATUS=$(echo "$BACKUP_DETAIL" | awk '{print $2}')
    MAX_BYTES=$(echo "$BACKUP_DETAIL" | awk '{print $3}')

    # Menangani jika maxChargeableBytes kosong atau null
    if [ -z "$MAX_BYTES" ] || [ "$MAX_BYTES" = "None" ]; then
        MAX_BYTES=0
    fi

    # Konversi bytes ke format yang mudah dibaca (MB)
    if [ "$MAX_BYTES" -gt 0 ]; then
        MAX_MB=$(echo "scale=2; $MAX_BYTES / 1024 / 1024" | bc 2>/dev/null || awk "BEGIN {print $MAX_BYTES/1024/1024}")
        SIZE_DISPLAY="${MAX_MB} MB"
    else
        SIZE_DISPLAY="0 MB"
    fi

    # Tampilkan baris data
    printf "%-15s | %-25s | %-12s | %-20s\n" "$BACKUP_ID" "$CREATED_TIME" "$STATUS" "$SIZE_DISPLAY ($MAX_BYTES Bytes)"
done

echo "=========================================================================="
