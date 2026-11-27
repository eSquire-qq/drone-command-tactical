"""Soak test: every map × language × run, with a readable report.

  python -X utf8 tools/soak.py                    # all maps, uk + en, 3 runs each, 3 at a time
  python -X utf8 tools/soak.py --runs 5 --maps urban,forest --langs en --jobs 4
  python -X utf8 tools/soak.py --windowed         # with a window: real FPS + pictures of problems
  python -X utf8 tools/soak.py --random 2         # +2 runs per map/lang with random seeds

Run i uses the fixed seed 1000 + i (repeatable start); --random adds runs with
random seeds for wider coverage. The game side is scripts/debug/soak_monitor.gd.
Report: soak_reports/<date_time>/report.md (+ a log per run, pictures).
"""
import argparse
import concurrent.futures as cf
import datetime
import json
import os
import random
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# the Godot 4.7 editor binary: set GODOT in the environment, or edit this default
GODOT = os.environ.get('GODOT', r'E:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe')
MAPS = ['training', 'treeline', 'field', 'village', 'forest', 'urban']
TIMEOUT = 900     # s of wall time per run


def run_one(job):
    m, lang, seed, out_dir, windowed = job
    args = [GODOT]
    if not windowed:
        args.append('--headless')
    args += ['--path', ROOT, '--', '--map=' + m, '--lang=' + lang, '--seed=%d' % seed, '--soak', '--soak-dir=' + out_dir]
    args += ['--autotest'] if m == 'training' else ['--balance=smart']
    log_path = os.path.join(out_dir, '%s_%s_%d.log' % (m, lang, seed))
    t0 = time.time()
    timed_out = False
    try:
        p = subprocess.run(args, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=TIMEOUT)
        out = p.stdout + '\n' + p.stderr
        code = p.returncode
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b'').decode('utf-8', 'replace') if isinstance(e.stdout, bytes) else (e.stdout or '')
        out += '\n' + ((e.stderr or b'').decode('utf-8', 'replace') if isinstance(e.stderr, bytes) else (e.stderr or ''))
        code = -1
        timed_out = True
    open(log_path, 'w', encoding='utf-8').write(out)
    return parse(m, lang, seed, out, code, timed_out, time.time() - t0, log_path)


def parse(m, lang, seed, out, code, timed_out, wall, log_path):
    r = {'map': m, 'lang': lang, 'seed': seed, 'code': code, 'timed_out': timed_out, 'wall': int(wall),
         'log': os.path.basename(log_path), 'summary': None, 'events': [], 'errors': {}, 'balance': None, 'shots': []}
    lines = out.split('\n')
    for i, line in enumerate(lines):
        if line.startswith('[SOAK] '):
            try:
                r['summary'] = json.loads(line[7:])
            except ValueError:
                pass
        elif line.startswith('[SOAK-EVENT] '):
            try:
                r['events'].append(json.loads(line[13:]))
            except ValueError:
                pass
        elif line.startswith('[SOAK-SHOT] '):
            r['shots'].append(os.path.basename(line[12:].strip()))
        elif line.startswith('[BALANCE] map='):
            r['balance'] = line[10:].strip()
        elif 'SCRIPT ERROR' in line or line.startswith('ERROR:') and 'Unreferenced static string' not in line and 'ObjectDB' not in line:
            where = ''
            for k in range(i + 1, min(i + 4, len(lines))):
                if lines[k].strip().startswith('at:'):
                    where = lines[k].strip()[3:].strip()
                    break
            key = (line.strip()[:160], where)
            r['errors'][key] = r['errors'].get(key, 0) + 1
    return r


def verdict(r):
    if r['timed_out']:
        return 'TIMEOUT'
    if r['errors']:
        return 'ERRORS'
    if r['summary'] is None:
        return 'NO SUMMARY'
    if r['summary'].get('reason') == 'no_end':
        return 'NO END'
    if any(e['kind'].startswith('stuck') for e in r['events']):
        return 'STUCK'
    return 'OK'


