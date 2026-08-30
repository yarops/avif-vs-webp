#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR="$SCRIPT_DIR/original"
AVIF_DIR="$SCRIPT_DIR/avif"
WEBP_DIR="$SCRIPT_DIR/webp"

command -v ffmpeg >/dev/null 2>&1 || {
    echo "Error: ffmpeg is not installed or is not in PATH." >&2
    exit 1
}

[[ -d "$SOURCE_DIR" ]] || {
    echo "Error: source directory does not exist: $SOURCE_DIR" >&2
    exit 1
}

mkdir -p -- "$AVIF_DIR" "$WEBP_DIR"

converted=0
failed=0

while IFS= read -r -d '' source; do
    relative=${source#"$SOURCE_DIR"/}
    stem=${relative%.*}
    avif="$AVIF_DIR/$stem.avif"
    webp="$WEBP_DIR/$stem.webp"

    mkdir -p -- "$(dirname -- "$avif")" "$(dirname -- "$webp")"
    printf 'Encoding: %s\n' "$relative"

    # CRF 0 + zero target bitrate enables lossless AV1 coding in libaom.
    if ! ffmpeg -hide_banner -loglevel error -nostdin -y -i "$source" \
        -map_metadata 0 -frames:v 1 -c:v libaom-av1 \
        -crf 0 -b:v 0 -still-picture 1 -cpu-used 4 \
        "$avif"; then
        printf 'AVIF failed: %s\n' "$relative" >&2
        ((failed += 1))
        continue
    fi

    # Explicit lossless mode; level 6 favors size over encoding speed.
    if ! ffmpeg -hide_banner -loglevel error -nostdin -y -i "$source" \
        -map_metadata 0 -frames:v 1 -c:v libwebp \
        -lossless 1 -compression_level 6 \
        "$webp"; then
        printf 'WebP failed: %s\n' "$relative" >&2
        ((failed += 1))
        continue
    fi

    ((converted += 1))
done < <(find "$SOURCE_DIR" -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0)

printf '\nDone: %d image(s) converted, %d failure(s).\n' "$converted" "$failed"
printf 'AVIF: %s\nWebP: %s\n' "$AVIF_DIR" "$WEBP_DIR"

((failed == 0))
