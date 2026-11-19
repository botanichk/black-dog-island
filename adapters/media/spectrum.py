#!/usr/bin/env python3
# Визуализатор для вкладки "Медиа": спектр звука из колонок.
#
# Откуда звук: parec снимает @DEFAULT_MONITOR@ - ровно то, что слышно в
# колонках. cava в системе не установлен (и без разрешения владельца мы его
# не ставим), поэтому FFT считаем сами: numpy (пакет python-numpy уже стоит),
# окно Ханна, BANDS полос с геометрическим шагом 40 Гц .. 16 кГц.
#
# Что печатаем: одну строку JSON на кадр - массив из BANDS чисел 0..1.
# Каждое число - уровень своей полосы после сглаживания (вверх быстро,
# вниз медленно, как в Noctalia: столбики не дёргаются).
#
# Почему числа, а не глифы: в GTK3 нельзя задать нулевой интерлиньяж, и
# строки из блоков ▁▂▃ шли бы с щелями. Вкладка рисует полосы обычными box
# (две плашки на полосу по :width, растут от вертикальной оси влево и вправо,
# как setMirrored + setCentered у Noctalia); progress не подошёл - GTK3
# заливает его не от края, и полоса выходила не той формы.
#
# Пока плеер на паузе, parec не держим: раз в секунду спрашиваем MPRIS,
# не началось ли воспроизведение, и печатаем гаснущий до нуля кадр.
#
# usage: spectrum.py    (печатает кадр ~20 раз в секунду)

import json
import os
import signal
import subprocess
import sys
import time

try:
    import numpy as np
except ImportError:  # без numpy визуализатор просто не рисуется
    sys.stderr.write("spectrum: нет numpy, визуализатор выключен\n")
    sys.exit(1)

RATE = 44100
# Кусок 1470 сэмплов = 33 мс. Это не косметика: раньше стояло 4096 (93 мс),
# и кадр физически не мог выйти чаще ~11 раз в секунду - столбики дёргались.
# При 33 мс выходит ~30 кадров в секунду, а FFT одного кадра стоит 0.5 мс,
# поэтому CPU остаётся почти нулевым. 30 fps - ровный шаг, делит 44.1 кГц.
CHUNK = 1470
NFFT = 8192                     # нули добираем: бин 5.4 Гц, низкие полосы не пустеют
BANDS = 16
LO_HZ, HI_HZ = 40.0, 16000.0
DB_MIN, DB_MAX = -66.0, -10.0   # диапазон громкости, растянутый на всю высоту
RISE, FALL = 0.62, 0.14         # сглаживание: вверх быстро, вниз медленно
IDLE_EVERY = 1.0                # пауза между попытками, когда звука нет

_proc = None


def _cleanup(*_):
    """Eww убивает всю группу процессов: parec уводим за собой, без сирот."""
    global _proc
    if _proc is not None:
        try:
            _proc.terminate()
            _proc.wait(timeout=1)
        except (OSError, subprocess.TimeoutExpired):
            pass
        _proc = None
    sys.exit(0)


def _emit(levels):
    """Один кадр. Закрытый pipe (Eww закрыл хаб) - штатный выход, не трейсбек."""
    frame = json.dumps([round(float(v), 3) for v in levels], separators=(",", ":"))
    try:
        sys.stdout.write(frame + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        _cleanup()


def _start_parec():
    return subprocess.Popen(
        [
            "parec",
            "--format=float32le",
            "--rate=%d" % RATE,
            "--channels=1",
            "--device=@DEFAULT_MONITOR@",
            "--latency-msec=40",
            "--raw",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
    )


def _read_exact(stream, size):
    """read(n) у pipe может вернуть меньше - добираем до полного кадра."""
    buf = stream.read(size)
    if not buf:
        return b""
    while len(buf) < size:
        more = stream.read(size - len(buf))
        if not more:
            break
        buf += more
    return buf


def _band_bins():
    """FFT-бины каждой полосы: края по геометрии от LO_HZ до HI_HZ."""
    freqs = np.fft.rfftfreq(NFFT, 1.0 / RATE)
    edges = np.geomspace(LO_HZ, HI_HZ, BANDS + 1)
    out = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        idx = np.nonzero((freqs >= lo) & (freqs < hi))[0]
        if idx.size == 0:
            idx = np.array([min(int(round(lo * NFFT / RATE)), freqs.size - 1)])
        out.append(idx)
    return out


def _playing():
    """Играет ли хоть один плеер MPRIS. Тихо: false, если busctl не ответил."""
    try:
        out = subprocess.run(
            [os.path.expanduser("~/eww-island/adapters/media/mpris.sh"), "status"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return out.stdout.strip() == "playing"
    except (OSError, subprocess.SubprocessError):
        return False


def main():
    global _proc
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, _cleanup)

    window = np.hanning(CHUNK).astype(np.float32)
    # Нормировка на сумму окна: дБ считаются относительно полной шкалы,
    # поэтому уровень не зависит от длины куска.
    spec_norm = 2.0 / float(window.sum())
    bins = _band_bins()
    levels = np.zeros(BANDS, dtype=np.float32)
    size = CHUNK * 4          # float32, моно

    while True:
        # Пауза: parec не держим, столбики плавно гаснут до нуля.
        if _proc is None:
            if not _playing():
                levels *= 1.0 - FALL
                levels[levels < 0.02] = 0.0
                _emit(levels)
                time.sleep(IDLE_EVERY)
                continue
            try:
                _proc = _start_parec()
            except OSError:
                _emit(levels)
                time.sleep(IDLE_EVERY)
                continue

        raw = _read_exact(_proc.stdout, size)
        if not raw:
            # parec умер посреди работы: закрываем и уходим в паузу.
            try:
                _proc.terminate()
                _proc.wait(timeout=1)
            except (OSError, subprocess.TimeoutExpired):
                pass
            _proc = None
            continue

        samples = np.frombuffer(raw, dtype="<f4")
        if samples.size < CHUNK:
            continue

        spec = np.abs(np.fft.rfft(samples[:CHUNK] * window, n=NFFT)) * spec_norm
        band = np.array([spec[idx].mean() for idx in bins], dtype=np.float32)
        db = 20.0 * np.log10(band + 1e-9)
        target = np.clip((db - DB_MIN) / (DB_MAX - DB_MIN), 0.0, 1.0)

        alpha = np.where(target > levels, RISE, FALL)
        levels += (target - levels) * alpha

        _emit(levels)


if __name__ == "__main__":
    main()
