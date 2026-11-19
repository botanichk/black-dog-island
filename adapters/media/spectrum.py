#!/usr/bin/env python3
# Визуализатор для вкладки "Медиа": спектр звука из колонок.
#
# Откуда звук: parec снимает @DEFAULT_MONITOR@ - ровно то, что слышно в
# колонках. cava в системе не установлен (и без разрешения владельца мы его
# не ставим), поэтому FFT считаем сами: numpy (пакет python-numpy уже стоит),
# окно Ханна, BANDS полос с геометрическим шагом 40 Гц .. 16 кГц.
#
# Что печатаем: одну строку JSON на кадр - объект {"v":[...], "p":[...]}.
# v - уровень полосы 0..1 после сглаживания (вверх быстро, вниз медленно),
# p - точка пика над столбиком (как в radiofm/radio/viz/spectrum.py: вверх
# мгновенно, вниз с разгоном).
#
# Как выглядит (вид взят у radiofm/radio/viz/spectrum.py, но ось вертикальная):
# 24 тонкие полосы лежат друг под другом и растут от общей вертикальной оси
# влево и вправо, на каждом конце висит точка пика, которая мгновенно
# подскакивает и медленно падает с разгоном.
#
# Почему числа, а не глифы: в GTK3 нельзя задать нулевой интерлиньяж, и
# строки из блоков ▁▂▃ шли бы с щелями. Вкладка рисует полосы обычными box
# с :width (толщину и зазор задаёт SCSS), пики - отдельные точки по тем же
# значениям.
#
# Пока плеер на паузе, parec не держим: раз в секунду спрашиваем MPRIS,
# не началось ли воспроизведение, и печатаем гаснущий до нуля кадр.
#
# usage: spectrum.py    (печатает кадр ~55-60 раз в секунду)

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
# HOP - сколько новых сэмплов берём за кадр. 735 при 44.1 кГц = 16.7 мс, то есть
# до ~60 кадров в секунду: ровно то, что просит плавность. Раньше читали 4096
# (93 мс) и кадр физически не мог выйти чаще 11 раз в секунду - отсюда "тормоза".
HOP = 735
# WIN - окно для FFT: 2048 сэмплов (46 мс). Окно БОЛЬШЕ шага: кадры считаются
# по перекрывающимся кускам, поэтому бас не проваливается, как было бы при
# окне в 735 сэмплов (16 мс - меньше периода 40 Гц).
WIN = 2048
NFFT = 8192                     # нули добираем: бин 5.4 Гц, низкие полосы не пустеют
BANDS = 24                      # 24 полосы, как узкие столбики radiofm
LO_HZ, HI_HZ = 40.0, 16000.0
DB_MIN, DB_MAX = -66.0, -10.0   # диапазон громкости, растянутый на всю высоту
RISE, FALL = 0.62, 0.14         # сглаживание: вверх быстро, вниз медленно
PEAK_ACCEL = 1.8                # разгон падающей точки пика (как в radiofm)
IDLE_EVERY = 1.0                # пауза между попытками, когда звука нет
IDLE_FPS = 20.0                 # на тишине кадры идут реже, но пунктир «дышит»
IDLE_AMP = 0.008                # амплитуда дыхания: единицы пикселей, «еле колышется»

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


def _emit(levels, peaks=None):
    """Один кадр. Закрытый pipe (Eww закрыл хаб) - штатный выход, не трейсбек."""
    frame = json.dumps(
        {
            "v": [round(float(v), 3) for v in levels],
            "p": [round(float(v), 3) for v in (levels if peaks is None else peaks)],
        },
        separators=(",", ":"),
    )
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

    window = np.hanning(WIN).astype(np.float32)
    # Нормировка на сумму окна: дБ считаются относительно полной шкалы,
    # поэтому уровень не зависит от длины окна.
    spec_norm = 2.0 / float(window.sum())
    bins = _band_bins()
    levels = np.zeros(BANDS, dtype=np.float32)
    peaks = np.zeros(BANDS, dtype=np.float32)      # точки пика над столбиками
    peak_vel = np.zeros(BANDS, dtype=np.float32)   # скорость их падения
    buf = np.zeros(WIN, dtype=np.float32)          # скользящее окно
    size = HOP * 4            # float32, моно
    prev_t = time.monotonic()

    while True:
        # Пауза: parec не держим. Пунктир у центра не замирает насмерть -
        # уровни еле «дышат», как в radiofm и noctalia. MPRIS спрашиваем раз
        # в секунду, а кадры дыхания идут чаще: busctl на каждом кадре - лишняя
        # работа.
        if _proc is None:
            if not _playing():
                for _ in range(int(IDLE_FPS)):
                    t = time.monotonic()
                    breathe = IDLE_AMP * (0.5 + 0.5 * np.sin(t * 1.4))
                    levels = np.maximum(levels * (1.0 - FALL), breathe)
                    _emit(levels, levels)
                    time.sleep(1.0 / IDLE_FPS)
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
        if samples.size == 0:
            continue

        # Скользящее окно: старые сэмплы уходят, новые приходят с конца.
        # Окно 2048 при шаге 735 даёт перекрытие ~64%, поэтому бас гладкий,
        # а кадры идут по 16.7 мс.
        buf = np.roll(buf, -samples.size)
        buf[-samples.size:] = samples
        n = samples.size

        spec = np.abs(np.fft.rfft(buf * window, n=NFFT)) * spec_norm
        band = np.array([spec[idx].mean() for idx in bins], dtype=np.float32)
        db = 20.0 * np.log10(band + 1e-9)
        target = np.clip((db - DB_MIN) / (DB_MAX - DB_MIN), 0.0, 1.0)

        alpha = np.where(target > levels, RISE, FALL)
        levels += (target - levels) * alpha

        # Точки пика, как в radiofm: мгновенно вверх, вниз с разгоном.
        now_t = time.monotonic()
        dt = min(0.1, max(1e-3, now_t - prev_t))
        prev_t = now_t
        faster = levels >= peaks
        peaks = np.where(faster, levels, peaks)
        peak_vel = np.where(faster, 0.0, peak_vel + PEAK_ACCEL * dt)
        peaks = np.where(faster, peaks, np.maximum(levels, peaks - peak_vel * dt))

        _emit(levels, peaks)


if __name__ == "__main__":
    main()
