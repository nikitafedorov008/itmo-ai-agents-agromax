import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const forest = Color(0xff103f32);
const ivory = Color(0xfff7f8f1);
const celery = Color(0xffc3e66b);
bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;

Future<T?> adaptiveDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => isIOS
    ? showCupertinoDialog<T>(context: context, builder: builder)
    : showDialog<T>(context: context, builder: builder);

class NativeAlert extends StatelessWidget {
  const NativeAlert({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
  });
  final Widget? title, content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => isIOS
      ? CupertinoAlertDialog(title: title, content: content, actions: actions)
      : AlertDialog(title: title, content: content, actions: actions);
}

class NativeInput extends StatefulWidget {
  const NativeInput({
    super.key,
    this.controller,
    this.initialValue,
    this.decoration,
    this.onChanged,
    this.maxLines = 1,
    this.obscureText = false,
    this.keyboardType,
  });
  final TextEditingController? controller;
  final String? initialValue;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final int? maxLines;
  final bool obscureText;
  final TextInputType? keyboardType;
  @override
  State<NativeInput> createState() => _NativeInputState();
}

class _NativeInputState extends State<NativeInput> {
  late final local = TextEditingController(text: widget.initialValue);
  @override
  void didUpdateWidget(covariant NativeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null &&
        oldWidget.initialValue != widget.initialValue &&
        local.text != (widget.initialValue ?? '')) {
      local.text = widget.initialValue ?? '';
    }
  }

  @override
  void dispose() {
    local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? local;
    if (!isIOS) {
      return TextField(
        controller: controller,
        decoration: widget.decoration,
        onChanged: widget.onChanged,
        maxLines: widget.maxLines,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.decoration?.labelText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.decoration!.labelText!,
              style: const TextStyle(fontSize: 14, color: forest),
            ),
          ),
        CupertinoTextField(
          controller: controller,
          placeholder: widget.decoration?.labelText,
          onChanged: widget.onChanged,
          maxLines: widget.maxLines,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          padding: const EdgeInsets.all(14),
          style: const TextStyle(fontSize: 16, color: Color(0xff172b23)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xffd8dfd1)),
          ),
        ),
      ],
    );
  }
}

class NativeButton extends StatelessWidget {
  const NativeButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.filled = false,
    this.outlined = false,
  }) : icon = null,
       label = null;
  const NativeButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.filled = false,
    this.outlined = false,
  }) : child = null;
  final VoidCallback? onPressed;
  final Widget? child;
  final Widget? icon, label;
  final bool filled, outlined;
  @override
  Widget build(BuildContext context) {
    final content =
        child ??
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon!,
            const SizedBox(width: 8),
            Flexible(child: label!),
          ],
        );
    if (isIOS) {
      final button = CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: filled ? forest : null,
        borderRadius: BorderRadius.circular(20),
        onPressed: onPressed,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: filled ? Colors.white : forest,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          child: content,
        ),
      );
      return outlined
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xffeef2e7),
                border: Border.all(color: const Color(0xffa6b9a4)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: button,
            )
          : button;
    }
    if (filled) return FilledButton(onPressed: onPressed, child: content);
    if (outlined) return OutlinedButton(onPressed: onPressed, child: content);
    return TextButton(onPressed: onPressed, child: content);
  }
}

class NativeSpinner extends StatelessWidget {
  const NativeSpinner({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: isIOS
        ? const CupertinoActivityIndicator()
        : const LinearProgressIndicator(),
  );
}
