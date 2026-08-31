#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AVIF_DIR="$SCRIPT_DIR/avif"
WEBP_DIR="$SCRIPT_DIR/webp"
REPORT_FILE="${1:-$SCRIPT_DIR/decoding-time-report.md}"
RUNS="${RUNS:-3}"

command -v ffmpeg >/dev/null 2>&1 || {
    echo "Error: ffmpeg is not installed or is not in PATH." >&2
    exit 1
}
[[ -d "$AVIF_DIR" && -d "$WEBP_DIR" ]] || {
    echo "Error: AVIF and WebP directories must exist." >&2
    exit 1
}
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || {
    echo "Error: RUNS must be a positive integer." >&2
    exit 1
}

data_file=$(mktemp)
trap 'rm -f -- "$data_file"' EXIT

elapsed_ms() {
    local start_ns=$1 end_ns=$2
    awk -v start="$start_ns" -v end="$end_ns" 'BEGIN { printf "%.3f", (end - start) / 1000000 }'
}

failed=0
while IFS= read -r -d '' avif; do
    relative=${avif#"$AVIF_DIR"/}
    stem=${relative%.avif}
    webp="$WEBP_DIR/$stem.webp"
    resolution=${relative%%/*}
    remainder=${relative#*/}
    image_type=${remainder%%/*}

    if [[ ! -f "$webp" ]]; then
        printf 'Missing WebP counterpart: %s\n' "$stem" >&2
        ((failed += 1))
        continue
    fi

    for ((run = 1; run <= RUNS; run++)); do
        printf 'Decoding (%d/%d): %s\n' "$run" "$RUNS" "$stem"

        start_ns=$(date +%s%N)
        if ffmpeg -hide_banner -loglevel error -nostdin -i "$avif" \
            -map 0:v:0 -frames:v 1 -f null -; then
            end_ns=$(date +%s%N)
            avif_ms=$(elapsed_ms "$start_ns" "$end_ns")
        else
            printf 'AVIF failed: %s (run %d)\n' "$stem" "$run" >&2
            ((failed += 1))
            continue
        fi

        start_ns=$(date +%s%N)
        if ffmpeg -hide_banner -loglevel error -nostdin -i "$webp" \
            -map 0:v:0 -frames:v 1 -f null -; then
            end_ns=$(date +%s%N)
            webp_ms=$(elapsed_ms "$start_ns" "$end_ns")
        else
            printf 'WebP failed: %s (run %d)\n' "$stem" "$run" >&2
            ((failed += 1))
            continue
        fi

        printf '%s\t%s\t%s\t%s\n' \
            "$resolution" "$image_type" "$avif_ms" "$webp_ms" >> "$data_file"
    done
done < <(find "$AVIF_DIR" -type f -iname '*.avif' -print0 | sort -z)

[[ -s "$data_file" ]] || {
    echo "Error: no successful decoding measurements." >&2
    exit 1
}

awk -F '\t' -v runs="$RUNS" '
function seconds(ms) { return sprintf("%.3f", ms / 1000) }
function millis(ms) { return sprintf("%.1f", ms) }
function ratio(a, w) { return sprintf("%.2fx", a / w) }
{
    key = $1 SUBSEP $2
    count[key]++; avif[key] += $3; webp[key] += $4
    total_count++; total_avif += $3; total_webp += $4
}
END {
    print "# Время декодирования AVIF и WebP"
    print ""
    printf "Каждый файл декодирован %d раз в null-output. Время включает запуск FFmpeg и чтение файла. Меньше — лучше.\n", runs
    print ""
    print "| Разрешение | Тип | Замеров | AVIF всего, с | WebP всего, с | AVIF среднее, мс | WebP среднее, мс | AVIF / WebP |"
    print "|---|---|---:|---:|---:|---:|---:|---:|"
    order[1] = "768x432"; order[2] = "1920x1080"; order[3] = "3840x2160"
    types[1] = "illustration"; types[2] = "photo"
    for (i = 1; i <= 3; i++) for (j = 1; j <= 2; j++) {
        key = order[i] SUBSEP types[j]
        if (count[key]) {
            label = (types[j] == "illustration" ? "Иллюстрация" : "Фото")
            printf "| %s | %s | %d | %s | %s | %s | %s | %s |\n", \
                order[i], label, count[key], seconds(avif[key]), seconds(webp[key]), \
                millis(avif[key] / count[key]), millis(webp[key] / count[key]), \
                ratio(avif[key], webp[key])
        }
    }
    printf "| **Итого** | **Все типы** | **%d** | **%s** | **%s** | **%s** | **%s** | **%s** |\n", \
        total_count, seconds(total_avif), seconds(total_webp), \
        millis(total_avif / total_count), millis(total_webp / total_count), \
        ratio(total_avif, total_webp)
}
' "$data_file" > "$REPORT_FILE"

printf 'Report written: %s\nMeasurements: %s; failures: %s\n' \
    "$REPORT_FILE" "$(wc -l < "$data_file")" "$failed"
((failed == 0))
