"""mp3 -> PSG 세 채널 악보. assets/psg/*.mp3 를 롬에 넣을 수 있는 형태로 옮긴다.

  uv run --with numpy python gfx/psg_music.py title battle=Final_Sector_Pursuit
  uv run --with numpy python gfx/psg_music.py battle --wav   굽지 않고 들어만 본다

인자는 `파일` 또는 `쓰임=파일` 이다. 쓰임이 곧 asm 의 MUS_<쓰임> 상수라,
곡을 갈아도 부르는 자리(StartBattle 의 MUS_BATTLE 등)는 안 고쳐도 된다.

곡마다 뱅크 하나를 통째로 준다. 둘을 한 뱅크에 넣으면 8KB 를 넘고, 곡이 뱅크
경계를 넘으면 PsgInit 이 ldir 한 번으로 못 옮긴다.

원곡은 동시에 네댓 음이 울리는 꽉 찬 편곡이고 PSG 는 사각파 셋뿐이라, 옮기는
것이 아니라 **줄여서 다시 쓰는** 일이다. 그래서 결과를 wav 로 되돌려 들어 보고
고칠 수 있게 했다 - 롬에 넣어 실기로 들어 보고서야 아는 것은 너무 늦다.

어떻게 고르나
  1. 프레임(60Hz)마다 MIDI 음마다의 에너지를 잰다. FFT 를 반음 폭 띠로 묶는다.
  2. 채널마다 **맡은 음역**(BANDS)에서 제일 센 음을 고른다. 베이스부터 골라
     가며 그 음의 배음 자리를 위 띠에서 깎는다.
  3. 음 번호에 중앙값 필터를 걸어 한두 프레임짜리 떨림을 없앤다.
  4. 같은 소리가 이어지면 한 덩어리로 묶어 사건 목록으로 만든다.

PSG 음정
  클록 1789772.5Hz, 주기 = 클록 / (16 * 주파수). 12 비트라 1~4095.
"""
import io
import json
import os
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "assets", "psg")
WORK = os.path.join(ROOT, "build", "psg")

FPS = 60.0                  # MSX2 NTSC 의 VBlank. 플레이어가 프레임마다 한 번 돈다.
SR = 22050
NFFT = 4096
PSG_CLOCK = 3579545.0 / 2

MIDI_LO, MIDI_HI = 24, 100
VOICES = 3

# 채널마다 맡는 음역 (MIDI). **성부를 음역으로 가른다.**
#
# 처음에는 프레임마다 센 음 셋을 골라 '직전 음과 가까운 채널' 에 붙였는데,
# 세 채널이 모두 G1~A#6 을 오갔다. 원곡이 동시에 네댓 음인 꽉 찬 편곡이라
# 무엇이 어느 성부인지가 프레임마다 흔들린 것이다. 그렇게 나온 소리는 성부가
# 서로 건너뛰어 곡으로 안 들린다.
#
# 음역을 못박으면 채널마다 하는 일이 분명해진다 - 베이스는 베이스만 따라간다.
# 가운데가 겹치는 것은 괜찮다. 같은 음이 두 채널에 겹치는 것만 막는다.
BANDS = [(60, 90),          # 0 가락
         (48, 72),          # 1 화음
         (28, 52)]          # 2 베이스

# 배음을 깎는 비율. 낮은 음 하나가 옥타브 위(12), 5도 위(19) 자리에도
# 봉우리를 만들어서, 안 깎으면 위 채널이 베이스의 배음을 가락으로 착각한다.
HARMONICS = [(12, 0.55), (19, 0.35), (24, 0.25), (28, 0.18)]

