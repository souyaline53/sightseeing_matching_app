import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/admin_transport_fields.dart';
import '../../model/transport.dart';
import '../../service/cloud/cloud_services.dart';

Map<String, dynamic> prepareAdminData(
  List<AdminField> fields,
  Map<String, dynamic> original,
) {
  final data = {...original};
  for (final f in fields) {
    final v = data[f.key];
    if (f.type == AdminInput.rows) {
      final rows = v is List ? v : [];
      data[f.key] = f.children.length == 1 && f.children.first.key == 'value'
          ? [...rows]
          : [
              for (final r in rows)
                prepareAdminData(
                  f.children,
                  Map<String, dynamic>.from(r as Map),
                ),
            ];
      if (rows.isEmpty && f.minRows > 0) {
        data[f.key] = List.generate(
          f.minRows,
          (i) => prepareAdminData(f.children, {'sequence': i + 1}),
        );
      }
    } else if (f.type == AdminInput.weekdays) {
      data[f.key] = v is List ? [...v] : <int>[];
    } else if (f.type == AdminInput.toggle) {
      data[f.key] =
          v ?? (f.key == 'pickupAllowed' || f.key == 'dropoffAllowed');
    } else if (f.type == AdminInput.choice && v == null) {
      data[f.key] = switch (f.key) {
        'timezone' => 'Asia/Tokyo',
        'sourceType' => 'manual',
        'verificationStatus' => 'unverified',
        _ => null,
      };
    } else if (f.type == AdminInput.date && v != null) {
      DateTime? date;
      if (v is DateTime) {
        date = v;
      } else if (v is String) {
        date = DateTime.tryParse(v);
      } else {
        try {
          date = (v as dynamic).toDate() as DateTime;
        } catch (_) {}
      }
      if (date != null) {
        data[f.key] =
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }
    } else if ([
      AdminInput.text,
      AdminInput.url,
      AdminInput.id,
    ].contains(f.type)) {
      data[f.key] = v?.toString() ?? '';
    }
  }
  return data;
}

final adminReferenceOptionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, String>>, String>((ref, collection) async {
      final cloud = await ref.watch(cloudServicesProvider.future);
      cloud.requireAdmin();
      final snapshot = await cloud.firestore
          .collection(collection)
          .limit(100)
          .get();
      return snapshot.docs
          .map(
            (d) => {
              'id': d.id,
              'name': (d.data()['name'] ?? d.data()['headsign'] ?? d.id)
                  .toString(),
            },
          )
          .toList();
    });

class AdminFieldsForm extends StatelessWidget {
  final List<AdminField> fields;
  final Map<String, dynamic> data;
  final bool enabled;
  final String prefix;
  const AdminFieldsForm({
    super.key,
    required this.fields,
    required this.data,
    this.enabled = true,
    this.prefix = '',
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final f in fields)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: AdminFieldInput(
            key: ValueKey('$prefix${f.key}'),
            field: f,
            data: data,
            enabled: enabled,
            prefix: prefix,
          ),
        ),
    ],
  );
}

class AdminFieldInput extends StatefulWidget {
  final AdminField field;
  final Map<String, dynamic> data;
  final bool enabled;
  final String prefix;
  const AdminFieldInput({
    super.key,
    required this.field,
    required this.data,
    required this.enabled,
    this.prefix = '',
  });
  @override
  State<AdminFieldInput> createState() => _InputState();
}

