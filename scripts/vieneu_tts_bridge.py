#!/usr/bin/env python3
"""
Vieneu TTS Bridge for DocTranslateApp
Provides CLI commands for voice discovery, single-text synthesis, and batch chapter synthesis.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

# Static fallback voice list in case Vieneu initialization is delayed
DEFAULT_PRESET_VOICES = [
    {"id": "Trúc Ly", "name": "Trúc Ly — Nữ · Bắc · Phong cách tự nhiên", "gender": "female", "region": "North"},
    {"id": "Phạm Tuyên", "name": "Phạm Tuyên — Nam · Bắc", "gender": "male", "region": "North"},
    {"id": "Bích Ngọc", "name": "Bích Ngọc — Nữ · Bắc", "gender": "female", "region": "North"},
    {"id": "Mỹ Duyên", "name": "Mỹ Duyên — Nữ · Bắc · Phong cách đọc truyện", "gender": "female", "region": "North"},
    {"id": "Đức Trí", "name": "Đức Trí — Nam · Bắc · Phong cách đọc truyện", "gender": "male", "region": "North"},
    {"id": "Hữu Quân", "name": "Hữu Quân — Nam · Bắc · Phong cách tin tức", "gender": "male", "region": "North"},
    {"id": "Xuân Tiên", "name": "Xuân Tiên — Nữ · Bắc · Phong cách tin tức", "gender": "female", "region": "North"},
    {"id": "Mai Anh", "name": "Mai Anh — Nữ · Bắc · Phong cách tin tức", "gender": "female", "region": "North"},
    {"id": "Anh Khôi", "name": "Anh Khôi — Nam · Bắc · Phong cách kể chuyện", "gender": "male", "region": "North"},
    {"id": "Minh Quân", "name": "Minh Quân — Nam · Bắc · Phong cách tự nhiên", "gender": "male", "region": "North"},
    {"id": "Mạnh Dũng", "name": "Mạnh Dũng — Nam · Bắc · Phong cách tự nhiên", "gender": "male", "region": "North"},
    {"id": "Adam", "name": "Adam — Nam · Nam · Giọng đọc tự nhiên", "gender": "male", "region": "South"},
    {"id": "Ái Hân", "name": "Ái Hân — Nữ · Nam · Phong cách tin tức", "gender": "female", "region": "South"},
]


def emit_json(data: dict) -> None:
    print(json.dumps(data, ensure_ascii=False), flush=True)


def cmd_list_voices() -> None:
    try:
        from vieneu import Vieneu
        tts = Vieneu('v3nano')
        raw_voices = tts.list_preset_voices()
        if raw_voices:
            voices = []
            for desc, voice_id in raw_voices:
                voices.append({"id": voice_id, "name": desc})
            emit_json({"status": "ok", "voices": voices})
            return
    except Exception as e:
        # Fall back to preset voices if Vieneu load throws
        pass

    emit_json({"status": "ok", "voices": DEFAULT_PRESET_VOICES})


def cmd_synthesize(args: argparse.Namespace) -> None:
    text = args.text
    if not text and args.text_file:
        text_path = Path(args.text_file)
        if not text_path.is_file():
            emit_json({"status": "error", "message": f"Text file not found: {args.text_file}"})
            sys.exit(1)
        text = text_path.read_text(encoding="utf-8")

    text = (text or "").strip()
    if not text:
        emit_json({"status": "error", "message": "Text is empty"})
        sys.exit(1)

    output_path = Path(args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        from vieneu import Vieneu
        t0 = time.time()
        tts = Vieneu('v3nano')
        speed_raw = str(args.speed).replace(",", ".") if args.speed else "1.0"
        speed = float(speed_raw)
        audio = tts.infer(text=text, voice=args.voice, speed=speed)
        tts.save(audio, str(output_path))
        elapsed = round(time.time() - t0, 3)
        emit_json({
            "status": "ok",
            "output": str(output_path),
            "voice": args.voice,
            "speed": speed,
            "duration_seconds": elapsed,
        })
    except Exception as e:
        emit_json({"status": "error", "message": str(e)})
        sys.exit(1)


def cmd_batch_synthesize(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest).resolve()
    if not manifest_path.is_file():
        emit_json({"status": "error", "message": f"Manifest file not found: {manifest_path}"})
        sys.exit(1)

    try:
        manifest_data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception as e:
        emit_json({"status": "error", "message": f"Invalid manifest JSON: {e}"})
        sys.exit(1)

    voice = manifest_data.get("voice", "Trúc Ly")
    speed_raw = str(manifest_data.get("speed", 1.0)).replace(",", ".")
    speed = float(speed_raw)
    output_dir = Path(manifest_data.get("output_dir", ".")).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    chapters = manifest_data.get("chapters", [])
    total = len(chapters)

    emit_json({"event": "start", "total": total, "voice": voice, "output_dir": str(output_dir)})

    try:
        from vieneu import Vieneu
        tts = Vieneu('v3nano')
    except Exception as e:
        emit_json({"status": "error", "message": f"Failed to load Vieneu TTS: {e}"})
        sys.exit(1)

    processed = 0
    skipped = 0
    errors = 0

    for idx, ch in enumerate(chapters):
        ch_id = ch.get("id", str(idx))
        ch_title = ch.get("title", f"Chapter {idx + 1}")
        out_filename = ch.get("output_filename", f"{idx + 1:03d}_{ch_title}.wav")
        out_path = output_dir / out_filename

        # Check resume condition
        if out_path.exists() and out_path.stat().st_size > 4096:
            skipped += 1
            emit_json({
                "event": "chapter_skip",
                "index": idx,
                "id": ch_id,
                "title": ch_title,
                "path": str(out_path),
            })
            continue

        # Get text
        ch_text = ch.get("text")
        if not ch_text and ch.get("text_file"):
            tf = Path(ch["text_file"])
            if tf.is_file():
                ch_text = tf.read_text(encoding="utf-8")

        ch_text = (ch_text or "").strip()
        if not ch_text:
            skipped += 1
            emit_json({
                "event": "chapter_skip",
                "index": idx,
                "id": ch_id,
                "title": ch_title,
                "reason": "empty_text",
            })
            continue

        emit_json({
            "event": "chapter_start",
            "index": idx,
            "id": ch_id,
            "title": ch_title,
        })

        t0 = time.time()
        try:
            audio = tts.infer(text=ch_text, voice=voice, speed=speed)
            tts.save(audio, str(out_path))
            duration = round(time.time() - t0, 3)
            processed += 1
            emit_json({
                "event": "chapter_done",
                "index": idx,
                "id": ch_id,
                "title": ch_title,
                "path": str(out_path),
                "duration_seconds": duration,
            })
        except Exception as e:
            errors += 1
            emit_json({
                "event": "chapter_error",
                "index": idx,
                "id": ch_id,
                "title": ch_title,
                "error": str(e),
            })

    emit_json({
        "event": "completed",
        "total": total,
        "processed": processed,
        "skipped": skipped,
        "errors": errors,
    })


def main() -> None:
    parser = argparse.ArgumentParser(description="Vieneu TTS CLI Bridge")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # list-voices
    subparsers.add_parser("list-voices", help="List available preset voices as JSON")

    # synthesize
    syn_parser = subparsers.add_parser("synthesize", help="Synthesize text to a .wav audio file")
    syn_parser.add_argument("--voice", type=str, default="Trúc Ly", help="Voice ID")
    syn_parser.add_argument("--speed", type=float, default=1.0, help="Speech speed multiplier")
    syn_parser.add_argument("--text", type=str, default=None, help="Text to synthesize")
    syn_parser.add_argument("--text-file", type=str, default=None, help="Path to text file")
    syn_parser.add_argument("--output", type=str, required=True, help="Output .wav path")

    # batch-synthesize
    batch_parser = subparsers.add_parser("batch-synthesize", help="Batch synthesize chapters from a manifest JSON")
    batch_parser.add_argument("--manifest", type=str, required=True, help="Path to manifest JSON file")

    args = parser.parse_args()

    if args.command == "list-voices":
        cmd_list_voices()
    elif args.command == "synthesize":
        cmd_synthesize(args)
    elif args.command == "batch-synthesize":
        cmd_batch_synthesize(args)


if __name__ == "__main__":
    main()
