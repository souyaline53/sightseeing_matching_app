import 'package:flutter/material.dart';
import '../../model/admin_transport_fields.dart';
import '../../model/spot_visit_info.dart';
import 'admin_fields_form.dart';

const _hoursFields = [
  AdminField('open', '開始（HH:mm）', required: true),
  AdminField('close', '終了（HH:mm）', required: true),
];
const _specialFields = [
  AdminField('date', '日付（日本時間）', type: AdminInput.date, required: true),
  AdminField('closed', '臨時休業', type: AdminInput.toggle),
  AdminField('hours', '特別営業時間', type: AdminInput.rows, children: _hoursFields),
  AdminField('note', '補足'),
];
const _periodFields = [
  AdminField(
    'startMonth',
    '開始月',
    type: AdminInput.integer,
    required: true,
    min: 1,
    max: 12,
  ),
  AdminField(
    'startDay',
    '開始日',
    type: AdminInput.integer,
    required: true,
    min: 1,
    max: 31,
  ),
  AdminField(
    'endMonth',
    '終了月',
    type: AdminInput.integer,
    required: true,
    min: 1,
    max: 12,
  ),
  AdminField(
    'endDay',
    '終了日',
    type: AdminInput.integer,
    required: true,
    min: 1,
    max: 31,
  ),
];

/// Draft owns mutable form maps; snapshot removes shared row-editor bookkeeping.
class SpotVisitDraft {
  final Map<String, dynamic> data;
  SpotVisitDraft(Map<String, dynamic> source)
    : data = SpotVisitInfo.fromMap(source).toMap();
  final weekly = <String, dynamic>{};
  final weeklyOpen = <String, bool>{};
  bool initialized = false;
  void initialize() {
    if (initialized) return;
    initialized = true;
    final raw = data['openingHours'] as Map? ?? {};
    for (final day in spotWeekdays.keys) {
      weekly[day] = prepareAdminData(
        [_dayField(day)],
        {day: raw[day] ?? []},
      )[day];
    }
    for (final day in spotWeekdays.keys) {
      weeklyOpen[day] = (weekly[day] as List).isNotEmpty;
    }
    data['specialHours'] = prepareAdminData(const [
      _specialField,
    ], data)['specialHours'];
    data['seasonalAvailability'] = prepareAdminData(const [
      _periodsField,
    ], Map<String, dynamic>.from(data['seasonalAvailability'] as Map));
  }

  Map<String, dynamic> snapshot() {
    initialize();
    if (data['openingHoursStatus'] == 'scheduled') {
      for (final day in spotWeekdays.keys) {
        if (weeklyOpen[day]! && (weekly[day] as List).isEmpty) {
          throw FormatException('${spotWeekdays[day]}の時間帯を追加するか休業にしてください。');
        }
      }
    }
    final result = readAdminFormData(const [_specialField], data);
    result['openingHours'] =
        data['openingHoursStatus'] == 'scheduled' ||
            data['openingHours'] != null
        ? readAdminFormData([
            for (final day in spotWeekdays.keys) _dayField(day),
          ], weekly)
        : null;
    result['seasonalAvailability'] = readAdminFormData(const [
      _periodsField,
    ], data['seasonalAvailability'] as Map<String, dynamic>);
    return result;
  }
}

const _specialField = AdminField(
  'specialHours',
  '特別営業日・臨時休業',
  type: AdminInput.rows,
  children: _specialFields,
);
const _periodsField = AdminField(
  'periods',
  '営業期間',
  type: AdminInput.rows,
  children: _periodFields,
);
AdminField _dayField(String day) => AdminField(
  day,
  spotWeekdays[day]!,
  type: AdminInput.rows,
  children: _hoursFields,
);

class SpotVisitInfoForm extends StatefulWidget {
  final SpotVisitDraft draft;
  final bool enabled;
  const SpotVisitInfoForm({
    super.key,
    required this.draft,
    this.enabled = true,
  });
  @override
  State<SpotVisitInfoForm> createState() => _SpotVisitInfoFormState();
}

class _SpotVisitInfoFormState extends State<SpotVisitInfoForm> {
  Map<String, dynamic> get data => widget.draft.data;
  @override
  void initState() {
    super.initState();
    widget.draft.initialize();
  }

