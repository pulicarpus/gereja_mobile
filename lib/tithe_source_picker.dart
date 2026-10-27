import 'package:flutter/material.dart';

/// Search filters the registered options; it never creates a new payee.
class TitheSourcePicker extends StatefulWidget {
  final String title;
  final List<String> options;
  final String? selected;
  const TitheSourcePicker({
    super.key,
    required this.title,
    required this.options,
    this.selected,
  });

  @override
  State<TitheSourcePicker> createState() => _TitheSourcePickerState();
}

class _TitheSourcePickerState extends State<TitheSourcePicker> {
  final _search = TextEditingController();
  String _query = '';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  @override
  Widget build(BuildContext context) {
    final visible =
        widget.options
            .where((name) => _normalize(name).contains(_query))
            .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('tithe-source-search'),
              controller: _search,
              onChanged: (value) => setState(() => _query = _normalize(value)),
              decoration: InputDecoration(
                hintText: 'Cari nama...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _search.text.isEmpty
                        ? null
                        : IconButton(
                          tooltip: 'Hapus pencarian',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child:
                  visible.isEmpty
                      ? Center(
                        child: Text(
                          widget.options.isEmpty
                              ? 'Belum ada data terdaftar.'
                              : 'Nama tidak ditemukan.',
                        ),
                      )
                      : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final name = visible[index];
                          return ListTile(
                            title: Text(name),
                            selected: widget.selected == name,
                            trailing:
                                widget.selected == name
                                    ? const Icon(
                                      Icons.check,
                                      color: Colors.indigo,
                                    )
                                    : null,
                            onTap: () => Navigator.pop(context, name),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
      ],
    );
  }
}
