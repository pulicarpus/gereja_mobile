"""Keep the Pigeon and document-reference codecs on the same native instance."""
from pathlib import Path
import sys


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f"FlutterFire layout changed: expected one {old!r}")
    return source.replace(old, new)


def patch(filename, source):
    source = replace_once(source, "firestore->set_settings(settings);",
                          "gkii_apply_firestore_settings(firestore, settings);")
    if filename == "cloud_firestore_plugin.cpp":
        source = replace_once(source,
            'pigeonApp.app_name() + "-" + pigeonApp.database_u_r_l()',
            'gkii_firestore_cache_key(pigeonApp.app_name(), pigeonApp.database_u_r_l())')
        source = replace_once(source,
            'Firestore::GetInstance(app, pigeonApp.database_u_r_l().c_str());',
            'Firestore::GetInstance(app, gkii_firestore_database_id(pigeonApp.database_u_r_l()).c_str());')
    elif filename == "firestore_codec.cpp":
        source = replace_once(source,
            'if (CloudFirestorePlugin::firestoreInstances_.find(appName) !=',
            'const std::string cacheKey = gkii_firestore_cache_key(appName, databaseUrl);\n'
            '      if (CloudFirestorePlugin::firestoreInstances_.find(cacheKey) !=')
        # This codec formerly used appName alone, creating another unique_ptr
        # for the same SDK instance and reapplying settings after it started.
        if source.count('firestoreInstances_[appName]') != 2:
            raise ValueError("Unexpected Firestore codec cache layout")
        source = source.replace('firestoreInstances_[appName]', 'firestoreInstances_[cacheKey]')
        source = replace_once(source, 'Firestore::GetInstance(app);',
            'Firestore::GetInstance(app, gkii_firestore_database_id(databaseUrl).c_str());')
    else:
        raise ValueError(f"Unknown source: {filename}")
    return '#include "firestore_settings_guard.h"\n' + source


if __name__ == '__main__':
    original, destination = map(Path, sys.argv[1:])
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(patch(original.name, original.read_text(encoding='utf-8')), encoding='utf-8')
