import 'package:flutter/material.dart';
import 'management_service.dart';
import 'management_support.dart';

Future<void> manageRegion(
  BuildContext context,
  String area,
  String label, {
  required bool delete,
  ManagementGateway? gateway,
}) async {
  final service = gateway ?? FirebaseManagementGateway();
  final controller = TextEditingController(text: label);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(delete ? 'Hapus Daerah?' : 'Edit Nama Daerah'),
      content: delete
          ? Text(
              'Hapus $label dari daftar aktif bersama semua gereja kosong di daerah ini? Jika masih ada akun, jemaat, pengurus, inventaris, atau riwayat, penghapusan ditolak. Gereja disimpan di Arsip Gereja dan dapat dipulihkan.',
            )
          : TextField(
              controller: controller,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Nama Daerah'),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () {
            final name = controller.text.trim();
            if (delete || name.isNotEmpty)
              Navigator.pop(context, delete ? 'delete' : name);
          },
          child: Text(delete ? 'Hapus' : 'Simpan'),
        ),
      ],
    ),
  );
  // Let the dialog finish its closing animation before disposing its controller.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  if (value == null || !context.mounted) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Menyimpan perubahan…')),
          ],
        ),
      ),
    ),
  );
  String message;
  try {
    if (delete) {
      await service.deleteRegion(area);
    } else {
      await service.renameRegion(area, value);
    }
    message = delete
        ? 'Daerah dihapus dari daftar aktif.'
        : 'Nama daerah diperbarui.';
  } catch (error) {
    message = managementError(error);
  }
  if (navigator.mounted) navigator.pop();
  if (context.mounted)
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
}
