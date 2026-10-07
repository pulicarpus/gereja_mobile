import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

const maxPhotoBytes = 10 * 1024 * 1024;
const maxAttachmentBytes = 20 * 1024 * 1024;
bool _starts(List<int> bytes, List<int> signature) => bytes.length >= signature.length &&
  List.generate(signature.length, (i) => bytes[i] == signature[i]).every((match) => match);
String uploadContentType(String name, List<int> header, int size, {bool attachment = false}) {
  if (size <= 0) throw StateError('File kosong atau tidak dapat dibaca.');
  if (size > (attachment ? maxAttachmentBytes : maxPhotoBytes)) {
    throw StateError(attachment ? 'Lampiran maksimal 20 MB.' : 'Foto maksimal 10 MB. Pilih foto yang lebih kecil.');
  }
  if (_starts(header, [255, 216, 255])) return 'image/jpeg';
  if (_starts(header, [137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
  if (_starts(header, [82, 73, 70, 70]) && header.length >= 12 && _starts(header.sublist(8), [87, 69, 66, 80])) return 'image/webp';
  if (attachment) {
    final extension = name.split('.').last.toLowerCase();
    if (extension == 'pdf' && _starts(header, [37, 80, 68, 70, 45])) return 'application/pdf';
    const office = {'doc': 'application/msword', 'xls': 'application/vnd.ms-excel', 'ppt': 'application/vnd.ms-powerpoint',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation'};
    final expected = office[extension];
    final signature = extension.endsWith('x') ? [80, 75, 3, 4] : [208, 207, 17, 224, 161, 177, 26, 225];
    if (expected != null && _starts(header, signature)) return expected;
  }
  throw StateError(attachment ? 'Format lampiran tidak didukung atau isi file tidak cocok. Gunakan foto, PDF, Word, Excel, atau PowerPoint.'
    : 'Format foto tidak didukung. Gunakan JPEG, PNG, atau WebP.');
}
Future<SettableMetadata> prepareUpload(File file, {bool attachment = false}) async {
  final size = await file.length();
  final reader = await file.open();
  try {
    final header = await reader.read(12);
    return SettableMetadata(contentType: uploadContentType(file.path, header, size, attachment: attachment));
  } finally { await reader.close(); }
}
