"""LectureRecorder 전사 작업기. transcribe.sh가 전사 도구 가상환경의 Python으로 실행한다.

사용: transcribe_worker.py <녹음> <결과.json> <진행.json> <앱 pid> [<이어하기.json>]

1. 녹음을 macOS 기본 afconvert로 16kHz 모노 wav로 바꾼다 (원본은 읽기만 한다).
2. 약 3분씩 잘라 mlx-audio의 Qwen3-ASR(1.7B-8bit, 한국어)로 전사한다.
3. 조각마다 진행 파일({"done", "total"})을 쓰고, <진행.json>.cancel 파일이 생기거나 앱이 꺼지면 멈춘다.
4. <이어하기.json>을 주면 조각마다 끝낸 조각과 글({"done", "total", "segments"})을 남기고,
   다음에 같은 파일로 부르면 끝낸 조각은 건너뛰고 이어서 한다 ("멈춤" 뒤 "이어서").
5. 끝나면 결과({"model", "segments": [{"start", "end", "text"}]})를 한 번에 쓴다.
6. 오류는 stderr와 함께 <진행.json>.log에도 남긴다. 앱이 실패 줄 아래에 마지막 몇 줄을 보인다.
"""

import json
import os
import subprocess
import sys
import tempfile
import traceback
import wave

MODEL = "mlx-community/Qwen3-ASR-1.7B-8bit"
LANGUAGE = "Korean"
CHUNK_SECONDS = 180

EXIT_BAD_ARGS = 2
EXIT_CONVERT = 21
EXIT_MODEL = 22
EXIT_TRANSCRIBE = 23
EXIT_CANCELLED = 40


ERROR_LOG = None


def log(message):
    print(f"[worker] {message}", file=sys.stderr, flush=True)
    if ERROR_LOG:
        try:
            with open(ERROR_LOG, "a", encoding="utf-8") as handle:
                handle.write(message + "\n")
        except OSError as error:
            print(f"[worker] 오류 기록 실패: {error!r}", file=sys.stderr, flush=True)


def write_atomic(path, payload):
    directory = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".tmp-", suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False)
    os.replace(tmp, path)


def app_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def should_stop(progress_path, pid):
    return os.path.exists(progress_path + ".cancel") or not app_alive(pid)


def convert(source, target):
    result = subprocess.run(
        ["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", source, target],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        log(f"afconvert 실패: {result.stderr.strip()}")
        sys.exit(EXIT_CONVERT)


def split(wav_path, work_dir):
    """(조각 경로, 시작 초) 목록."""
    chunks = []
    with wave.open(wav_path, "rb") as source:
        rate = source.getframerate()
        params = source.getparams()
        frames_per_chunk = rate * CHUNK_SECONDS
        index = 0
        while True:
            frames = source.readframes(frames_per_chunk)
            if not frames:
                break
            path = os.path.join(work_dir, f"chunk-{index:04d}.wav")
            with wave.open(path, "wb") as target:
                target.setparams(params)
                target.writeframes(frames)
            chunks.append((path, index * CHUNK_SECONDS))
            index += 1
    return chunks


def field(item, name):
    if isinstance(item, dict):
        return item.get(name)
    return getattr(item, name, None)


def segments_of(result, offset, chunk_length):
    raw = field(result, "segments") or []
    segments = []
    for item in raw:
        text = (field(item, "text") or "").strip()
        if not text:
            continue
        start = float(field(item, "start") or 0)
        end = float(field(item, "end") or start)
        segments.append({"start": offset + start, "end": offset + end, "text": text})
    if not segments:
        text = (field(result, "text") or "").strip()
        if text:
            segments.append({"start": float(offset), "end": float(offset + chunk_length), "text": text})
    return segments


def load_resume(path, total):
    """이어 할 조각 번호와 그때까지의 글. 없거나 녹음이 달라졌으면 처음부터."""
    if not path or not os.path.exists(path):
        return 0, []
    try:
        with open(path, encoding="utf-8") as handle:
            saved = json.load(handle)
        done = int(saved.get("done", 0))
        segments = list(saved.get("segments", []))
        if saved.get("total") != total or not 0 <= done <= total:
            log("이어하기 기록이 이 녹음과 맞지 않아 처음부터 해요")
            return 0, []
        return done, segments
    except (OSError, ValueError, TypeError, AttributeError) as error:
        log(f"이어하기 기록을 읽지 못해 처음부터 해요: {error!r}")
        return 0, []


def main():
    global ERROR_LOG
    if len(sys.argv) not in (5, 6) or not sys.argv[4].isdigit():
        log("인자: <녹음> <결과.json> <진행.json> <앱 pid> [<이어하기.json>]")
        sys.exit(EXIT_BAD_ARGS)
    source, output, progress, pid = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    resume = sys.argv[5] if len(sys.argv) == 6 and sys.argv[5] else None
    ERROR_LOG = progress + ".log"

    with tempfile.TemporaryDirectory(prefix="lecture-transcribe-") as work:
        wav = os.path.join(work, "audio.wav")
        convert(source, wav)
        chunks = split(wav, work)
        os.remove(wav)
        total = max(len(chunks), 1)
        start, segments = load_resume(resume, total)
        if start > 0:
            log(f"조각 {start}/{total}부터 이어서 해요")
        write_atomic(progress, {"done": start, "total": total})

        if start >= total:
            # 지난번에 조각을 다 끝냈다(앱이 결과를 저장하지 못해 다시 시도). 모델 없이 결과만 다시 쓴다.
            write_atomic(output, {"model": MODEL, "segments": segments})
            return

        try:
            from mlx_audio.stt import load

            model = load(MODEL)
        except Exception as error:  # noqa: BLE001 - 무엇이든 앱에 코드로 알린다
            log(f"모델 불러오기 실패: {error!r}")
            sys.exit(EXIT_MODEL)

        for done, (path, offset) in enumerate(chunks):
            if done < start:
                os.remove(path)
                continue
            if should_stop(progress, pid):
                log("취소됨")
                sys.exit(EXIT_CANCELLED)
            with wave.open(path, "rb") as chunk:
                length = chunk.getnframes() / float(chunk.getframerate())
            try:
                result = model.generate(path, language=LANGUAGE)
            except Exception as error:  # noqa: BLE001
                log(f"전사 실패(조각 {done}): {error!r}")
                sys.exit(EXIT_TRANSCRIBE)
            segments.extend(segments_of(result, offset, length))
            os.remove(path)
            if resume:
                write_atomic(resume, {"done": done + 1, "total": total, "segments": segments})
            write_atomic(progress, {"done": done + 1, "total": total})

        write_atomic(output, {"model": MODEL, "segments": segments})


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001 - 예상 못 한 오류도 앱의 실패 줄에 보이게 남긴다
        log(traceback.format_exc().strip())
        sys.exit(EXIT_TRANSCRIBE)
