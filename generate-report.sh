#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AVIF_DIR="$SCRIPT_DIR/avif"
WEBP_DIR="$SCRIPT_DIR/webp"
REPORT_FILE="${1:-$SCRIPT_DIR/compression-report.md}"

[[ -d "$AVIF_DIR" ]] || {
    echo "Error: AVIF directory does not exist: $AVIF_DIR" >&2
    exit 1
}
[[ -d "$WEBP_DIR" ]] || {
    echo "Error: WebP directory does not exist: $WEBP_DIR" >&2
    exit 1
}

data_file=$(mktemp)
trap 'rm -f -- "$data_file"' EXIT

missing=0
while IFS= read -r -d '' avif; do
    relative=${avif#"$AVIF_DIR"/}
    resolution=${relative%%/*}
    remainder=${relative#*/}
    image_type=${remainder%%/*}
    stem=${relative%.avif}
    webp="$WEBP_DIR/$stem.webp"

    if [[ ! -f "$webp" ]]; then
        printf 'Missing WebP counterpart: %s\n' "$stem" >&2
        ((missing += 1))
        continue
    fi

    printf '%s\t%s\t%s\t%s\n' \
        "$resolution" "$image_type" \
        "$(stat -c '%s' -- "$avif")" "$(stat -c '%s' -- "$webp")" \
        >> "$data_file"
done < <(find "$AVIF_DIR" -type f -iname '*.avif' -print0)

if [[ ! -s "$data_file" ]]; then
    echo "Error: no matching image pairs found." >&2
    exit 1
fi

awk -F '\t' '
function mib(bytes) { return sprintf("%.2f", bytes / 1048576) }
function kib(bytes) { return sprintf("%.1f", bytes / 1024) }
function ratio(a, w) { return sprintf("%.2f%%", a / w * 100) }
function saving(a, w) { return sprintf("%.2f%%", (w - a) / w * 100) }
{
    key = $1 SUBSEP $2
    count[key]++
    avif[key] += $3
    webp[key] += $4
    resolution[key] = $1
    type[key] = $2
    total_count++
    total_avif += $3
    total_webp += $4
}
END {
    print "# Отчёт о lossless-сжатии AVIF и WebP"
    print ""
    print "Размеры указаны для файлов, полученных из одного набора исходников в lossless-режимах кодеков. Экономия рассчитана относительно WebP: `(WebP − AVIF) / WebP × 100%`."
    print ""
    print "| Разрешение | Тип | Файлов | AVIF, MiB | WebP, MiB | Средний AVIF, KiB | Средний WebP, KiB | AVIF / WebP | Экономия AVIF |"
    print "|---|---|---:|---:|---:|---:|---:|---:|---:|"

    # The known directory names sort naturally by pixel width in this order.
    order[1] = "768x432"; order[2] = "1920x1080"; order[3] = "3840x2160"
    types[1] = "illustration"; types[2] = "photo"
    for (i = 1; i <= 3; i++) {
        for (j = 1; j <= 2; j++) {
            key = order[i] SUBSEP types[j]
            if (count[key]) {
                label = (types[j] == "illustration" ? "Иллюстрация" : "Фото")
                printf "| %s | %s | %d | %s | %s | %s | %s | %s | %s |\n", \
                    order[i], label, count[key], mib(avif[key]), mib(webp[key]), \
                    kib(avif[key] / count[key]), kib(webp[key] / count[key]), \
                    ratio(avif[key], webp[key]), saving(avif[key], webp[key])
            }
        }
    }

    printf "| **Итого** | **Все типы** | **%d** | **%s** | **%s** | **%s** | **%s** | **%s** | **%s** |\n", \
        total_count, mib(total_avif), mib(total_webp), \
        kib(total_avif / total_count), kib(total_webp / total_count), \
        ratio(total_avif, total_webp), saving(total_avif, total_webp)
    print ""
    printf "Итого AVIF занимает **%s** от размера WebP и экономит **%s** (**%s MiB**) на всём наборе.\n", \
        ratio(total_avif, total_webp), saving(total_avif, total_webp), \
        mib(total_webp - total_avif)
}
' "$data_file" > "$REPORT_FILE"

printf 'Report written: %s\n' "$REPORT_FILE"
printf 'Compared pairs: %s; missing pairs: %s\n' \
    "$(wc -l < "$data_file")" "$missing"

((missing == 0))
