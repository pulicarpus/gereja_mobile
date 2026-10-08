"""Keep SDK references and Flutter event sinks alive for Windows Storage tasks."""
import argparse
import re
from pathlib import Path


def patch(source):
    methods = ('ReferenceDelete', 'ReferenceGetDownloadURL', 'ReferenceGetMetaData',
               'ReferenceGetData', 'ReferenceUpdateMetadata')
    for method in methods:
        pattern = rf'(void FirebaseStoragePlugin::{method}\([\s\S]*?)(?=\n(?:void |firebase::|std::|class )|\Z)'
        matches = list(re.finditer(pattern, source))
        if len(matches) != 1:
            raise ValueError(f'Expected one {method} implementation')
        match = matches[0]
        section = match.group(0)
        old = 'StorageReference cpp_reference =\n      GetCPPStorageReferenceFromPigeon(app, reference);'
        if section.count(old) != 1:
            raise ValueError(f'Upstream reference lifetime changed in {method}')
        section = section.replace(old, 'auto cpp_reference = gkii_storage_reference(\n      GetCPPStorageReferenceFromPigeon(app, reference));')
        section = section.replace('cpp_reference.', 'cpp_reference->')
        capture = '[result, byte_buffer]' if method == 'ReferenceGetData' else '[result]'
        if section.count(capture) != 1:
            raise ValueError(f'Upstream callback changed in {method}')
        section = section.replace(capture, capture[:-1] + ', cpp_reference]')
        source = source[:match.start()] + section + source[match.end():]
    local_ref = 'StorageReference reference = storage_->GetReference(reference_path_);'
    if source.count(local_ref) != 3:
        raise ValueError('Expected three upload/download stream references')
    source = source.replace(local_ref, 'reference_ = storage_->GetReference(reference_path_);\n    StorageReference& reference = reference_;')
    sink = 'std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events_ =\n      nullptr;'
    if source.count(sink) != 3:
        raise ValueError('Expected three dangling event sink members')
    source = source.replace(sink, 'StorageReference reference_;\n  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> events_;')
    return '#include "storage_reference_owner.h"\n' + source


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    result = patch(Path(args.input).read_text(encoding='utf-8'))
    target = Path(args.output)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(result, encoding='utf-8')
