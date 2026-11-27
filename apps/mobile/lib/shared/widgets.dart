import 'package:flutter/material.dart';

/// Campo de senha com botão de mostrar/ocultar. Desativa sugestões e
/// autocorreção do teclado para não vazar o conteúdo ao dicionário do SO.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.autofocus = false,
    this.onSubmitted,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscured,
      autofocus: widget.autofocus,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: TextInputType.visiblePassword,
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.suffix != null) widget.suffix!,
            IconButton(
              tooltip: _obscured ? 'Mostrar' : 'Ocultar',
              icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscured = !_obscured),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mostra uma mensagem curta na parte inferior da tela.
void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Diálogo de confirmação. Retorna `true` somente se o usuário confirmar.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