  Widget choice(
    String key,
    String label,
    Map<String, String> options, {
    Map<String, dynamic>? target,
  }) {
    final map = target ?? data;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DropdownButtonFormField<String>(
        key: ValueKey('visit-$key'),
        initialValue: map[key] as String,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final entry in options.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: widget.enabled
            ? (value) => setState(() => map[key] = value)
            : null,
      ),
    );
  }

  Widget chips(String key, Map<String, String> options) {
    final selected = data[key] as List;
    return Wrap(
      spacing: 8,
      children: [
        for (final entry in {
          ...options,
          for (final value in selected)
            value as String: options[value] ?? value,
        }.entries)
          FilterChip(
            label: Text(entry.value),
            selected: selected.contains(entry.key),
            onSelected: widget.enabled
                ? (on) => setState(() {
                    on ? selected.add(entry.key) : selected.remove(entry.key);
                  })
                : null,
          ),
      ],
    );
  }

  Widget fields(
    List<AdminField> fields,
    Map<String, dynamic> target,
    String prefix,
  ) => AdminFieldsForm(
    fields: fields,
    data: target,
    enabled: widget.enabled,
    prefix: prefix,
  );
  Widget section(String title, List<Widget> children) => ExpansionTile(
    title: Text(title),
    maintainState: true,
    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final seasonal = data['seasonalAvailability'] as Map<String, dynamic>;
    final fee = data['admissionFee'] as Map<String, dynamic>;
    return Column(
      children: [
        section('営業時間・営業期間', [
          choice('openingHoursStatus', '営業時間の登録状態', openingStatusOptions),
          const Text('日本時間（Asia/Tokyo）。深夜の日付またぎは対象外。終了のみ24:00を指定できます。'),
          if (data['openingHoursStatus'] == 'scheduled') ...[
            const Text('曜日ごとに営業・休業を設定し、複数の時間帯を追加できます。'),
            for (final day in spotWeekdays.keys)
              Builder(
                builder: (context) {
                  final weekly = widget.draft.weekly;
                  final isOpen = widget.draft.weeklyOpen[day]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        title: Text(
                          '${spotWeekdays[day]}：${isOpen ? '営業' : '休業'}',
                        ),
                        value: isOpen,
                        onChanged: widget.enabled
                            ? (on) => setState(() {
                                widget.draft.weeklyOpen[day] = on;
                                weekly[day] = on
                                    ? [
                                        prepareAdminData(_hoursFields, {
                                          'open': '09:00',
                                          'close': '17:00',
                                        }),
                                      ]
                                    : <dynamic>[];
                              })
                            : null,
                      ),
                      if (isOpen) fields([_dayField(day)], weekly, 'weekly-'),
                    ],
                  );
                },
              ),
          ],
          fields(const [_specialField], data, 'visit-'),
          const Text('特別営業日が曜日設定より優先します。休業日は時間帯を空にしてください。祝日は自動判定しません。'),
          choice('status', '季節営業', seasonalStatusOptions, target: seasonal),
          if (seasonal['status'] == 'seasonal') ...[
            const Text('毎年の営業期間。12月〜3月など年をまたぐ期間も登録できます。'),
            fields(const [_periodsField], seasonal, 'seasonal-'),
          ],
          const SizedBox(height: 16),
          const Text('おすすめの季節（営業期間とは別）'),
          chips('recommendedSeasons', recommendedSeasonOptions),
        ]),
        section('施設情報', [
          choice('environmentType', '屋内・屋外', environmentOptions),
          choice('status', '料金区分', feeStatusOptions, target: fee),
          fields(
            const [
              AdminField(
                'adultYen',
                '大人料金（円・空欄は不明）',
                type: AdminInput.integer,
                min: 0,
              ),
              AdminField(
                'childYen',
                '子供料金（円・空欄は不明）',
                type: AdminInput.integer,
                min: 0,
              ),
              AdminField('note', '料金の補足', multiline: true),
            ],
            fee,
            'fee-',
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: DropdownButtonFormField<String>(
              initialValue:
                  data['reservationRequired']?.toString() ?? 'unknown',
              decoration: const InputDecoration(labelText: '予約の必要性'),
              items: const [
                DropdownMenuItem(value: 'unknown', child: Text('不明')),
                DropdownMenuItem(value: 'true', child: Text('予約必須')),
                DropdownMenuItem(value: 'false', child: Text('予約不要')),
              ],
              onChanged: widget.enabled
                  ? (value) => setState(
                      () => data['reservationRequired'] = value == 'unknown'
                          ? null
                          : value == 'true',
                    )
                  : null,
            ),
          ),
          fields(
            const [
              AdminField('officialUrl', '公式サイト（HTTPS）', type: AdminInput.url),
            ],
            data,
            'visit-',
          ),
        ]),
        section('体験情報', [
          chips('experienceTags', {
            for (final tag in experienceTagOptions) tag: tag,
          }),
        ]),
      ],
    );
  }
}
