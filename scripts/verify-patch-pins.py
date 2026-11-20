#!/usr/bin/env python3
"""Verify build.sh's six patch declarations without executing shell code."""
import hashlib
import pathlib
import re
import sys


def verify(root):
    root = pathlib.Path(root).resolve()
    lines = (root / 'build.sh').read_text().splitlines()
    for number in range(1, 7):
        suffix = '' if number == 1 else str(number)
        values = []
        for key in ('FORGE_PATCH' + suffix, 'EXPECTED_PATCH' + suffix + '_SHA256'):
            declarations = [line for line in lines if re.match(r'^\s*' + re.escape(key) + r'\s*=', line)]
            if len(declarations) != 1:
                raise ValueError(f'{key}: expected exactly one declaration')
            match = re.fullmatch(re.escape(key) + r'="([^"\r\n]+)"', declarations[0])
            if not match:
                raise ValueError(f'{key}: unsupported declaration syntax')
            values.append(match.group(1))
        name, expected = values
        if not re.fullmatch(r'patches/[A-Za-z0-9_-]+\.patch', name):
            raise ValueError(f'{name}: invalid patch path')
        if not re.fullmatch(r'[0-9a-f]{64}', expected):
            raise ValueError(f'{name}: invalid SHA256 pin')
        path = root / name
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root):
            raise ValueError(f'{name}: patch must be a regular file inside the repository')
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f'{name}: SHA256 mismatch')
    return 6


def main():
    if len(sys.argv) != 1:
        print('usage: verify-patch-pins.py', file=sys.stderr)
        return 2
    try:
        count = verify(pathlib.Path(__file__).resolve().parents[1])
    except (OSError, ValueError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 1
    print(f'PASS: {count} patch pins match build.sh')
    return 0


if __name__ == '__main__':
    sys.exit(main())