def report(results, out_dir, opts):
    L = []
    L.append('# Прогін карт (soak) — %s\n' % datetime.datetime.now().strftime('%d.%m.%Y %H:%M'))
    L.append('Карти: %s · мови: %s · прогонів: %d фіксованих + %d випадкових · %s\n' % (
        ', '.join(opts.maps), ', '.join(opts.langs), opts.runs, opts.random, 'вікно' if opts.windowed else 'без вікна (headless, час кадру = логіка)'))
    L.append('## Підсумок\n')
    L.append('| Карта | Мова | Прогонів | OK | Помилки | Застрягання | Без кінця / таймаут | Перемог | Час бою, хв | Логіка, мс (сер / p99) | FPS (сер / 1%) | Пам\'ять, МБ (старт → макс) |')
    L.append('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')
    by = {}
    for r in results:
        by.setdefault((r['map'], r['lang']), []).append(r)
    for (m, lang), rs in sorted(by.items(), key=lambda x: (opts.maps.index(x[0][0]) if x[0][0] in opts.maps else 99, x[0][1])):
        v = [verdict(r) for r in rs]
        wins = sum(1 for r in rs if r['balance'] and 'win=true' in r['balance'])
        ts = [r['summary']['t'] / 60.0 for r in rs if r['summary']]
        fm = [r['summary']['frame_ms'] for r in rs if r['summary']]
        fps = [r['summary']['fps'] for r in rs if r['summary']]
        mem = [(r['summary']['mem_mb_start'], r['summary']['mem_mb_max']) for r in rs if r['summary']]
        avg = lambda a: sum(a) / len(a) if a else 0
        L.append('| %s | %s | %d | %d | %d | %d | %d | %d | %s | %s | %s | %s |' % (
            m, lang, len(rs), v.count('OK'), v.count('ERRORS'), v.count('STUCK'), v.count('NO END') + v.count('TIMEOUT') + v.count('NO SUMMARY'),
            wins, '%.1f' % avg(ts) if ts else '—',
            '%.1f / %.1f' % (avg([f['avg'] for f in fm]), max(f['p99'] for f in fm)) if fm else '—',
            '%.0f / %.0f' % (avg([f['avg'] for f in fps]), min(f.get('p1', f['min']) for f in fps)) if fps and opts.windowed else '—',
            '%.0f → %.0f' % (avg([a for a, b in mem]), max(b for a, b in mem)) if mem else '—'))
    # errors
    errs = {}
    for r in results:
        for (msg, where), n in r['errors'].items():
            e = errs.setdefault((msg, where), {'n': 0, 'runs': set()})
            e['n'] += n
            e['runs'].add('%s/%s/%d' % (r['map'], r['lang'], r['seed']))
    L.append('\n## Помилки скриптів\n')
    if not errs:
        L.append('Немає.')
    for (msg, where), e in sorted(errs.items(), key=lambda x: -x[1]['n']):
        L.append('- **%s** — `%s` — %d раз у %d прогонах: %s' % (msg, where, e['n'], len(e['runs']), ', '.join(sorted(e['runs'])[:6])))
    # events
    L.append('\n## Проблеми під час бою\n')
    any_ev = False
    for r in results:
        evs = [e for e in r['events']]
        if not evs and verdict(r) == 'OK':
            continue
        any_ev = True
        L.append('### %s / %s / seed %d — %s (лог `%s`)' % (r['map'], r['lang'], r['seed'], verdict(r), r['log']))
        if r['balance']:
            L.append('`%s`' % r['balance'])
        kinds = {}
        for e in evs:
            kinds.setdefault(e['kind'], []).append(e)
        for k, es in kinds.items():
            L.append('- %s × %d' % (k, len(es)))
            for e in es[:5]:
                d = {x: y for x, y in e.items() if x not in ('kind', 'map')}
                L.append('  - `%s`' % json.dumps(d, ensure_ascii=False))
        if r['summary'] and r['summary'].get('stuck_units'):
            L.append('- застрягали (епізодів): %s' % ', '.join(r['summary']['stuck_units']))
        for s in r['shots']:
            L.append('  - знімок: `%s`' % s)
        L.append('')
    if not any_ev:
        L.append('Немає.')
    L.append('\n## Усі прогони\n')
    L.append('| Карта | Мова | Seed | Результат | Секунд | Бій |')
    L.append('| --- | --- | --- | --- | --- | --- |')
    for r in results:
        L.append('| %s | %s | %d | %s | %d | %s |' % (r['map'], r['lang'], r['seed'], verdict(r), r['wall'], (r['balance'] or '').replace('|', '/')))
    path = os.path.join(out_dir, 'report.md')
    open(path, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--maps', default=','.join(MAPS))
    ap.add_argument('--langs', default='uk,en')
    ap.add_argument('--runs', type=int, default=3)
    ap.add_argument('--random', type=int, default=0)
    ap.add_argument('--jobs', type=int, default=3)
    ap.add_argument('--windowed', action='store_true')
    opts = ap.parse_args()
    opts.maps = opts.maps.split(',')
    opts.langs = opts.langs.split(',')
    out_dir = os.path.join(ROOT, 'soak_reports', datetime.datetime.now().strftime('%Y-%m-%d_%H-%M'))
    os.makedirs(out_dir, exist_ok=True)
    gdi = os.path.join(ROOT, 'soak_reports', '.gdignore')
    if not os.path.exists(gdi):
        open(gdi, 'w').close()
    jobs = []
    for m in opts.maps:
        for lang in opts.langs:
            for i in range(opts.runs):
                jobs.append((m, lang, 1000 + i, out_dir, opts.windowed))
            for i in range(opts.random):
                jobs.append((m, lang, random.randint(2000, 999999), out_dir, opts.windowed))
    print('runs:', len(jobs), '→', out_dir, flush=True)
    results = []
    with cf.ThreadPoolExecutor(max_workers=1 if opts.windowed else opts.jobs) as ex:
        for r in ex.map(run_one, jobs):
            results.append(r)
            print('%-9s %s seed %-6d %-10s %4d s  %s' % (r['map'], r['lang'], r['seed'], verdict(r), r['wall'], r['balance'] or ''), flush=True)
            report(results, out_dir, opts)
    print('report:', report(results, out_dir, opts))


if __name__ == '__main__':
    main()
