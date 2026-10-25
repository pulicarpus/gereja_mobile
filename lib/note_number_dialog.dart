import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NoteNumberDialog extends StatefulWidget {
  final int initialNumber;
  const NoteNumberDialog({super.key, required this.initialNumber});
  @override
  State<NoteNumberDialog> createState() => _NoteNumberDialogState();
}

class _NoteNumberDialogState extends State<NoteNumberDialog> {
  late final _input = TextEditingController(text: '${widget.initialNumber}');
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ubah nomor daftar'),
    content: Form(
      key: _form,
      child: TextFormField(
        key: const ValueKey('note-list-start-input'),
        controller: _input,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 4,
        decoration: const InputDecoration(
          labelText: 'Mulai dari nomor',
          helperText: 'Baris berikutnya melanjutkan nomor ini.',
        ),
        validator: (value) {
          final parsed = int.tryParse(value ?? '');
          return parsed == null || parsed < 1 || parsed > 9999
              ? 'Isi angka 1–9999'
              : null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate())
            Navigator.pop(context, int.parse(_input.text));
        },
        child: const Text('Terapkan'),
      ),
    ],
  );
}
