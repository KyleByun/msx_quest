"""달무리 글꼴의 8x8 한글 조합 규칙을 파이썬으로 옮긴 것.

달무리(dalmoori, Apache 2.0)는 8x8 에 현대 한글 전체를 담으려고 만든 글꼴이다.
자모를 낱개로 갖고 있고, 글자를 만들 때마다 **자리에 맞는 변형을 골라 겹친다.**
조합형 폰트의 '벌' 과 같은 생각인데, 벌 번호를 표에서 찾는 대신 조건을 걸어
맞는 것을 찾아낸다. 8x8 은 자리가 워낙 좁아서 그렇게까지 해야 한다.

  generator/glyph/hangul-phoneme/consonant/<자음>/onset-<너비>-<높이>[-꼬리].txt
                                          <자음>/coda-<높이>[-꼬리].txt
                                 vowel/<모음>/<변형이름들>.txt

각 파일은 `---` 로 둘러싼 머리말과 8x8 격자다. 격자에서 `#` 만 잉크고
`.` `x` `m` 은 전부 빈칸이다 (`x` 는 '내 구역이 아님', `m` 은 여백 표시).

옮긴 원본은 generator/src/core 의 ascii-font.ts, hangul-phoneme.ts, combine.ts 다.
고르는 차례와 조건을 그대로 따랐다. tools/proof.py 가 한글 11,172자를 전부
만들어 보고, 실패한 글자가 없는지와 고를 것이 여럿인 자리가 없는지 확인한다.

이 규칙은 빌드할 때만 돈다. Z80 은 다 만들어진 8x8 비트맵을 받아 쓰기만 한다.
"""
import functools, os, re

WIDTH = HEIGHT = 8

COMPAT_CONSONANT = 'ㄱㄲㄳㄴㄵㄶㄷㄸㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅃㅄㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ'
COMPAT_VOWEL = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ'
# 유니코드 음절 순서의 초성 19개, 종성 27개를 위의 호환 자모 이름으로
ONSET_ORDER = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ'
CODA_ORDER = 'ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ'

# 원본(hangul-phoneme.ts)의 정규식은 앵커가 없다. 그래서 `coda-3 ㅗㅜㅡ.txt`
# 처럼 뒤에 무엇이 붙어도 앞부분만 읽고 통과한다. 여기서도 그렇게 맞춘다.
ONSET_RE = re.compile(r'onset-(\d+)-(\d+)')
CODA_RE = re.compile(r'coda-(\d+)')