# 음을 붙드는 세기. 지금 잡고 있는 음의 에너지가 새 후보의 이 배 이상이면
# 안 바꾼다. 1.0 이면 늘 바꾸고(옛 동작), 0 이면 영영 안 바꾼다.
HOLD = 0.55
MIN_FRAMES = 6              # 이보다 짧은 음은 앞 음에 흡수시킨다 (0.1 초)
#
# 8 로 두면 떨림은 완전히 없어지지만 가락이 69 음까지 줄어 뭉개진다. 5 로
# 내리면 109 음으로 살아나는 대신 화음/베이스에 +-1 반음 왕복이 15/22 회
# 돌아온다. 6 이 그 사이다 - 가락 92 음, 왕복 1 회.

VOL_SMOOTH = 9              # 세기를 이만큼의 프레임으로 고른다
VOL_STEP = 2                # 볼륨 눈금. 잘게 두면 사건의 3/4 이 볼륨 변화가 된다.

MEDIAN = 7                  # 이만큼의 프레임에서 중앙값 - 한두 프레임 떨림을 없앤다
SILENCE = 0.10              # 그 띠의 최대치 대비 이보다 약하면 소리 없음

NAMES = "C C# D D# E F F# G G# A A# B".split()


def note_name(m):
    return "%s%d" % (NAMES[m % 12], m // 12 - 1)


def decode(name):
    """mp3 -> 모노 wav. ffmpeg 가 하는 일이라 파이썬으로 흉내내지 않는다."""
    if not os.path.isdir(WORK):
        os.makedirs(WORK)
    src = os.path.join(SRC, name + ".mp3")
    if not os.path.exists(src):
        sys.exit("%s 가 없습니다" % src)
    out = os.path.join(WORK, name + ".wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src,
                    "-ac", "1", "-ar", str(SR), out], check=True)
    w = wave.open(out)
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    return x.astype(np.float64) / 32768


def note_energy(x):
    """프레임마다 MIDI 음별 에너지. [프레임][음]"""
    midi = np.arange(MIDI_LO, MIDI_HI)
    freqs = 440.0 * 2 ** ((midi - 69) / 12.0)
    bins = np.fft.rfftfreq(NFFT, 1.0 / SR)
    lo = np.searchsorted(bins, freqs * 2 ** (-0.5 / 12))
    hi = np.maximum(np.searchsorted(bins, freqs * 2 ** (0.5 / 12)), lo + 1)
    win = np.hanning(NFFT)
    hop = SR / FPS
    n = max(0, int((len(x) - NFFT) / hop))
    E = np.zeros((n, len(midi)))
    for i in range(n):
        s = int(i * hop)
        mag = np.abs(np.fft.rfft(x[s:s + NFFT] * win))
        for j in range(len(midi)):
            E[i, j] = mag[lo[j]:hi[j]].max()
    return midi, E


def voices(E, midi):
    """프레임마다 채널별 (음, 세기). 채널마다 제 음역에서 제일 센 음을 고른다.

    배음 때문에 낮은 음이 높은 띠에도 봉우리를 만든다. 그래서 낮은 채널부터
    골라 가며 그 음의 배음 자리를 위 띠에서 깎는다.
    """
    idx = {int(m): j for j, m in enumerate(midi)}
    n = len(E)
    raw = [[None] * n for _ in range(VOICES)]
    amps = [[0.0] * n for _ in range(VOICES)]
    held = [None] * VOICES                          # 채널마다 지금 붙들고 있는 음
    for i in range(n):
        e = E[i].copy()
        for c in range(VOICES - 1, -1, -1):         # 베이스부터
            lo, hi = BANDS[c]
            a = idx.get(lo, 0)
            b = idx.get(hi, len(e) - 1)
            seg = e[a:b]
            if not len(seg):
                continue
            j = a + int(np.argmax(seg))
            v = e[j]
            if v < E[i].max() * SILENCE:
                held[c] = None
                continue
            # **붙들기.** 지금 잡고 있는 음이 아직 새 후보에 견줄 만하면 안
            # 바꾼다. 안 그러면 봉우리가 이웃 반음 칸을 오갈 때마다 음이 따라
            # 흔들린다 - 소리로는 그것이 가장 크게 들린다.
            h = held[c]
            if h is not None:
                jh = idx.get(h)
                if jh is not None and a <= jh < b and e[jh] >= v * HOLD:
                    j, v = jh, float(e[jh])
            held[c] = int(midi[j])
            raw[c][i] = int(midi[j])
            amps[c][i] = float(v)
            for d, k in HARMONICS:                  # 이 음의 배음을 위에서 깎는다
                h = j + d
                if h < len(e):
                    e[h] = max(0.0, e[h] - v * k)
            e[j] = 0.0
    return raw, amps


