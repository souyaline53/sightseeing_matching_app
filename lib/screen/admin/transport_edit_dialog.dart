import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../model/admin_transport_fields.dart';
import 'admin_fields_form.dart';

class TransportEditDialog extends StatefulWidget {
  final String collection, title;
  final Map<String, dynamic>? record;
  final bool duplicate;
  final Future<void> Function(String, Map<String, dynamic>) onSave;
  const TransportEditDialog({
    super.key,
    required this.collection,
    required this.title,
    this.record,
    this.duplicate = false,
    required this.onSave,
  });
  @override
  State<TransportEditDialog> createState() => _EditState();
}

class _EditState extends State<TransportEditDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController id;
  late final List<AdminField> fields;
  late final Map<String, dynamic> draft;
  bool busy = false;
  String? error;
  bool get creating => widget.record == null || widget.duplicate;
  @override
  void initState() {
    super.initState();
    fields = transportFields(widget.collection);
    draft = prepareAdminData(
      fields,
      {...?widget.record}
        ..remove('id')
        ..remove('createdAt')
        ..remove('updatedAt'),
    );
    id = TextEditingController(
      text: creating ? '' : widget.record!['id'] as String,
    );
  }

  @override
  void dispose() {
    id.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    if (!form.currentState!.validate()) {
      setState(() => error = '入力内容を確認してください。各項目に表示されたエラーを修正してください。');
      return;
    }
    final data = readAdminFormData(fields, draft);
    try {
      validateTransport(widget.collection, data);
    } on FormatException catch (e) {
      setState(() => error = e.message);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave(id.text, data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is StateError
              ? e.message.toString()
              : e is FormatException
              ? e.message
              : '保存できませんでした。入力内容は保持しています。通信・権限を確認してください。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text('${widget.title}：${creating ? '追加' : '編集'}'),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('項目ごとに入力してください。空欄の徒歩時間・時刻は「不明」として保存します。'),
                TextFormField(
                  key: const ValueKey('transport-id'),
                  controller: id,
                  enabled: !busy && creating,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
                    LengthLimitingTextInputFormatter(80),
                  ],
                  decoration: const InputDecoration(
                    labelText: '内部ID（英数字・_・-、作成後は変更不可）',
                  ),
                  validator: (v) =>
                      v == null || !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(v)
                      ? 'IDを1〜80文字で入力してください'
                      : null,
                ),
                AdminFieldsForm(fields: fields, data: draft, enabled: !busy),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (error != null)
          Text(
            error!,
            key: const ValueKey('transport-form-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const ValueKey('transport-save'),
          onPressed: busy ? null : save,
          child: Text(busy ? '保存中' : 'この1件を保存'),
        ),
      ],
    ),
  );
}
