import 'package:flutter/services.dart';
import '../../model/admin_transport_fields.dart';
import 'admin_fields_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../model/catalog_record.dart';
import '../../service/cloud/catalog_admin_service.dart';
import '../../service/cloud/cloud_services.dart';
import '../../service/post_media_picker.dart';
import '../../state/account_state.dart';
import '../../service/photo_source.dart';
import '../../widgets/settings_actions.dart';

class CatalogEditScreen extends HookConsumerWidget {
  final CatalogKind kind;
  final CatalogRecord? record;
  const CatalogEditScreen({super.key, required this.kind, this.record});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = useTextEditingController(text: record?.id ?? '');
    final fields = useMemoized(() => catalogFields(kind), [kind]);
    final controllers = useMemoized(
      () => {
        for (final field in fields)
          field.key: TextEditingController(
            text:
                record?.data[field.key]?.toString() ??
                (field.number ? '0' : ''),
          ),
      },
      [record, kind],
    );
    useEffect(
      () => () {
        for (final controller in controllers.values) {
          controller.dispose();
        }
      },
      [controllers],
    );
    final photos = useState<List<CatalogPhotoDraft>>([
      for (final photo in record?.photos ?? <CloudCatalogPhoto>[])
        CatalogPhotoDraft(url: photo.url, path: photo.path),
    ]);
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final access = useMemoized(
      () => prepareAdminData(
        [accessStopsField],
        {'accessStops': record?.data['accessStops'] ?? []},
      ),
      [record],
    );
    final accessNotes = useTextEditingController(
      text: record?.data['accessNotes'] as String? ?? '',
    );
    final busy = useState(false);
    final error = useState<String?>(null);
    final authorized =
        ref.watch(isAdminProvider) &&
        ref.watch(currentAccountProvider).identity.emailVerified;
    const maxPhotos = 6;
    Future<void> pick() async {
      if (busy.value) return;
      busy.value = true;
      try {
        final picked = await ref
            .read(postMediaPickerProvider)
            .pick(
              PostMediaSource.library,
              remaining: maxPhotos - photos.value.length,
            );
        if (context.mounted) {
          photos.value = [
            ...photos.value,
            for (final item in picked) CatalogPhotoDraft(bytes: item.bytes),
          ];
        }
      } catch (failure) {
        if (context.mounted) {
          error.value = failure is StateError
              ? failure.message.toString()
              : '画像を選択できませんでした。';
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> save() async {
      if (busy.value || !formKey.currentState!.validate()) return;
      final values = <String, dynamic>{
        for (final field in fields)
          field.key: field.number
              ? int.tryParse(controllers[field.key]!.text.trim())
              : controllers[field.key]!.text.trim(),
      };
      final accessData = readAdminFormData([accessStopsField], access);
      try {
        validateAdminFields([accessStopsField], accessData);
      } on FormatException catch (e) {
        error.value = e.message;
        return;
      }
      values['accessStops'] = accessData['accessStops'];
      values['accessNotes'] = accessNotes.text;
      error.value = validateCatalogRecord(kind, id.text.trim(), values);
      if (error.value != null) return;
      busy.value = true;
      try {
        final failed = await ref
            .read(catalogAdminServiceProvider)
            .save(kind, id.text.trim(), values, photos.value, original: record);
        if (context.mounted) {
          showMessage(
            context,
            failed.isEmpty
                ? '保存しました。'
                : '情報は保存済みです。一部の旧写真の削除に失敗しました。Storageを確認してください。',
          );
          Navigator.pop(context);
        }
      } catch (failure) {
        if (context.mounted) {
          error.value = failure is StateError
              ? failure.message.toString()
              : '保存できませんでした。Firebaseの設定・権限・通信を確認してください。入力は保持しています。';
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return PopScope(
      canPop: !busy.value,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${kind.label}：${record == null ? '追加' : '編集'}'),
        ),
        body: !authorized
            ? const Center(child: Text('メール確認済みの管理者アカウントが必要です。'))
            : Form(
                key: formKey,
                child: ListView(
                  key: const ValueKey('catalog-edit-form'),
                  padding: const EdgeInsets.all(20),
                  children: [
                    TextField(
                      key: const ValueKey('catalog-id'),
                      controller: id,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9_ -]'),
                        ),
                        LengthLimitingTextInputFormatter(80),
                      ],
                      enabled: !busy.value && record == null,
                      decoration: const InputDecoration(
                        labelText: 'ID（作成後は変更不可）',
                      ),
                    ),
                    for (final field in fields)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: TextField(
                          key: ValueKey('catalog-${field.key}'),
                          controller: controllers[field.key],
                          inputFormatters: [
                            if (field.number)
                              FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(
                              field.number ? 6 : 10000,
                            ),
                          ],
                          enabled: !busy.value,
                          keyboardType: field.number
                              ? TextInputType.number
                              : field.multiline
                              ? TextInputType.multiline
                              : TextInputType.text,
                          minLines: field.multiline ? 3 : 1,
                          maxLines: field.multiline ? 8 : 1,
                          decoration: InputDecoration(labelText: field.label),
                        ),
                      ),
                    if (kind == CatalogKind.sightseeing) ...[
                      const SizedBox(height: 16),
                      AdminFieldsForm(
                        fields: const [accessStopsField],
                        data: access,
                        enabled: !busy.value,
                      ),
                      TextField(
                        controller: accessNotes,
                        enabled: !busy.value,
                        decoration: const InputDecoration(
                          labelText: 'アクセスの根拠・入口などの補足',
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      '写真（${photos.value.length}/$maxPhotos）',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      '1枚5MB未満。先頭が代表写真、2枚目以降が補足写真です。',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < photos.value.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 88,
                              height: 78,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: photos.value[i].bytes != null
                                    ? Image.memory(
                                        photos.value[i].bytes!,
                                        fit: BoxFit.cover,
                                      )
                                    : Image(
                                        image: photoSource(photos.value[i].url),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, error, stack) =>
                                            const Icon(
                                              Icons.broken_image_outlined,
                                            ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(i == 0 ? '代表写真' : '補足写真 $i')),
                            if (i > 0)
                              IconButton(
                                tooltip: '先頭にする',
                                onPressed: busy.value
                                    ? null
                                    : () {
                                        final next = [...photos.value];
                                        final selected = next.removeAt(i);
                                        next.insert(0, selected);
                                        photos.value = next;
                                      },
                                icon: const Icon(Icons.vertical_align_top),
                              ),
                            IconButton(
                              tooltip: '写真を除く',
                              onPressed: busy.value
                                  ? null
                                  : () {
                                      final next = [...photos.value]
                                        ..removeAt(i);
                                      photos.value = next;
                                    },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('catalog-add-photo'),
                      onPressed: busy.value || photos.value.length >= maxPhotos
                          ? null
                          : pick,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('写真を追加'),
                    ),
                    if (error.value != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          error.value!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const ValueKey('catalog-save'),
                      onPressed: busy.value ? null : save,
                      child: Text(busy.value ? 'アップロード・保存中…' : '保存'),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}
