import 'package:flutter/material.dart';
import 'family_service.dart';

Future<bool> confirmCancelFamilyHead(
  BuildContext context,
  String churchId,
  String memberId,
  String name,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Batalkan jadi kepala keluarga?'),
      content: Text(
        '$name akan menjadi jemaat yang belum terikat keluarga. Data jemaat dan akun tetap tersimpan. Tindakan ini hanya dapat dilakukan setelah tidak ada anggota lain dalam keluarga.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Batalkan status'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await FamilyService().cancelHead(churchId, memberId);
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Status kepala keluarga dibatalkan. Data jemaat tetap tersimpan.',
          ),
        ),
      );
    return true;
  } catch (error) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message.toString()
                : 'Pembatalan belum berhasil. Periksa koneksi dan muat ulang data sebelum mencoba lagi.',
          ),
        ),
      );
    return false;
  }
}
