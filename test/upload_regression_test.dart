import 'package:flutter_test/flutter_test.dart';
import '../lib/upload_support.dart';

void main() {
  test('upload uses actual JPEG/PNG/WebP signature, not file extension', () {
    expect(uploadContentType('file.jpg', [137,80,78,71,13,10,26,10], 100), 'image/png');
    expect(uploadContentType('file.txt', [255,216,255], 100), 'image/jpeg');
    expect(uploadContentType('file.jpg', [82,73,70,70,0,0,0,0,87,69,66,80], 100), 'image/webp');
    expect(() => uploadContentType('file.jpg', [60,104,116,109,108], 100), throwsStateError);
  });
  test('photo and attachment limits reject empty and oversized files', () {
    expect(uploadContentType('a.jpg', [255,216,255], maxPhotoBytes), 'image/jpeg');
    expect(() => uploadContentType('a.jpg', [255,216,255], maxPhotoBytes+1), throwsStateError);
    expect(() => uploadContentType('a.pdf', [37,80,68,70,45], maxAttachmentBytes+1, attachment: true), throwsStateError);
    expect(() => uploadContentType('a.jpg', [255,216,255], 0), throwsStateError);
  });
  test('PDF and uppercase Office extensions use compatible MIME types and validate container header', () {
    expect(uploadContentType('a.PDF', [37,80,68,70,45], 100, attachment: true), 'application/pdf');
    expect(uploadContentType('a.DOCX', [80,75,3,4], 100, attachment: true), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    expect(uploadContentType('a.xls', [208,207,17,224,161,177,26,225], 100, attachment: true), 'application/vnd.ms-excel');
    expect(() => uploadContentType('a.pdf', [80,75,3,4], 100, attachment: true), throwsStateError);
  });
}
