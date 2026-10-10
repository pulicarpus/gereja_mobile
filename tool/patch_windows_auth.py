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


def instrument(source):
    replacements = {
        '  App* app = App::GetInstance(pigeonApp.app_name().c_str());':
            '  GkiiStartupTrace("auth: lookup app");\n  App* app = App::GetInstance(pigeonApp.app_name().c_str());\n  GkiiStartupTrace(app ? "auth: app found" : "auth: app missing");',
        '  Auth* auth = Auth::GetAuth(app);':
            '  GkiiStartupTrace("auth: get native Auth");\n  Auth* auth = Auth::GetAuth(app);\n  GkiiStartupTrace(auth ? "auth: native Auth found" : "auth: native Auth missing");',
        '    firebase::auth::User user = auth->current_user();':
            '    GkiiStartupTrace("auth: callback current user");\n    firebase::auth::User user = auth->current_user();\n    GkiiStartupTrace(user.is_valid() ? "auth: callback signed in" : "auth: callback signed out");',
        '    auth_->AddIdTokenListener(listener_);':
            '    GkiiStartupTrace("auth: add ID token listener");\n    auth_->AddIdTokenListener(listener_);\n    GkiiStartupTrace("auth: ID token listener added");',
        '    auth_->AddAuthStateListener(listener_);':
            '    GkiiStartupTrace("auth: add auth state listener");\n    auth_->AddAuthStateListener(listener_);\n    GkiiStartupTrace("auth: auth state listener added");',
    }
    for before, after in replacements.items():
        expected = 2 if 'current_user' in before else 1
        if source.count(before) != expected:
            raise ValueError('Auth diagnostic source changed')
        source = source.replace(before, after)
    return '#include "startup_trace.h"\n' + source


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('input')
    parser.add_argument('output')
    args = parser.parse_args()
    target = Path(args.output)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(instrument(patch(Path(args.input).read_text(encoding='utf-8'))), encoding='utf-8')
