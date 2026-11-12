import '../../model/spot_visit_info.dart';
import 'spot_visit_info_form.dart';
import 'dart:async';
import '../../service/address_geocoder.dart';
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
    final visitDraft = useMemoized(() => SpotVisitDraft(record?.data ?? {}), [
      record,
    ]);
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
    final latitude = useTextEditingController(
      text: record?.data['latitude']?.toString() ?? '',
    );
    final longitude = useTextEditingController(
      text: record?.data['longitude']?.toString() ?? '',
    );
    final manual = useState(false);
    final resolving = useState(false);
    final locationError = useState<String?>(null);
    final resolvedAddress = useState(record?.data['address'] as String?);
    final timer = useRef<Timer?>(null);
    final revision = useRef(0);
    useEffect(
      () => () {
        timer.value?.cancel();
        revision.value++;
      },
      const [],
    );
    Future<void> resolveAddress() async {
      final version = ++revision.value;
      final address = controllers['address']!.text.trim();
      resolving.value = true;
      locationError.value = null;
      try {
        final point = await ref.read(addressGeocoderProvider).resolve(address);
        if (!context.mounted || version != revision.value) return;
        latitude.text = point.latitude.toString();
        longitude.text = point.longitude.toString();
        resolvedAddress.value = address;
      } catch (failure) {
        if (!context.mounted || version != revision.value) return;
        locationError.value = failure is StateError
            ? failure.message.toString()
            : '住所を変換できません。緯度・経度を入力してください。';
      } finally {
        if (context.mounted && version == revision.value) {
          resolving.value = false;
        }
      }
    }

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
      busy.value = true;
      try {
        final values = <String, dynamic>{
          for (final field in fields)
            field.key: field.number
                ? int.tryParse(controllers[field.key]!.text.trim())
                : controllers[field.key]!.text.trim(),
        };
        if (!manual.value &&
            resolvedAddress.value != controllers['address']!.text.trim()) {
          timer.value?.cancel();
          await resolveAddress();
          if (!context.mounted || locationError.value != null) return;
        }
        values['latitude'] = double.tryParse(latitude.text.trim());
        values['longitude'] = double.tryParse(longitude.text.trim());
        if (values['latitude'] == null || values['longitude'] == null) {
          error.value = '緯度・経度を入力してください。';
          return;
        }
        final accessData = readAdminFormData([accessStopsField], access);
        try {
          validateAdminFields([accessStopsField], accessData);
        } on FormatException catch (e) {
          error.value = e.message;
          return;
        }
        values['accessStops'] = accessData['accessStops'];
        if (kind == CatalogKind.sightseeing) {
          values['accessNotes'] = accessNotes.text;
          try {
            final visit = SpotVisitInfo.fromMap(visitDraft.snapshot())
              ..validate();
            values.addAll(visit.toMap());
          } on FormatException catch (e) {
            error.value = e.message;
            return;
          }
        }
        error.value = validateCatalogRecord(kind, id.text.trim(), values);
        if (error.value != null) return;
        busy.value = true;
        try {
          final failed = await ref
              .read(catalogAdminServiceProvider)
              .save(
                kind,
                id.text.trim(),
                values,
                photos.value,
                original: record,
              );
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
                        if (kind == CatalogKind.sightseeing)
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9_ -]'),
                          ),
                        LengthLimitingTextInputFormatter(80),
                      ],
                      enabled: !busy.value && record == null,
                      decoration: InputDecoration(
                        labelText: 'ID（作成後は変更不可）',
                        helperText: kind == CatalogKind.departure
                            ? '出発地の表示名です。例：札幌駅'
                            : null,
                      ),
                    ),
                    for (final field in fields)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: TextFormField(
                          key: ValueKey('catalog-${field.key}'),
                          controller: controllers[field.key],
                          onChanged: field.key == 'address'
                              ? (_) {
                                  timer.value?.cancel();
                                  revision.value++;
                                  resolvedAddress.value = null;
                                  resolving.value = false;
                                  locationError.value = null;
                                  if (!manual.value) {
                                    timer.value = Timer(
                                      const Duration(milliseconds: 700),
                                      resolveAddress,
                                    );
                                  }
                                }
                              : null,
                          inputFormatters: [
                            if (field.number)
                              FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(
                              field.number ? 6 : field.maxLength,
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
                          validator: field.key == 'name'
                              ? (value) => value == null || value.trim().isEmpty
                                    ? '観光地名称を入力してください。'
                                    : null
                              : null,
                          decoration: InputDecoration(
                            labelText: field.key == 'name'
                                ? '${field.label}（必須）'
                                : field.label,
                            helperText: field.key == 'name'
                                ? '旅程に表示する短い名称です。例：○○公園、○○美術館'
                                : field.key == 'title'
                                ? '体験カードで興味を惹く紹介文として表示します。'
                                : null,
                          ),
                        ),
                      ),
                    if (resolving.value) const Text('住所から座標に変換中…'),
                    if (locationError.value != null)
                      Text(
                        locationError.value!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    SwitchListTile(
                      title: const Text('緯度・経度を直接指定する'),
                      value: manual.value,
                      onChanged: busy.value
                          ? null
                          : (value) {
                              timer.value?.cancel();
                              revision.value++;
                              resolving.value = false;
                              manual.value = value;
                              if (!value) {
                                resolvedAddress.value = null;
                                resolveAddress();
                              }
                            },
                    ),
                    for (final entry in {
                      '緯度（−90〜90）': latitude,
                      '経度（−180〜180）': longitude,
                    }.entries)
                      TextField(
                        controller: entry.value,
                        enabled: manual.value && !busy.value,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: InputDecoration(labelText: entry.key),
                      ),
                    const SizedBox(height: 16),
                    AdminFieldsForm(
                      fields: const [accessStopsField],
                      data: access,
                      enabled: !busy.value,
                    ),
                    if (kind == CatalogKind.sightseeing)
                      TextField(
                        controller: accessNotes,
                        enabled: !busy.value,
                        decoration: const InputDecoration(
                          labelText: 'アクセスの根拠・入口などの補足',
                        ),
                      ),
                    if (kind == CatalogKind.sightseeing)
                      SpotVisitInfoForm(
                        draft: visitDraft,
                        enabled: !busy.value,
                      ),
                    if (kind == CatalogKind.sightseeing) ...[
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
                                          image: photoSource(
                                            photos.value[i].url,
                                          ),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, error, stack) =>
                                              const Icon(
                                                Icons.broken_image_outlined,
                                              ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(i == 0 ? '代表写真' : '補足写真 $i'),
                              ),
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
                        onPressed:
                            busy.value || photos.value.length >= maxPhotos
                            ? null
                            : pick,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('写真を追加'),
                      ),
                    ],
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
                      onPressed: busy.value || resolving.value ? null : save,
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
