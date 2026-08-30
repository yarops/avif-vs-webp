# Сравнение lossless AVIF и WebP

## Вводные

- Исходники: JPEG из `original/`.
- AVIF: кодек AV1 через `libaom-av1`.
- WebP: кодек WebP через `libwebp`.
- FFmpeg: `6.1.1-3ubuntu5`.
- libaom: `3.8.2`.
- libwebp: `1.3.2`.
- В обоих случаях используется lossless-кодирование без дополнительной квантовации.

Исходные JPEG уже являются сжатыми с потерями. Lossless в этом тесте означает, что при перекодировании не добавляются новые потери кодека; качество исходного JPEG не восстанавливается.

## Параметры кодирования

AVIF:

```text
-c:v libaom-av1 -crf 0 -b:v 0 -still-picture 1 -cpu-used 4
```

- `-crf 0 -b:v 0` — lossless AV1;
- `-still-picture 1` — оптимизация для одиночного изображения;
- `-cpu-used 4` — баланс скорости кодирования и размера результата.

WebP:

```text
-c:v libwebp -lossless 1 -compression_level 6
```

- `-lossless 1` — lossless WebP;
- `-compression_level 6` — максимальное усилие сжатия libwebp.

Для обоих форматов кодируется один кадр (`-frames:v 1`), метаданные копируются (`-map_metadata 0`).

## Структура

```text
original/  исходники
avif/      результаты AVIF
webp/      результаты WebP
```

Структура поддиректорий из `original/` сохраняется в `avif/` и `webp/`.

## Запуск

```bash
./encode-lossless.sh
./generate-report.sh
```

- `encode-lossless.sh` — конвертирует исходники;
- `generate-report.sh` — создаёт `compression-report.md` с группировкой по разрешению и типу изображения.

Экономия AVIF в отчёте рассчитывается относительно WebP:

```text
(размер WebP − размер AVIF) / размер WebP × 100%
```
