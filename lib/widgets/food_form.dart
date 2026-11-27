import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';

import '../models/food_photo.dart';
import '../models/food_tracker.dart';
import '../services/food_service.dart';
import 'food_visuals.dart';

class FoodForm extends StatefulWidget {
  const FoodForm({
    super.key,
    required this.service,
    this.original,
    this.pickImage,
  });

  final FoodService service;
  final FoodTracker? original;
  final Future<XFile?> Function()? pickImage;

  @override
  State<FoodForm> createState() => _FoodFormState();
}

class _FoodFormState extends State<FoodForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _person;
  late final TextEditingController _date;
  late String _meal;
  FoodPhoto? _photo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final original = widget.original?.input;
    _name = TextEditingController(text: original?.name);
    final price = original?.price;
    final twoPlaces = price?.toStringAsFixed(2);
    _price = TextEditingController(
      text: double.tryParse(twoPlaces ?? '') == price
          ? twoPlaces
          : price.toString(),
    );
    _person = TextEditingController(text: original?.person.toString());
    _date = TextEditingController(text: original?.date);
    _meal = original?.meal ?? FoodInput.meals.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _person.dispose();
    _date.dispose();
    super.dispose();
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickImage() async {
    setState(() => _busy = true);
    try {
      final selected =
          await (widget.pickImage?.call() ??
              ImagePicker().pickImage(
                source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
                maxWidth: kIsWeb ? null : 1600,
                imageQuality: kIsWeb ? null : 85,
              ));
      if (selected == null || !mounted) return;
      if (await selected.length() > FoodPhoto.maxBytes) {
        throw const FormatException('ขนาดรูปต้องไม่เกิน 5 MiB');
      }
      final photo = await FoodPhoto.decode(await selected.readAsBytes());
      if (mounted) setState(() => _photo = photo);
    } on FormatException catch (error) {
      if (mounted) _notify(error.message);
    } on Exception {
      if (mounted) _notify('เปิดกล้องหรืออ่านไฟล์ไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: FoodInput.parseDate(_date.text) ?? DateTime.now(),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: 'เลือกวันที่',
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
    );
    if (chosen == null || !mounted) return;
    _date.text = FoodInput.formatDate(chosen);
  }

  void _clear() {
    FocusScope.of(context).unfocus();
    _form.currentState?.reset();
    _name.clear();
    _price.clear();
    _person.clear();
    _date.clear();
    setState(() {
      _meal = FoodInput.meals.first;
      _photo = null;
    });
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final input = FoodInput(
      name: _name.text,
      meal: _meal,
      price: FoodInput.parsePrice(_price.text)!,
      person: FoodInput.parsePerson(_person.text)!,
      date: _date.text,
    );
    final original = widget.original;
    await _submit(
      () => original == null
          ? widget.service.addFood(input, _photo)
          : widget.service.updateFood(original, input, _photo),
      original == null ? 'บันทึกแล้ว' : 'บันทึกการแก้ไขแล้ว',
    );
  }

  Future<void> _delete() async {
    final original = widget.original;
    if (_busy || original == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบรายการอาหาร?'),
        content: Text(original.input.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบข้อมูล', style: TextStyle(color: foodRed)),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _submit(() => widget.service.deleteFood(original), 'ลบรายการแล้ว');
  }

  Future<void> _submit(
    Future<FoodChange> Function() action,
    String success,
  ) async {
    setState(() => _busy = true);
    String? notice;
    try {
      final change = await action();
      final issue = change.cleanupIssue;
      notice = issue == null ? success : '$success • ${issue.notice}';
    } on FoodActionException catch (error) {
      if (!mounted) return;
      if (error.refresh) {
        notice = error.message;
      } else {
        _notify(error.message);
      }
    } on FormatException catch (error) {
      if (mounted) _notify(error.message);
    } on Exception {
      if (mounted) _notify('ทำรายการไม่สำเร็จ กรุณาตรวจการเชื่อมต่อ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && notice != null) Navigator.pop(context, notice);
  }

  Widget _field(
    String label,
    String hint,
    TextEditingController controller,
    FormFieldValidator<String> validator, {
    TextInputType? keyboard,
    bool dateField = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        TextFormField(
          controller: controller,
          enabled: !_busy,
          keyboardType: keyboard,
          validator: validator,
          readOnly: dateField,
          onTap: dateField ? _pickDate : null,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 14,
            ),
            suffixIcon: dateField
                ? const Icon(Icons.calendar_today_outlined)
                : null,
          ),
        ),
      ],
    ),
  );

  Widget _mealField() => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('กินมื้อไหน', style: TextStyle(fontSize: 16)),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 7.0;
            final scaled = MediaQuery.textScalerOf(context).scale(14);
            final width = constraints.maxWidth >= 240 && scaled <= 17
                ? (constraints.maxWidth - 3 * gap) / FoodInput.meals.length
                : null;
            return Wrap(
              spacing: gap,
              children: [
                for (final meal in FoodInput.meals)
                  SizedBox(
                    width: width,
                    child: ChoiceChip(
                      label: SizedBox(
                        width: width == null ? null : width - 14,
                        child: Text(meal, textAlign: TextAlign.center),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 3),
                      labelStyle: const TextStyle(color: Colors.white),
                      selected: _meal == meal,
                      showCheckmark: false,
                      selectedColor: foodGreen,
                      backgroundColor: foodGrey,
                      side: BorderSide.none,
                      shape: const StadiumBorder(),
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _meal = meal),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _button(String text, Color color, VoidCallback action) => SizedBox(
    width: double.infinity,
    height: 48,
    child: ElevatedButton(
      onPressed: _busy ? null : action,
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      child: Text(text),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final original = widget.original;
    final photo = _photo;
    const camera = Icon(Icons.camera_alt_outlined, color: foodGrey, size: 86);
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 530),
            child: Form(
              key: _form,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 25, 26, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Tooltip(
                        message: kIsWeb ? 'เลือกรูปอาหาร' : 'ถ่ายรูปอาหาร',
                        child: InkWell(
                          onTap: _busy ? null : _pickImage,
                          child: SizedBox.square(
                            dimension: 130,
                            child: photo != null
                                ? Image.memory(photo.bytes, fit: BoxFit.cover)
                                : FoodNetworkPhoto(
                                    url: widget.service.displayImage(
                                      original?.imageUrl,
                                    ),
                                    size: 130,
                                    fallback: camera,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _field(
                      'กินอะไร',
                      'เช่น KFC, Pizza',
                      _name,
                      (text) => text == null || text.trim().isEmpty
                          ? 'กรุณากรอกชื่ออาหาร'
                          : null,
                    ),
                    _mealField(),
                    _field(
                      'กินไปเท่าไหร่',
                      'เช่น 299.50',
                      _price,
                      (text) => FoodInput.parsePrice(text ?? '') == null
                          ? 'กรุณากรอกราคาตั้งแต่ 0 บาท'
                          : null,
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    _field(
                      'กินกันกี่คน',
                      'เช่น 3',
                      _person,
                      (text) => FoodInput.parsePerson(text ?? '') == null
                          ? 'กรุณากรอกจำนวนเต็ม 1–2,147,483,647'
                          : null,
                      keyboard: TextInputType.number,
                    ),
                    _field(
                      'กินไปวันไหน',
                      'เช่น 2020-01-31',
                      _date,
                      (text) => FoodInput.parseDate(text ?? '') == null
                          ? 'กรุณาเลือกวันที่'
                          : null,
                      dateField: true,
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    _button(
                      original == null ? 'บันทึก' : 'บันทึกแก้ไข',
                      foodGreen,
                      _save,
                    ),
                    const SizedBox(height: 8),
                    _button(
                      original == null ? 'ยกเลิก' : 'ลบข้อมูล',
                      foodRed,
                      original == null ? _clear : _delete,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
