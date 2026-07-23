import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/profile_controller.dart';
import '../../widgets/ui_bits.dart';

/// Bottom sheet for importing a subscription URL or pasting raw node links.
class ImportSheet extends ConsumerStatefulWidget {
  const ImportSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => const ImportSheet(),
      );

  @override
  ConsumerState<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<ImportSheet> {
  final _content = TextEditingController();
  final _name = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _content.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _content.text = data!.text!;
  }

  Future<void> _submit() async {
    final text = _content.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    await ref.read(profileProvider.notifier).import(text, name: _name.text.trim());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.slateHi,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Добавить подписку или узлы', style: AppType.display(20)),
          const SizedBox(height: 6),
          Text(
            'Вставьте ссылку на подписку (http…) либо строки vless:// vmess:// trojan:// ss:// hy2:// tuic://',
            style: AppType.ui(13, color: AppColors.mist),
          ),
          const SizedBox(height: 18),
          _field(_name, 'Название (необязательно)', maxLines: 1),
          const SizedBox(height: 12),
          _field(_content, 'Ссылка или узлы', maxLines: 4),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: const Text('Вставить из буфера'),
              style: TextButton.styleFrom(foregroundColor: AppColors.auroraTeal),
            ),
          ),
          const SizedBox(height: 8),
          AuroraButton(
            label: _submitting ? 'Загрузка…' : 'Добавить',
            icon: Icons.add_rounded,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      style: AppType.ui(14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppType.ui(14, color: AppColors.mistDim),
        filled: true,
        fillColor: AppColors.voidBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.auroraTeal, width: 1.4),
        ),
      ),
    );
  }
}
