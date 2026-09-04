"""mp3/mml -> PSG 세 채널 악보. assets/psg/ 의 곡을 롬에 넣을 형태로 옮긴다.

  uv run --with numpy python gfx/psg_music.py title battle=Final_Sector_Pursuit
  uv run --with numpy python gfx/psg_music.py battle --wav   굽지 않고 들어만 본다

원본은 **.bas, .mml, .mp3** 셋 중 하나다. 확장자를 붙여 주면 그것을 쓰고
(`battle=Obsidian_Keep.bas`), 안 붙이면 .bas > .mml > .mp3 차례로 찾아 **무엇을
골랐는지 찍는다.** 조용히 고르면 "왜 안 바뀌지" 로 이어진다.

  .bas  MSX-BASIC 의 PLAY 문. `A$="T85O4..."` 셋이 그대로 PSG 세 채널이다.
        사람이 쓴 악보라 제일 낫다 - 성부가 셋이고 음이 정확하다.
  .mml  홑가락 악보. 음은 정확하지만 성부가 하나뿐이라 얇다.
  .mp3  FFT 로 음을 **알아맞힌다.** 봉우리가 이웃 반음을 오가면 음이 흔들려서
        HOLD/MIN_FRAMES 로 눌러야 하고, 그만큼 가락이 뭉개진다.

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
import re
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

# ------------------------------------------------------------------------ mml
MML_VOL = 13                # 홑가락이라 세게. 아래 옥타브 겹은 이보다 낮다
MML_GAP = 1                 # 음과 음 사이에 두는 빈 프레임
MML_MINGAP = 4              # 이보다 짧은 음은 끊지 않는다 (끊으면 없어진다)
MML_OCT = 55                # 이 음 위로는 한 옥타브 아래를 겹쳐 두껍게 한다
MML_OCTVOL = 4              # 겹치는 소리를 얼마나 낮출지 (볼륨 눈금)
BAS_VOL = 13                # .bas 의 채널마다 주는 볼륨
#
# 성부가 셋이라 한꺼번에 울린다. 11 로 재 보니 롬에서 rms 0.040 으로 앞 곡
# (홑가락, 0.057)보다 작았다. 13 이면 0.081 이고 깎이는 표본은 0 이다.

MML_STEP = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}


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


def mml_tokens(text, up, base, octv=4, deflen=4, tempo=120):
    """MML 글자열 -> ([(MIDI 음 또는 None, 온음표 몫, 빠르기)], 남은 상태).

    `up` 이 `>` 의 방향(+1 올림 / -1 내림), `base` 가 옥타브 번호를 MIDI 로
    옮기는 기준이다 (음 = (옥타브 + base) * 12 + 계단). **방언마다 둘 다
    달라서 인자로 받는다** - 부르는 자리 둘에 왜 그 값인지를 적어 두었다.
    한 파일 안에 반대 규칙을 둘 박아 두면 나중에 하나를 '고치다가' 깨진다.

    `^` 는 앞 음에 길이를 더한다. basic pitch 가 뽑은 악보는 MIDI 를 옮긴
    것이라 `e12^e192` 처럼 1/192 까지 잘게 이어 붙는다.
    """
    s = re.sub(r"\s+", "", text).lower()
    i, out, tie = 0, [], False
    while i < len(s):
        ch = s[i]
        if ch in "tol":                             # 빠르기 / 옥타브 / 기본 길이
            j = i + 1
            while j < len(s) and s[j].isdigit():
                j += 1
            n = int(s[i + 1:j] or 0)
            if ch == "t":
                tempo = n
            elif ch == "o":
                octv = n
            else:
                deflen = n
            i = j
        elif ch == ">":
            octv += up
            i += 1
        elif ch == "<":
            octv -= up
            i += 1
        elif ch == "^":
            tie = True
            i += 1
        elif ch in "abcdefgr":
            i += 1
            acc = 0
            while i < len(s) and s[i] in "+-#":
                acc += 1 if s[i] in "+#" else -1
                i += 1
            j = i
            while j < len(s) and s[j].isdigit():
                j += 1
            ln = int(s[i:j]) if j > i else deflen
            i = j
            frac = add = 1.0 / ln
            while i < len(s) and s[i] == ".":       # 점 하나마다 절반씩 더
                add /= 2.0
                frac += add
                i += 1
            note = None if ch == "r" else (octv + base) * 12 + MML_STEP[ch] + acc
            if tie and out and out[-1][0] == note:
                out[-1][1] += frac
            else:
                out.append([note, frac, tempo])
            tie = False
        else:
            i += 1                                  # `;` 등 모르는 글자는 흘린다
    return out, (octv, deflen, tempo)


def parse_mml(text):
    """basic pitch 가 뽑아 준 홑가락 악보.

    **`>` 가 옥타브를 내린다.** MSX-BASIC 의 PLAY 와 반대인데(parse_bas 를
    보라), 짐작이 아니라 옆에 있는 .mid 와 맞대어 본 결과다: 올림으로 읽으면
    음역이 51~107 이 나오고 프레임의 16%만 맞는다. 내림으로 읽으면 35~76 -
    .mid 와 정확히 같은 음역이고 81% 가 맞는다(나머지는 basic pitch 가 겹쳐
    낸 음들이다).

    옥타브 기준도 다르다. 여기는 `옥타브 * 12`, MSX-BASIC 은 `(옥타브+1) * 12`
    (o4 의 C 가 가온다 = 60) 다. 여기서 +1 로 읽으면 한 옥타브가 통째로
    높아진다 - 이것도 .mid 로 맞췄다.
    """
    ev, _st = mml_tokens(text, -1, 0)
    return ev


def parse_bas(text):
    """MSX-BASIC 의 PLAY 문 -> 채널 셋.

    `10 A$="T85O4..."` 로 성부를 담고 `40 PLAY A$,B$,C$` 로 튼다. PLAY 는
    기다리지 않고 큐에 넣기만 하므로, PLAY 가 여러 번이면 채널마다 제 몫이
    **차례로 이어 붙는다.** 그래서 성부별로 이어 붙이는 것이 맞다.

    **`>` 가 옥타브를 올린다.** 진짜 MSX-BASIC 이라 표준을 따르는데, 이것도
    재 봤다 - Obsidian_Keep.mp3 에 맞대니 올림이 0.645(음역 35~76, 옆에 있는
    .mid 와 같다), 내림이 0.510(음역 27~107 로 말이 안 된다)이었다.
    parse_mml 은 반대다.

    `IF PLAY(0) THEN ...` 같은 줄은 PLAY 문이 아니다 - 성부 이름이 따라오는
    것만 센다. 안 그러면 빈 마디가 하나 더 생긴다.
    """
    cur, secs = {}, []
    for line in text.split("\n"):
        m = re.match(r'\s*\d+\s+([ABC])\$\s*=\s*"([^"]*)"', line)
        if m:
            cur[m.group(1)] = m.group(2)
            continue
        if re.search(r"\bPLAY\s*[A-C]\$", line, re.I):
            secs.append([cur.get(k, "") for k in "ABC"])
            cur = {}
    if not secs:
        sys.exit("PLAY A$,B$,C$ 를 못 찾았습니다")

    chans = [[], [], []]
    for sec in secs:
        for c in range(VOICES):
            ev, _st = mml_tokens(sec[c], +1, 1)
            chans[c] += ev
    return chans


def spans_to_frames(spans):
    """[(음, 온음표 몫, 빠르기)] -> [(음, 시작, 끝)] 과 총 프레임 수.

    **길이를 따로 반올림하지 않고 경계를 반올림한다.** basic pitch 악보에는
    1/192(120bpm 에서 0.6 프레임)짜리가 흔해서, 길이마다 따로 반올림하면 0 이
    되어 사라지고 그 오차가 쌓여 곡 전체가 밀린다. 경계로 재면 짧은 음은
    사라지되 뒤 음이 그 자리를 물려받아 전체 길이는 안 밀린다.
    """
    t, out = 0.0, []
    for note, frac, tempo in spans:
        a = int(round(t))
        t += frac * 4.0 * 60.0 / tempo * FPS        # 온음표 = 4분음표 넷
        out.append((note, a, int(round(t))))
    return out, int(round(t))


def pack(ch, nf):
    """[(음, 볼륨, 울릴 프레임, 쉴 프레임)] 셋 -> 롬에 넣을 사건 목록 셋."""
    ev = []
    for c in range(VOICES):
        runs = []                                   # [[(볼륨, 주기), 프레임]]
        for note, vol, on, gap in ch[c] or [(None, 0, nf, 0)]:
            p = 1 if note is None else min(max(period(note), 1), 4095)
            for key, d in (((0 if note is None else vol, p), on), ((0, p), gap)):
                if d <= 0:
                    continue
                if runs and runs[-1][0] == key:
                    runs[-1][1] += d
                else:
                    runs.append([key, d])

        # 채널 셋의 길이가 같아야 한다 - emit() 이 그것을 못박는다. 곡 끝에서
        # 채널마다 따로 처음으로 돌기 때문이다(PsgChan).
        short = nf - sum(d for _, d in runs)
        if short > 0:
            runs.append([(0, 1), short])
        while short < 0:                            # 넘치면 뒤에서 깎는다
            take = min(-short, runs[-1][1])
            runs[-1][1] -= take
            short += take
            if runs[-1][1] == 0:
                runs.pop()

        out = []
        for (vol, p), d in runs:
            while d > 0:                            # 길이는 한 바이트뿐이다
                k = min(d, 255)
                out.append((vol, p & 0xFF, p >> 8, k))
                d -= k
        ev.append(out)
    return ev


def voice_cells(spans, vol):
    """한 성부 -> [(음, 볼륨, 울릴 프레임, 쉴 프레임)]. 음 사이를 살짝 끊는다."""
    out = []
    for note, a, b in spans:
        if b <= a:
            continue                                # 반올림에 먹힌 음
        n = b - a
        gap = MML_GAP if n >= MML_MINGAP else 0     # 짧은 음은 안 끊는다
        out.append((note, vol, n - gap, gap))
    return out


def mml_events(spans):
    """홑가락 mml -> 채널 셋. FFT 쪽 다듬기(smooth/hold_min/HOLD)는 안 거친다.

    그것들은 FFT 가 잘못 짚은 음을 지우는 장치다. 여기서는 음이 이미 정확
    하므로 통과시키면 멀쩡한 가락만 뭉갠다.

    홑가락이라 채널 0 만 쓰면 사각파 하나가 되어 얇다. 가락이 MML_OCT 위로
    올라가는 동안만 채널 1 에 **한 옥타브 아래를 겹쳐** 둔다. 없는 성부를
    지어내지 않으면서 소리를 두껍게 하는 흔한 수다.
    """
    frames, nf = spans_to_frames(spans)
    ch = [voice_cells(frames, MML_VOL), [], []]
    for note, a, b in frames:
        if b <= a:
            continue
        n = b - a
        gap = MML_GAP if n >= MML_MINGAP else 0
        if note is not None and note >= MML_OCT:
            ch[1].append((note - 12, MML_VOL - MML_OCTVOL, n - gap, gap))
        else:
            ch[1].append((None, 0, n - gap, gap))
    return pack(ch, nf), nf


def bas_events(chans):
    """PLAY 세 성부 -> 채널 셋. A$/B$/C$ 가 그대로 PSG 채널 A/B/C 다.

    성부 길이가 서로 다르면 짧은 쪽 뒤가 조용해진다 - MSX 에서도 그렇다.
    pack() 이 긴 쪽에 맞춰 채운다.
    """
    fr = [spans_to_frames(c) for c in chans]
    nf = max(n for _f, n in fr)
    return pack([voice_cells(f, BAS_VOL) for f, _n in fr], nf), nf


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
        L.append("MUS_%-8s equ %d                 ; %s" % (role.upper(), i, name))
        D.append("    ; %s <- %s (%d 바이트, %d 프레임)"
                 % (role, name, len(blob), frames))
        D.append("    dw %d, %d, %d, %d" % (len(blob), ofs[0], ofs[1], ofs[2]))
        C.bank_file("quest8", "musicbank", i, blob,
                    "%s -> PSG 세 채널 (사건 %s)" % (name, [len(c) for c in ev]))

    L.append("")
    L.append("MUSIC_MAXLEN equ %d              ; RAM 에 잡아 둘 자리" % maxlen)
    io.open(os.path.join(ROOT, "src", "quest8musicconst.asm"), "w",
            encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
    io.open(os.path.join(ROOT, "src", "quest8musicdata.asm"), "w",
            encoding="utf-8", newline="\n").write("\n".join(D) + "\n")
    return maxlen


def convert(name):
    """이름 -> (사건 목록, 프레임 수). 무엇을 골랐는지 함께 찍는다.

    확장자를 붙여 주면 그것을 쓰고, 안 붙이면 .bas > .mml > .mp3 차례로 찾는다.
    """
    stem, _, ext = name.rpartition(".")
    if ext in ("bas", "mml", "mp3"):
        cand = [(stem, ext)]
    else:
        stem = name
        cand = [(stem, e) for e in ("bas", "mml", "mp3")]
    for st, e in cand:
        path = os.path.join(SRC, "%s.%s" % (st, e))
        if os.path.exists(path):
            break
    else:
        sys.exit("%s: %s 를 못 찾았습니다"
                 % (name, " / ".join("%s.%s" % c for c in cand)))

    if e in ("bas", "mml"):
        text = io.open(path, encoding="utf-8").read()
        if e == "bas":
            chans = parse_bas(text)
            ev, nf = bas_events(chans)
            played = [n for c in chans for n, _f, _t in c if n is not None]
            what = "성부 %s" % [sum(1 for n, _f, _t in c if n is not None)
                                for c in chans]
        else:
            spans = parse_mml(text)
            ev, nf = mml_events(spans)
            played = [n for n, _f, _t in spans if n is not None]
            what = "홑가락 %d 음" % len(played)
        print("%s.%s: %d 프레임 (%.1f 초), %s (%s ~ %s), 사건 %s -> %d 바이트"
              % (st, e, nf, nf / FPS, what,
                 note_name(min(played)), note_name(max(played)),
                 [len(c) for c in ev], sum(len(c) for c in ev) * 4 + 12))
        return ev, nf

    x = decode(st)
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