# --- 글리프 파일 읽기 ---------------------------------------------------------
def parse(path):
    """--- 머리말 --- + 8x8 격자  ->  (머리말 dict, 잉크 좌표 집합)"""
    src = open(path, encoding='utf-8').read()
    if not src.startswith('---'):
        raise ValueError("머리말이 없다: %s" % path)
    end = src.index('---', 4)
    meta = {}
    for line in src[3:end].split('\n'):
        line = line.strip()
        if not line:
            continue
        k, _, v = line.partition('=')
        keys = [s.strip() for s in k.split('.')]
        v = v.strip()
        if _num(v) is not None:
            val = _num(v)
        elif ',' in v:
            val = [_num(s) if _num(s) is not None else s.strip() for s in v.split(',')]
        else:
            val = v
        tgt = meta
        for key in keys[:-1]:
            tgt = tgt.setdefault(key, {})
        tgt[keys[-1]] = val

    ink, i = set(), 0
    for c in src[end + 3:]:
        if c in ' \t\r\n':
            continue
        if c == '#':
            ink.add((i % WIDTH, i // WIDTH))
            i += 1
        elif c in '.xm':
            i += 1
        else:
            raise ValueError("알 수 없는 글자 %r: %s" % (c, path))
        if i > WIDTH * HEIGHT:
            raise ValueError("격자가 너무 크다: %s" % path)
    return meta, ink

def _num(s):
    try:
        return int(s)
    except (TypeError, ValueError):
        return None

def _listof(meta, key, default):
    """머리말 값 하나 또는 목록 -> 내림차순 목록. 원본이 늘 내림차순으로 정렬한다."""
    if key not in meta:
        return list(default)
    v = meta[key]
    return sorted(v if isinstance(v, list) else [v], reverse=True)

def _re(meta, key):
    return re.compile('^' + str(meta[key]) + '$') if key in meta else None

def _reqmap(meta):
    out = {}
    for target, v in (meta.get('variant') or {}).items():
        out[target] = list(v) if isinstance(v, list) else [v]
    return out

# --- 자모 한 벌 --------------------------------------------------------------
class Part:
    __slots__ = ('ink', 'reqmap', 'for_re', 'notfor_re', 'height', 'mtop', 'name')
    def __init__(self, path, height=0, mtop_default=(0,)):
        meta, self.ink = parse(path)
        self.name = os.path.basename(path)
        self.reqmap = _reqmap(meta)
        self.for_re = _re(meta, 'for')
        self.notfor_re = _re(meta, 'not-for')
        self.height = height
        self.mtop = _listof(meta, 'margin-top', mtop_default)

class NucleusVariant:
    __slots__ = ('ink', 'applied', 'wocc', 'hocc', 'mleft', 'mtop', 'name')
    def __init__(self, path):
        meta, self.ink = parse(path)
        self.name = os.path.basename(path)
        self.applied = set(os.path.basename(path)[:-4].split(','))
        self.wocc = meta.get('width-occupying', 0)
        self.hocc = meta.get('height-occupying', 0)
        self.mleft = _listof(meta, 'margin-left', (0,))
        self.mtop = _listof(meta, 'margin-top', (0,))

class Font:
    """glyph/ 아래를 한 번 읽어 두고 글자를 만들어 준다."""
    def __init__(self, glyphdir):
        base = os.path.join(glyphdir, 'hangul-phoneme')
        self.onsets, self.codas, self.nuclei = {}, {}, {}
        for c in COMPAT_CONSONANT:
            d = os.path.join(base, 'consonant', c)
            if not os.path.isdir(d):
                continue
            onset, coda = {}, []
            for f in sorted(os.listdir(d)):
                stem = f[:-4] if f.endswith('.txt') else f
                m = ONSET_RE.match(stem)
                if m:
                    w, h = int(m.group(1)), int(m.group(2))
                    onset.setdefault((w, h), []).append(Part(os.path.join(d, f)))
                    continue
                m = CODA_RE.match(stem)
                if m:
                    coda.append(Part(os.path.join(d, f), height=int(m.group(1))))
            coda.sort(key=lambda p: -p.height)          # 원본과 같이 높이 내림차순
            self.onsets[c], self.codas[c] = onset, coda
        for v in COMPAT_VOWEL:
            d = os.path.join(base, 'vowel', v)
            if os.path.isdir(d):
                self.nuclei[v] = _sort_variants(
                    [NucleusVariant(os.path.join(d, f)) for f in sorted(os.listdir(d))])
        self.latin = load_latin(glyphdir)

    def glyph(self, ch):
        """한글이면 조합하고, 그 밖이면 basic-latin 에서 찾는다. -> 8바이트"""
        if 0xAC00 <= ord(ch) <= 0xD7A3:
            ink = self.syllable(ch)
        elif ch in self.latin:
            ink = self.latin[ch]
        else:
            raise ValueError("글리프가 없다: %r (U+%04X)" % (ch, ord(ch)))
        return bytes(sum(0x80 >> x for x in range(WIDTH) if (x, y) in ink)
                     for y in range(HEIGHT))

    def syllable(self, ch, all_matches=False):
        """완성형 한글 한 글자 -> 잉크 좌표 집합. all_matches 면 가능한 것 전부."""
        n = ord(ch) - 0xAC00
        if not 0 <= n < 11172:
            raise ValueError("한글 음절이 아니다: %r" % ch)
        on = ONSET_ORDER[n // 588]
        nu = COMPAT_VOWEL[(n // 28) % 21]
        co = CODA_ORDER[n % 28 - 1] if n % 28 else None
        return combine(self, on, nu, co, all_matches)

    def bitmap(self, ch):
        """8바이트. 한 줄이 1바이트, 왼쪽 픽셀이 최상위 비트."""
        ink = self.syllable(ch)
        return bytes(sum(0x80 >> x for x in range(WIDTH) if (x, y) in ink)
                     for y in range(HEIGHT))

def _sort_variants(vs):
    def cmp(a, b):
        if 'default' in a.applied:
            return -1
        if 'default' in b.applied:
            return 1
        return len(a.applied) - len(b.applied)
    return sorted(vs, key=functools.cmp_to_key(cmp))

# --- 조합 (원본 combine.ts 를 그대로 옮겼다) ----------------------------------
def combine(font, onset_c, nucleus_c, coda_c=None, all_matches=False):
    onset = font.onsets[onset_c]
    nucleus = font.nuclei[nucleus_c]
    codas = font.codas[coda_c] if coda_c else None

    if codas:
        heights = [(p, mt, p.height) for p in codas for mt in p.mtop]
    else:
        heights = [(None, 0, 0)]

    found = []
    for coda_part, mt_coda, coda_h in heights:
        real_coda_h = mt_coda + coda_h
        for nv in nucleus:
            if HEIGHT < real_coda_h + nv.hocc:
                continue
            if coda_part is not None:
                probe = onset_c + nucleus_c
                if coda_part.for_re and not coda_part.for_re.match(probe):
                    continue
                if coda_part.notfor_re and coda_part.notfor_re.match(probe):
                    continue
                reqs = list(coda_part.reqmap.get(nucleus_c, [])) + ['coda-%d' % real_coda_h]
                if any(r not in nv.applied for r in reqs):
                    continue
            for mt_nu in nv.mtop:
                if HEIGHT < real_coda_h + nv.hocc + mt_nu:
                    continue
                for ml in nv.mleft:
                    for op in onset.get((WIDTH - nv.wocc - ml,
                                         HEIGHT - nv.hocc - mt_nu - real_coda_h), []):
                        tails = ([coda_c + str(mt_coda + coda_h),
                                  '%s%d %d' % (coda_c, mt_coda, coda_h)]
                                 if coda_c else ['.0'])
                        heads = [nucleus_c + str(mt_nu + nv.hocc),
                                 '%s%d %d' % (nucleus_c, mt_nu, nv.hocc)]
                        probes = [h + t for h in heads for t in tails]
                        if op.for_re and not any(op.for_re.match(p) for p in probes):
                            continue
                        if op.notfor_re and any(op.notfor_re.match(p) for p in probes):
                            continue
                        if any(r not in nv.applied
                               for r in op.reqmap.get(nucleus_c, [])):
                            continue
                        ink = op.ink | nv.ink
                        if op.ink & nv.ink:
                            continue                    # 원본의 with() 가 여기서 던진다
                        if coda_part is not None:
                            if ink & coda_part.ink:
                                continue
                            ink = ink | coda_part.ink
                        if not all_matches:
                            return ink
                        found.append((frozenset(ink), op.name, nv.name,
                                      coda_part.name if coda_part else None))
    if all_matches:
        return found
    raise ValueError("조합할 수 없다: %s%s%s" % (onset_c, nucleus_c, coda_c or ''))

def art(bmp):
    return [''.join('#' if b & (0x80 >> x) else '.' for x in range(WIDTH)) for b in bmp]

# --- 영문/숫자/문장부호 -------------------------------------------------------
# basic-latin 은 조합이 없다. 글리프 하나가 그대로 한 글자다.
# 파일 이름은 글자 그대로거나(예: A.txt), 파일 이름에 쓰기 어려운 글자는
# U+XXXX.txt 꼴이다.
def _latin_key(name):
    stem = name[:-4] if name.endswith('.txt') else name
    if stem.startswith('U+'):
        return chr(int(stem[2:], 16))
    return stem if len(stem) == 1 else None

def load_latin(glyphdir):
    """{글자: 잉크 좌표 집합}"""
    d = os.path.join(glyphdir, 'basic-latin')
    out = {}
    if not os.path.isdir(d):
        return out
    for f in sorted(os.listdir(d)):
        k = _latin_key(f)
        if k is not None:
            out[k] = parse(os.path.join(d, f))[1]
    return out