class _InputState extends State<AdminFieldInput> {
  late final TextEditingController text;
  AdminField get f => widget.field;
  dynamic get value => widget.data[f.key];
  @override
  void initState() {
    super.initState();
    text = TextEditingController(
      text: f.type == AdminInput.time
          ? (value is int ? transportTime(value as int) : '')
          : value?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  String? validate(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return f.required ? '${f.label}を入力してください' : null;
    dynamic v = s;
    if (f.type == AdminInput.integer) v = int.tryParse(s);
    if (f.type == AdminInput.decimal) v = double.tryParse(s);
    if (f.type == AdminInput.time) v = parseAdminTime(s);
    if (v == null) {
      return f.type == AdminInput.time
          ? '08:10、25:10のように入力してください'
          : '正しい数値を入力してください';
    }
    try {
      validateAdminFields([f], {f.key: v});
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  void change(String s) {
    widget.data[f.key] = switch (f.type) {
      AdminInput.integer => int.tryParse(s),
      AdminInput.decimal => double.tryParse(s),
      AdminInput.time => parseAdminTime(s),
      _ => s.trim(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final label = '${f.label}${f.required ? '（必須）' : ''}';
    if (f.type == AdminInput.rows) {
      return AdminRowsEditor(
        field: f,
        data: widget.data,
        enabled: widget.enabled,
        prefix: widget.prefix,
      );
    }
    if (f.type == AdminInput.weekdays) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 1; i <= 7; i++)
                FilterChip(
                  label: Text(['月', '火', '水', '木', '金', '土', '日'][i - 1]),
                  selected: (value as List).contains(i),
                  onSelected: widget.enabled
                      ? (selected) => setState(() {
                          final days = List<int>.from(value as List);
                          selected ? days.add(i) : days.remove(i);
                          days.sort();
                          widget.data[f.key] = days;
                        })
                      : null,
                ),
            ],
          ),
        ],
      );
    }
    if (f.type == AdminInput.toggle) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value == true,
        onChanged: widget.enabled
            ? (v) => setState(() => widget.data[f.key] = v)
            : null,
      );
    }
    if (f.type == AdminInput.choice) {
      return DropdownButtonFormField<String>(
        initialValue: f.options.containsKey(value) ? value as String : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: f.options.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: widget.enabled
            ? (v) => setState(() => widget.data[f.key] = v)
            : null,
        validator: (v) => f.required && v == null
            ? '選択してください'
            : value != null && !f.options.containsKey(value)
            ? '選択肢から選び直してください'
            : null,
      );
    }
    if (f.type == AdminInput.date) {
      return TextFormField(
        controller: text,
        enabled: widget.enabled,
        readOnly: true,
        validator: validate,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!f.required)
                IconButton(
                  tooltip: '日付をクリア',
                  onPressed: widget.enabled
                      ? () {
                          text.clear();
                          widget.data[f.key] = null;
                          setState(() {});
                        }
                      : null,
                  icon: const Icon(Icons.clear),
                ),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.calendar_today),
              ),
            ],
          ),
        ),
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: DateTime.tryParse(text.text) ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime(2200),
          );
          if (date != null && mounted) {
            final s =
                '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            setState(() {
              text.text = s;
              widget.data[f.key] = s;
            });
          }
        },
      );
    }
    final numeric = [AdminInput.integer, AdminInput.decimal].contains(f.type);
    final input = TextFormField(
      key: ValueKey('${widget.prefix}input-${f.key}'),
      controller: text,
      enabled: widget.enabled,
      validator: validate,
      onChanged: change,
      maxLength: f.type == AdminInput.integer
          ? 10
          : f.type == AdminInput.id
          ? 80
          : f.type == AdminInput.time
          ? 6
          : 10000,
      minLines: f.multiline ? 2 : 1,
      maxLines: f.multiline ? 5 : 1,
      keyboardType: numeric
          ? TextInputType.numberWithOptions(
              decimal: f.type == AdminInput.decimal,
              signed: f.type == AdminInput.decimal,
            )
          : f.type == AdminInput.time
          ? TextInputType.datetime
          : f.type == AdminInput.url
          ? TextInputType.url
          : TextInputType.text,
      inputFormatters: [
        if (f.type == AdminInput.integer)
          FilteringTextInputFormatter.digitsOnly,
        if (f.type == AdminInput.decimal)
          TextInputFormatter.withFunction(
            (old, next) =>
                RegExp(r'^-?\d*(\.\d*)?$').hasMatch(next.text) ? next : old,
          ),
        if (f.type == AdminInput.id)
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
        if (f.type == AdminInput.time)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        helperText: f.type == AdminInput.time
            ? '例 08:10 / 翌日01:10は25:10。空欄は不明'
            : f.type == AdminInput.integer
            ? '${f.min ?? 0}以上の整数のみ'
            : null,
      ),
    );
    if (f.reference == null) return input;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        input,
        Consumer(
          builder: (context, ref, _) {
            final options = ref.watch(
              adminReferenceOptionsProvider(f.reference!),
            );
            return options.when(
              loading: () => const Text('登録済みの候補を読み込み中…'),
              error: (_, stack) => const Text('候補を取得できませんでした。IDを直接入力できます。'),
              data: (items) => Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.list_alt),
                  label: const Text('登録済みから選ぶ'),
                  onPressed: !widget.enabled
                      ? null
                      : () async {
                          final id = await showDialog<String>(
                            context: context,
                            builder: (context) => SimpleDialog(
                              title: Text(f.label),
                              children: [
                                if (items.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('候補は未登録です。先に対象データを追加してください。'),
                                  ),
                                for (final item in items)
                                  SimpleDialogOption(
                                    onPressed: () =>
                                        Navigator.pop(context, item['id']),
                                    child: Text(
                                      '${item['name']}（${item['id']}）',
                                    ),
                                  ),
                              ],
                            ),
                          );
                          if (id != null && mounted) {
                            setState(() {
                              text.text = id;
                              widget.data[f.key] = id;
                            });
                          }
                        },
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class AdminRowsEditor extends StatefulWidget {
  final AdminField field;
  final Map<String, dynamic> data;
  final bool enabled;
  final String prefix;
  const AdminRowsEditor({
    super.key,
    required this.field,
    required this.data,
    required this.enabled,
    this.prefix = '',
  });
  @override
  State<AdminRowsEditor> createState() => _RowsState();
}

class _RowsState extends State<AdminRowsEditor> {
  late final List<Map<String, dynamic>> rows;
  bool get scalar =>
      widget.field.children.length == 1 &&
      widget.field.children.first.key == 'value';
  @override
  void initState() {
    super.initState();
    rows = (widget.data[widget.field.key] as List? ?? [])
        .map((r) => scalar ? {'value': r} : Map<String, dynamic>.from(r as Map))
        .toList();
    sync();
  }

  void sync() {
    widget.data[widget.field.key] = scalar
        ? rows.map((r) => r['value']).toList()
        : rows;
    if (scalar) widget.data['_formRows_${widget.field.key}'] = rows;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(widget.field.label, style: Theme.of(context).textTheme.titleMedium),
      for (var i = 0; i < rows.length; i++)
        Card(
          key: ObjectKey(rows[i]),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${i + 1}件目')),
                    IconButton(
                      tooltip: 'この項目を削除',
                      onPressed: !widget.enabled
                          ? null
                          : () => setState(() {
                              rows.removeAt(i);
                              sync();
                            }),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                // Scalar rows must synchronize after each edit as the stored array has scalar values.
                AdminFieldsForm(
                  fields: widget.field.children,
                  data: rows[i],
                  enabled: widget.enabled,
                  prefix: '${widget.prefix}${widget.field.key}-$i-',
                ),
              ],
            ),
          ),
        ),
      if (rows.isEmpty) const Text('未登録です。追加ボタンから入力できます。'),
      OutlinedButton.icon(
        onPressed: !widget.enabled || rows.length >= widget.field.maxRows
            ? null
            : () => setState(() {
                rows.add(
                  prepareAdminData(
                    widget.field.children,
                    widget.field.key == 'stopTimes'
                        ? {
                            'sequence':
                                rows.fold<int>(
                                  0,
                                  (max, row) =>
                                      row['sequence'] is int &&
                                          (row['sequence'] as int) > max
                                      ? row['sequence'] as int
                                      : max,
                                ) +
                                1,
                          }
                        : {},
                  ),
                );
                sync();
              }),
        icon: const Icon(Icons.add),
        label: Text('${widget.field.label}を追加'),
      ),
    ],
  );
  @override
  void didUpdateWidget(covariant AdminRowsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }
}

// Build a typed snapshot without persisting internal row editing state.
Map<String, dynamic> readAdminFormData(
  List<AdminField> fields,
  Map<String, dynamic> data,
) {
  final result = {
    for (final e in data.entries)
      if (!e.key.startsWith('_formRows_')) e.key: e.value,
  };
  for (final f in fields) {
    final live = data['_formRows_${f.key}'];
    if (live is List) {
      result[f.key] = live.map((r) => (r as Map)['value']).toList();
    }
    if (f.type == AdminInput.rows && f.children.length > 1) {
      result[f.key] = [
        for (final r in data[f.key] as List? ?? [])
          readAdminFormData(f.children, r as Map<String, dynamic>),
      ];
    }
  }
  return result;
}