def smooth(raw):
    """음 번호에 중앙값 필터. 스쳐 지나가는 한두 프레임짜리 음을 없앤다.

    평균이 아니라 중앙값이어야 한다 - 평균은 없는 음(반음 사이)을 만들어 낸다.
    """
    out = []
    h = MEDIAN // 2
    for ch in raw:
        o = []
        for i in range(len(ch)):
            w = [v for v in ch[max(0, i - h):i + h + 1] if v is not None]
            if len(w) * 2 <= MEDIAN:                # 절반 넘게 비어 있으면 쉼표
                o.append(None)
            else:
                o.append(int(np.median(w)))
        out.append(o)
    return out


def hold_min(notes):
    """MIN_FRAMES 보다 짧은 음은 앞 음에 흡수시킨다.

    붙들기로도 남는 짧은 음이 있다 - 세기가 정말로 크게 바뀌는 자리다. 그런데
    0.1 초짜리 음은 가락으로 안 들리고 떨림으로 들리므로, 앞 음을 그만큼 더
    끌어 준다. 앞이 없으면 뒤에 붙인다.
    """
    out = []
    for ch in notes:
        runs = []
        for v in ch:
            if runs and runs[-1][0] == v:
                runs[-1][1] += 1
            else:
                runs.append([v, 1])
        i = 0
        while i < len(runs) and len(runs) > 1:
            if runs[i][1] >= MIN_FRAMES:
                i += 1
                continue
            if i > 0:
                runs[i - 1][1] += runs[i][1]
                del runs[i]
                i = max(0, i - 1)                   # 늘어난 앞 런을 다시 본다
            else:
                runs[1][1] += runs[0][1]
                del runs[0]
        o = []
        for v, k in runs:
            o += [v] * k
        out.append(o)
    return out


def period(note):
    f = 440.0 * 2 ** ((note - 69) / 12.0)
    return int(round(PSG_CLOCK / (16.0 * f)))


def events(notes, amps):
    """채널마다 (볼륨, 주기 하위, 주기 상위, 이어질 프레임 수). 같은 소리가
    이어지면 한 덩어리로 묶는다 - 프레임마다 다 적으면 자료가 여섯 배다.

    **세기를 다듬고 눈금을 굵게 잡는다.** 프레임마다 잰 값을 그대로 쓰면 사건의
    3/4 이 '음은 그대로인데 볼륨만 한 칸 움직임' 이었다(837 개 중 520 개).
    귀로는 거의 같은데 자료만 네 배가 된다.
    """
    amax = max((a for ch in amps for a in ch), default=1.0) or 1.0
    ev = []
    for c in range(VOICES):
        a = np.array(amps[c], dtype=np.float64)
        if len(a):                                  # 이동 평균으로 다듬는다
            k = np.ones(VOL_SMOOTH) / VOL_SMOOTH
            a = np.convolve(a, k, mode="same")
        out, prev, run = [], None, 0
        for i, note in enumerate(notes[c]):
            if note is None:
                key = (0, 0)                        # 볼륨 0 = 소리 없음
            else:
                p = min(max(period(note), 1), 4095)
                # 세기를 0~15 로. PSG 볼륨은 한 칸에 3dB 라 로그로 매긴다.
                vol = 15 + 20 * np.log10(max(a[i], 1e-6) / amax) / 3.0
                vol = int(round(vol / VOL_STEP) * VOL_STEP)
                key = (min(max(vol, 1), 15), p)     # 소리가 있으면 1 아래로 안 간다
            if key == prev and run < 255:
                run += 1
                continue
            if prev is not None:
                out.append((prev[0], prev[1] & 0xFF, prev[1] >> 8, run))
            prev, run = key, 1
        if prev is not None:
            out.append((prev[0], prev[1] & 0xFF, prev[1] >> 8, run))
        ev.append(out)
    return ev


