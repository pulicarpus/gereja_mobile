"""Do not read user metadata for a signed-out Windows Firebase user."""
import argparse
from pathlib import Path


def patch(source):
    for listener in ('FlutterIdTokenListener', 'FlutterAuthStateListener'):
        start = source.index('class ' + listener + ' :')
        end = source.index('\n private:', start)
        section = source[start:end]
        parse = '\n    PigeonUserDetails userDetails = FirebaseAuthPlugin::ParseUserDetails(user);\n'
        valid = '      if (user.is_valid()) {\n'
        if section.count(parse) != 1 or section.count(valid) != 1:
            raise ValueError('Upstream Windows auth listener changed: ' + listener)
        section = section.replace(parse, '\n').replace(valid, valid + '        PigeonUserDetails userDetails = FirebaseAuthPlugin::ParseUserDetails(user);\n')
        source = source[:start] + section + source[end:]
    return source


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('input')
    parser.add_argument('output')
    args = parser.parse_args()
    target = Path(args.output)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(patch(Path(args.input).read_text(encoding='utf-8')), encoding='utf-8')
