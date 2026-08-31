#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR="$SCRIPT_DIR/original"
REPORT_FILE="${1:-$SCRIPT_DIR/encoding-time-report.md}"
RUNS="${RUNS:-1}"

command -v ffmpeg >/dev/null 2>&1 || {
    echo "Error: ffmpeg is not installed or is not in PATH." >&2
    exit 1
}
[[ -d "$SOURCE_DIR" ]] || {
    echo "Error: source directory does not exist: $SOURCE_DIR" >&2
    exit 1
}
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || {
    echo "Error: RUNS must be a positive integer." >&2
    exit 1
}

data_file=$(mktemp)
output_dir=$(mktemp -d)
trap 'rm -f -- "$data_file"; rm -rf -- "$output_dir"' EXIT

elapsed_ms() {
    local start_ns=$1 end_ns=$2
    awk -v start="$start_ns" -v end="$end_ns" 'BEGIN { printf "%.3f", (end - start) / 1000000 }'
}

failed=0
while IFS= read -r -d '' source; do
    relative=${source#"$SOURCE_DIR"/}
    resolution=${relative%%/*}
    remainder=${relative#*/}
    image_type=${remainder%%/*}

    for ((run = 1; run <= RUNS; run++)); do
        printf 'Encoding (%d/%d): %s\n' "$run" "$RUNS" "$relative"

        start_ns=$(date +%s%N)
        if ffmpeg -hide_banner -loglevel error -nostdin -y -i "$source" \
            -map_metadata 0 -frames:v 1 -c:v libaom-av1 \
            -crf 0 -b:v 0 -still-picture 1 -cpu-used 4 \
            "$output_dir/output.avif"; then
            end_ns=$(date +%s%N)
            avif_ms=$(elapsed_ms "$start_ns" "$end_ns")
        else
            printf 'AVIF failed: %s (run %d)\n' "$relative" "$run" >&2
            ((failed += 1))
            continue
        fi

        start_ns=$(date +%s%N)
        if ffmpeg -hide_banner -loglevel error -nostdin -y -i "$source" \
            -map_metadata 0 -frames:v 1 -c:v libwebp \
            -lossless 1 -compression_level 6 \
            "$output_dir/output.webp"; then
            end_ns=$(date +%s%N)
            webp_ms=$(elapsed_ms "$start_ns" "$end_ns")
        else
            printf 'WebP failed: %s (run %d)\n' "$relative" "$run" >&2
            ((failed += 1))
            continue
        fi

        printf '%s\t%s\t%s\t%s\n' \
            "$resolution" "$image_type" "$avif_ms" "$webp_ms" >> "$data_file"
    done
done < <(find "$SOURCE_DIR" -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0 | sort -z)

[[ -s "$data_file" ]] || {
    echo "Error: no successful encoding measurements." >&2
    exit 1
}

awk -F '\t' -v runs="$RUNS" '
function seconds(ms) { return sprintf("%.3f", ms / 1000) }
function ratio(a, w) { return sprintf("%.2fx", a / w) }
{
    key = $1 SUBSEP $2
    count[key]++; avif[key] += $3; webp[key] += $4
    total_count++; total_avif += $3; total_webp += $4
}
END {
    print "# Время lossless-кодирования AVIF и WebP"
    print ""
    printf "Каждый файл закодирован %d раз. Время включает запуск FFmpeg, чтение исходника и запись временного результата. Меньше — лучше.\n", runs
    print ""
    print "| Разрешение | Тип | Замеров | AVIF всего, с | WebP всего, с | AVIF среднее, с | WebP среднее, с | AVIF / WebP |"
    print "|---|---|---:|---:|---:|---:|---:|---:|"
    order[1] = "768x432"; order[2] = "1920x1080"; order[3] = "3840x2160"
    types[1] = "illustration"; types[2] = "photo"
    for (i = 1; i <= 3; i++) for (j = 1; j <= 2; j++) {
        key = order[i] SUBSEP types[j]
        if (count[key]) {
            label = (types[j] == "illustration" ? "Иллюстрация" : "Фото")
            printf "| %s | %s | %d | %s | %s | %s | %s | %s |\n", \
                order[i], label, count[key], seconds(avif[key]), seconds(webp[key]), \
                seconds(avif[key] / count[key]), seconds(webp[key] / count[key]), \
                ratio(avif[key], webp[key])
        }
    }
    printf "| **Итого** | **Все типы** | **%d** | **%s** | **%s** | **%s** | **%s** | **%s** |\n", \
        total_count, seconds(total_avif), seconds(total_webp), \
        seconds(total_avif / total_count), seconds(total_webp / total_count), \
        ratio(total_avif, total_webp)
}
' "$data_file" > "$REPORT_FILE"

printf 'Report written: %s\nMeasurements: %s; failures: %s\n' \
    "$REPORT_FILE" "$(wc -l < "$data_file")" "$failed"
((failed == 0))
