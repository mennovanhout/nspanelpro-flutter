import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// The code sheet for the alarm card: masked dots, a 3×4 keypad (or a text
/// field when the entity's code_format is text), one confirm button. It
/// rises once (opacity + a small lift, the same budget as everything else)
/// and closes itself when `onSubmit` says the code was accepted; a refused
/// code clears the digits and says "Wrong code" for two seconds.
Future<void> showKeypadSheet(
  BuildContext context, {
  required String title,
  required Color accent,
  bool text = false,
  String hint = 'Enter the code',
  required Future<bool> Function(String code) onSubmit,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: Ns.ground.withValues(alpha: .72),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (_, a, _, child) {
      final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, _, _) => _Keypad(title: title, accent: accent, text: text, hint: hint, onSubmit: onSubmit),
  );
}

class _Keypad extends StatefulWidget {
  const _Keypad({
    required this.title,
    required this.accent,
    required this.text,
    required this.hint,
    required this.onSubmit,
  });

  final String title, hint;
  final Color accent;
  final bool text;
  final Future<bool> Function(String code) onSubmit;

  @override
  State<_Keypad> createState() => _KeypadState();
}

class _KeypadState extends State<_Keypad> {
  var _code = '';
  var _busy = false;
  var _wrong = false;
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _tap(String k) {
    HapticFeedback.lightImpact();
    setState(() {
      _wrong = false;
      if (k == 'C') {
        _code = '';
      } else if (k == '<') {
        if (_code.isNotEmpty) _code = _code.substring(0, _code.length - 1);
      } else if (_code.length < 12) {
        _code += k;
      }
    });
  }

  Future<void> _submit() async {
    final code = widget.text ? _field.text : _code;
    if (code.isEmpty || _busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    final ok = await widget.onSubmit(code);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _wrong = true;
      _code = '';
      _field.clear();
    });
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _wrong = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entered = widget.text ? _field.text : _code;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Ns.text, fontSize: 22, fontWeight: FontWeight.w700)),
                        Text(_wrong ? 'Wrong code' : widget.hint,
                            style: TextStyle(
                                color: _wrong ? Ns.danger : Ns.muted, fontSize: 15, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  _Key(label: '✕', size: 56, onTap: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.text)
                TextField(
                  controller: _field,
                  autofocus: true,
                  obscureText: true,
                  onChanged: (_) => setState(() => _wrong = false),
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(color: Ns.text, fontSize: 22, letterSpacing: 4),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: .08),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                )
              else ...[
                SizedBox(
                  height: 28,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < (_code.isEmpty ? 4 : _code.length); i++)
                        Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _code.length
                                ? (_wrong ? Ns.danger : widget.accent)
                                : Colors.white.withValues(alpha: .18),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Column(
                    children: [
                      for (final row in const [
                        ['1', '2', '3'],
                        ['4', '5', '6'],
                        ['7', '8', '9'],
                        ['C', '0', '<'],
                      ]) ...[
                        Expanded(
                          child: Row(
                            children: [
                              for (final k in row) ...[
                                if (k != row.first) const SizedBox(width: 10),
                                Expanded(
                                  child: _Key(
                                    label: k == '<' ? '⌫' : k,
                                    muted: k == 'C' || k == '<',
                                    onTap: () => _tap(k),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (row.first != '7' || true) const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              SizedBox(
                height: 58,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: Ns.ground,
                    disabledBackgroundColor: widget.accent.withValues(alpha: .35),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  onPressed: entered.isEmpty || _busy ? null : _submit,
                  child: Text(_busy ? '…' : widget.title),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap, this.muted = false, this.size});
  final String label;
  final VoidCallback onTap;
  final bool muted;
  final double? size;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: muted ? .06 : .10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label,
              style: TextStyle(
                  color: muted ? Ns.muted : Ns.text,
                  fontSize: size != null ? 24 : 26,
                  fontWeight: FontWeight.w600,
                  fontFeatures: Ns.tabular)),
        ),
      );
}
