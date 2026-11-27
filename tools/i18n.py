"""Translation helper for «Drone Command: Tactical».

The game text is written in Ukrainian; the Ukrainian text itself is the
translation key (msgid). English lives in locale/en.po (gettext), loaded by
Godot (project setting internationalization/locale/translations).

  python -X utf8 tools/i18n.py wrap [--dry]   wrap Ukrainian literals in runtime code in Loc.t("...")
  python -X utf8 tools/i18n.py pot            collect every game string -> locale/strings.pot,
                                              merge into locale/en.po (keeps existing translations),
                                              list the untranslated ones in locale/todo_en.txt
  python -X utf8 tools/i18n.py apply FILE     FILE: lines "N<TAB>English" for the numbered
                                              entries of todo_en.txt -> written into en.po
  python -X utf8 tools/i18n.py stats

Not wrapped (identifiers, not text): literals compared with == / != / in,
dictionary keys, match patterns, arguments of has/get/begins_with/…,
const tables, @export_enum, print / push_* lines. A literal used as an
identifier anywhere is never wrapped; such text is translated where it is
shown (Loc.t(value)). The Godot editor tools (scripts/map/editor, addons)
and the debug harness stay Ukrainian.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CYR = re.compile('[А-Яа-яІіЇїЄєҐґ]')
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
SKIP_DIRS = ('scripts/map/editor', 'scripts/debug', 'addons')
NO_WRAP_DIRS = SKIP_DIRS + ('scripts/map/maps',)      # data: translated where shown
ID_BEFORE = re.compile(r'(==|!=|\.has\(|\.get\(|\.erase\(|begins_with\(|ends_with\(|\.find\(|\.replace\(|'
                       r'\.count\(|\.split\(|\.contains\(|[\w\])]\[|match)\s*$')
ID_AFTER = re.compile(r'^\s*(==|!=|:(?!=)|\bin\b)')


def files(dirs=('scripts',), skip=SKIP_DIRS):
    for d in dirs:
        for root, _, fs in os.walk(os.path.join(ROOT, d)):
            rel = os.path.relpath(root, ROOT).replace(os.sep, '/')
            if rel.startswith(skip):
                continue
            for f in fs:
                if f.endswith('.gd'):
                    yield os.path.join(root, f)


def unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            out.append({'n': '\n', 't': '\t', '"': '"', '\\': '\\', "'": "'"}.get(n, '\\' + n))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def code_part(line):
    """The line without a trailing comment (a # outside string literals)."""
    q = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '\\' and q:
            i += 2
            continue
        if c == '"':
            q = not q
        elif c == '#' and not q:
            return line[:i]
        i += 1
    return line


def literals(path):
    """(line index, match, statement_is_const, line) for every Cyrillic literal."""
    lines = open(path, encoding='utf-8').read().split('\n')
    depth = 0
    const_stmt = False
    out = []
    ml = False   # inside a """ block
    for li, line in enumerate(lines):
        if '"""' in line:
            if line.count('"""') == 1:
                ml = not ml
            continue
        if ml:
            continue
        code = code_part(line)
        st = code.strip()
        if depth == 0:
            # class-level statements (const tables, member defaults) run before
            # the language is set: their text is translated where it is shown
            const_stmt = st.startswith(('const ', '@export', 'enum ', 'var ', 'static var ')) and not line[:1].isspace()
        for m in LIT.finditer(code):
            if CYR.search(m.group(1)):
                out.append((li, m, const_stmt, line))
        # bracket depth outside literals
        stripped = LIT.sub('""', code)
        depth += stripped.count('(') + stripped.count('[') + stripped.count('{')
        depth -= stripped.count(')') + stripped.count(']') + stripped.count('}')
        depth = max(depth, 0)
    return lines, out


def is_id_use(line, m):
    before = line[:m.start()]
    after = line[m.end():]
    if before.rstrip().endswith('Loc.t(') or before.rstrip().endswith('tr('):
        return False
    if ID_BEFORE.search(before):
        return True
    # inside a list after "in [": ... in ["а", "б"]
    k = max(before.rfind(' in ['), before.rfind(' in('))
    if k >= 0 and ']' not in before[k:] and ')' not in before[k + 4:] and 'for ' not in before[:k]:
        return True
    if ID_AFTER.search(after):
        return True
    return False


def identifiers():
    ids = set()
    for p in files(('scripts',), skip=('addons',)):
        _, lits = literals(p)
        for li, m, const_stmt, line in lits:
            if is_id_use(line, m):
                ids.add(m.group(1))
    return ids


def cmd_wrap(dry):
    ids = identifiers()
    total = 0
    for p in files(skip=NO_WRAP_DIRS):
        lines, lits = literals(p)
        changed = {}
        for li, m, const_stmt, line in lits:
            s = m.group(1)
            st = line.strip()
            if const_stmt or s in ids or is_id_use(line, m):
                continue
            if '# i18n-key' in line:
                continue   # a key kept in Ukrainian (saved data), translated where shown
            if st.startswith(('print(', 'push_warning(', 'push_error(', 'assert(', 'printerr(')):
                continue
            before = line[:m.start()]
            if before.rstrip().endswith(('Loc.t(', 'tr(')):
                continue
            changed.setdefault(li, []).append(m)
        if not changed:
            continue
        for li, ms in changed.items():
            line = lines[li]
            for m in sorted(ms, key=lambda x: -x.start()):
                line = line[:m.start()] + 'Loc.t(' + m.group(0) + ')' + line[m.end():]
                total += 1
            lines[li] = line
        if not dry:
            open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
        print('%4d  %s' % (sum(len(v) for v in changed.values()), os.path.relpath(p, ROOT)))
    print('wrapped', total, '(dry run)' if dry else '')


# ------------------------------------------------------------------ po files
def po_escape(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')


def po_unescape(s):
    return unescape(s)


def read_po(path):
    d = {}
    if not os.path.exists(path):
        return d
    msgid = msgstr = None
    cur = None
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if line.startswith('msgid '):
            if msgid is not None:
                d[msgid] = msgstr
            msgid = po_unescape(line[7:-1])
            msgstr = ''
            cur = 'id'
        elif line.startswith('msgstr '):
            msgstr = po_unescape(line[8:-1])
            cur = 'str'
        elif line.startswith('"') and cur:
            if cur == 'id':
                msgid += po_unescape(line[1:-1])
            else:
                msgstr += po_unescape(line[1:-1])
    if msgid is not None:
        d[msgid] = msgstr
    d.pop('', None)
    return d


def write_po(path, entries, header_lang):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('msgid ""\nmsgstr ""\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Language: %s\\n"\n\n' % header_lang)
        for k, v, ref in entries:
            if ref:
                f.write('#: %s\n' % ref)
            f.write('msgid "%s"\nmsgstr "%s"\n\n' % (po_escape(k), po_escape(v)))


def all_strings():
    """Every Cyrillic literal shown to the player (runtime code + map data), in order of appearance."""
    seen = {}
    for p in files(skip=SKIP_DIRS):
        if p.replace(os.sep, '/').endswith('core/loc.gd'):
            continue   # transliteration table and language names
        _, lits = literals(p)
        for li, m, const_stmt, line in lits:
            s = unescape(m.group(1))
            if line.strip().startswith(('print(', 'push_warning(', 'push_error(', 'printerr(')):
                continue
            if s not in seen:
                seen[s] = '%s:%d' % (os.path.relpath(p, ROOT).replace(os.sep, '/'), li + 1)
    # the scenes of the official maps can hold texts edited in the Godot editor
    keys = re.compile(r'^(title|subtitle|terrain_type|terrain_desc|task_text|label|desc|team_name) = "((?:[^"\\]|\\.)*)"', re.M)
    for f in sorted(os.listdir(os.path.join(ROOT, 'maps'))):
        if f.endswith('.tscn'):
            txt = open(os.path.join(ROOT, 'maps', f), encoding='utf-8').read()
            for m in keys.finditer(txt):
                s = unescape(m.group(2))
                if CYR.search(s):
                    seen.setdefault(s, 'maps/' + f)
    return seen


def cmd_pot():
    os.makedirs(os.path.join(ROOT, 'locale'), exist_ok=True)
    strings = all_strings()
    write_po(os.path.join(ROOT, 'locale', 'strings.pot'), [(k, '', r) for k, r in strings.items()], 'uk')
    en_path = os.path.join(ROOT, 'locale', 'en.po')
    en = read_po(en_path)
    entries = [(k, en.get(k, ''), r) for k, r in strings.items()]
    # keep translations of strings that are no longer found (a text may come back)
    for k, v in en.items():
        if k not in strings and v:
            entries.append((k, v, 'obsolete'))
    write_po(en_path, entries, 'en')
    todo = [k for k, v, r in entries if not v]
    with open(os.path.join(ROOT, 'locale', 'todo_en.txt'), 'w', encoding='utf-8', newline='\n') as f:
        for i, k in enumerate(todo):
            f.write('%d\t%s\n' % (i, po_escape(k)))
    print('strings %d, translated %d, todo %d' % (len(strings), len(strings) - len([k for k in strings if not en.get(k)]), len(todo)))


def cmd_apply(path):
    todo = {}
    for line in open(os.path.join(ROOT, 'locale', 'todo_en.txt'), encoding='utf-8'):
        n, s = line.rstrip('\n').split('\t', 1)
        todo[int(n)] = unescape(s)
    en_path = os.path.join(ROOT, 'locale', 'en.po')
    en = read_po(en_path)
    added = 0
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line.strip() or '\t' not in line:
            continue
        n, t = line.split('\t', 1)
        k = todo.get(int(n))
        if k is None:
            print('no entry', n)
            continue
        t = unescape(t)
        # keep the format placeholders in the same order
        ph_k = re.findall(r'%[-+0-9.]*[sdf%]', k)
        ph_t = re.findall(r'%[-+0-9.]*[sdf%]', t)
        if ph_k != ph_t:
            print('PLACEHOLDERS DIFFER', n, repr(k), '->', repr(t))
            continue
        en[k] = edges(k, t)
        added += 1
    strings = all_strings()
    entries = [(k, en.get(k, ''), strings.get(k, 'obsolete')) for k in list(strings) + [k for k in en if k not in strings]]
    write_po(en_path, entries, 'en')
    print('applied', added)


def edges(k, t):
    """The translation gets the same leading / trailing spaces and line breaks as the original
    (they are layout, and editors tend to strip them)."""
    ws = ' \n'
    lead = k[:len(k) - len(k.lstrip(ws))]
    trail = k[len(k.rstrip(ws)):]
    return lead + t.strip(ws) + trail


def cmd_fix_edges():
    en_path = os.path.join(ROOT, 'locale', 'en.po')
    en = read_po(en_path)
    n = 0
    for k, v in en.items():
        if v and edges(k, v) != v:
            en[k] = edges(k, v)
            n += 1
    strings = all_strings()
    entries = [(k, en.get(k, ''), strings.get(k, 'obsolete')) for k in list(strings) + [k for k in en if k not in strings]]
    write_po(en_path, entries, 'en')
    print('fixed', n)


def cmd_stats():
    strings = all_strings()
    en = read_po(os.path.join(ROOT, 'locale', 'en.po'))
    left = [k for k in strings if not en.get(k)]
    print('strings %d, untranslated %d' % (len(strings), len(left)))


if __name__ == '__main__':
    c = sys.argv[1] if len(sys.argv) > 1 else 'stats'
    if c == 'wrap':
        cmd_wrap('--dry' in sys.argv)
    elif c == 'pot':
        cmd_pot()
    elif c == 'fix-edges':
        cmd_fix_edges()
    elif c == 'apply':
        cmd_apply(sys.argv[2])
    else:
        cmd_stats()