def render(ev, path):
    """PSG 가 낼 소리를 wav 로 되돌린다. 롬에 넣기 전에 들어 보려는 것이다."""
    total = max(sum(e[3] for e in ch) for ch in ev)
    n = int(total / FPS * SR)
    out = np.zeros(n)
    for ch in ev:
        t = 0
        phase = 0.0
        for vol, plo, phi, dur in ch:
            p = plo | (phi << 8)
            a = 0.0 if vol == 0 else 0.25 * (10 ** ((vol - 15) * 3 / 20.0))
            f = PSG_CLOCK / (16.0 * max(p, 1))
            ns = int(dur / FPS * SR)
            if t + ns > n:
                ns = n - t
            if ns > 0 and a > 0:
                k = np.arange(ns)
                ph = phase + 2 * np.pi * f * k / SR
                out[t:t + ns] += a * np.sign(np.sin(ph))
                phase = (phase + 2 * np.pi * f * ns / SR) % (2 * np.pi)
            t += ns
            if t >= n:
                break
    out = np.clip(out, -1, 1)
    w = wave.open(path, "w")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((out * 32767).astype(np.int16).tobytes())
    w.close()


def emit(songs):
    """롬에 들어갈 자료와 상수. songs = [(이름, 사건목록, 프레임수), ...]

    곡은 **뱅크에 두고 시작할 때 RAM 으로 옮긴다.** 본체(0x4000-0x9FFF)에 두면
    한 곡에 4KB 를 먹고, 0xA000 창에 둔 채로 읽으면 그림을 푸는 동안 창을 서로
    뺏는다(음악은 그림을 푸는 중에도 계속 울려야 한다). RAM 은 RamEnd 위로
    0xC940~0xF380 이 비어 있어 넉넉하다.

    곡마다 뱅크 하나를 준다 - 두 곡을 한 뱅크에 이어 붙이면 8KB 를 넘고, 곡이
    경계를 넘으면 옮기는 동안 뱅크를 갈아 끼워야 한다.
    """
    import quest_convert as C

    L = ["; gfx/psg_music.py 가 만든 파일입니다. 직접 고치지 마세요.",
         ";",
         "; MUS_* 는 곡의 **쓰임**이지 파일 이름이 아니다. 곡을 갈아도 부르는",
         "; 자리는 그대로 두려는 것이다.",
         ";",
         "; 곡마다 뱅크 하나. 음악 뱅크는 타이틀 뱅크 **앞**에 온다 - 전투곡은",
         "; --title 을 안 준 빌드에도 있어야 한다.",
         "",
         "MUSIC_BANKS  equ %d" % len(songs),
         "MUSIC_BANK   equ RUN_BANK0 + RUN_BANKS",
         "MUS_N        equ %d" % len(songs),
         "MUS_STRIDE   equ 8                 ; 길이 + 채널 셋의 자리, 워드 넷",
         ""]
    D = ["; gfx/psg_music.py 가 만든 파일입니다. 직접 고치지 마세요.",
         "",
         "; 곡마다 (길이, 가락 자리, 화음 자리, 베이스 자리).",
         "MusTab:"]
    maxlen = 0
    for i, (role, name, ev, frames) in enumerate(songs):
        blob = bytearray()
        ofs = []
        for c in range(VOICES):
            ofs.append(len(blob))
            for vol, plo, phi, dur in ev[c]:
                blob += bytes([vol, plo, phi, dur])
            blob += b"\x00\x00\x00\x00"             # 끝
        if len(blob) > C.BANK_SIZE:
            sys.exit("%s 가 %d 바이트다. 한 곡이 뱅크 하나(%d)에 들어가야 한다."
                     % (name, len(blob), C.BANK_SIZE))

        # 채널 셋의 총 길이가 같아야 한다. 곡 끝에서 채널마다 따로 처음으로
        # 돌아가는데(PsgChan), 길이가 다르면 돌 때마다 어긋나 화음이 깨진다.
        durs = [sum(e[3] for e in ev[c]) for c in range(VOICES)]
        if len(set(durs)) != 1:
            sys.exit("%s 의 채널 길이가 다르다: %s 프레임.\n"
                     "  곡 끝에서 되돌 때 어긋난다 - events() 를 보세요."
                     % (name, durs))
        if durs[0] != frames:
            sys.exit("%s 의 채널 길이 %d 가 잰 프레임 수 %d 와 다르다."
                     % (name, durs[0], frames))

        maxlen = max(maxlen, len(blob))
        L.append("MUS_%-8s equ %d                 ; %s.mp3" % (role.upper(), i, name))
        D.append("    ; %s <- %s (%d 바이트, %d 프레임)"
                 % (role, name, len(blob), frames))
        D.append("    dw %d, %d, %d, %d" % (len(blob), ofs[0], ofs[1], ofs[2]))
        C.bank_file("quest8", "musicbank", i, blob,
                    "%s.mp3 -> PSG 세 채널 (사건 %s)" % (name, [len(c) for c in ev]))

    L.append("")
    L.append("MUSIC_MAXLEN equ %d              ; RAM 에 잡아 둘 자리" % maxlen)
    io.open(os.path.join(ROOT, "src", "quest8musicconst.asm"), "w",
            encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
    io.open(os.path.join(ROOT, "src", "quest8musicdata.asm"), "w",
            encoding="utf-8", newline="\n").write("\n".join(D) + "\n")
    return maxlen


def convert(name):
    """이름 -> (사건 목록, 프레임 수). 무엇을 골랐는지 함께 찍는다."""
    x = decode(name)
    midi, E = note_energy(x)
    raw, amps = voices(E, midi)
    notes = hold_min(smooth(raw))
    ev = events(notes, amps)

    total = sum(len(c) for c in ev) * 4 + 12
    print("%s: %d 프레임 (%.1f 초), 사건 %s -> %d 바이트"
          % (name, len(E), len(E) / FPS, [len(c) for c in ev], total))
    for c in range(VOICES):
        used = [e for e in ev[c] if e[0] > 0]
        if used:
            ps = [e[1] | (e[2] << 8) for e in used]
            f = [PSG_CLOCK / (16.0 * p) for p in ps]
            print("  채널 %d (%s): 사건 %4d, 음역 %s ~ %s"
                  % (c, ("가락", "화음", "베이스")[c], len(ev[c]),
                     note_name(int(round(69 + 12 * np.log2(min(f) / 440)))),
                     note_name(int(round(69 + 12 * np.log2(max(f) / 440))))))
    return ev, len(E)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")] or ["title"]
    songs = []
    for a in args:
        role, _, name = a.partition("=")
        if not name:
            name = role                     # `파일` 만 주면 쓰임도 그 이름이다
        songs.append((role, name) + convert(name))
    if "--wav" in sys.argv:
        for _role, name, ev, _f in songs:
            p = os.path.join(WORK, name + "_psg.wav")
            render(ev, p)
            print("들어 보기: %s" % p)
        return
    n = emit(songs)
    print("wrote src/quest8musicconst.asm + quest8musicdata.asm + 뱅크 %d 개 "
          "(가장 큰 곡 %d 바이트)" % (len(songs), n))


if __name__ == "__main__":
    main()
