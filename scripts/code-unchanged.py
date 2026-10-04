#!/usr/bin/env python3
"""Proves a comment-only edit: compares Swift files' code with every
comment removed (line, block and doc comments; string literals kept
intact) between a git revision and the working tree.

usage: scripts/code-unchanged.py [REV] [paths...]   (default REV=HEAD,
paths = every modified .swift file). Exit 1 and print the first
differing line of each file whose code changed."""
import subprocess, sys, re

def strip(src: str) -> list[str]:
    out, i, n = [], 0, len(src)
    buf = []
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            while i < n and src[i] != '\n': i += 1
            continue
        if src.startswith('/*', i):
            depth = 0
            while i < n:
                if src.startswith('/*', i): depth += 1; i += 2
                elif src.startswith('*/', i): depth -= 1; i += 2
                else: i += 1
                if depth == 0: break
            continue
        m = re.match(r'(#*)("""|")', src[i:])
        if m:
            hashes, quote = m.group(1), m.group(2)
            close = quote + hashes
            j = i + len(m.group(0))
            while j < n:
                if not hashes and src[j] == '\\': j += 2; continue
                if src.startswith(close, j): j += len(close); break
                j += 1
            buf.append(src[i:j]); i = j
            continue
        buf.append(c); i += 1
    text = ''.join(buf)
    return [re.sub(r'\s+', ' ', l).strip() for l in text.split('\n') if l.strip()]

def main():
    args = sys.argv[1:]
    rev = 'HEAD'
    if args and not args[0].endswith('.swift') and not args[0].startswith('Sources'):
        rev = args.pop(0)
    paths = args or [p for p in subprocess.run(['git', 'diff', '--name-only', rev, '--', '*.swift'],
                     capture_output=True, text=True).stdout.split() if p.endswith('.swift')]
    root = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True).stdout.strip()
    bad = 0
    for p in paths:
        rel = p if p.startswith('Phoebus/') else 'Phoebus/' + p
        old = subprocess.run(['git', 'show', f'{rev}:{rel}'], capture_output=True, text=True, cwd=root).stdout
        try: new = open(root + '/' + rel).read()
        except FileNotFoundError: print('MISSING', p); bad += 1; continue
        a, b = strip(old), strip(new)
        if a != b:
            bad += 1
            for k, (x, y) in enumerate(zip(a, b)):
                if x != y: print(f'CODE CHANGED {p}: -{x[:90]}\n{" "*len("CODE CHANGED ")}+{y[:90]}'); break
            else: print(f'CODE CHANGED {p}: line count {len(a)} -> {len(b)}')
    print(f'code-unchanged: {len(paths)} files, {bad} with code changes')
    sys.exit(1 if bad else 0)

main()
