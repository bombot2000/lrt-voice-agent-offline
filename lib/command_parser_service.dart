import 'tariff_utils.dart';

enum CommandIntent { greeting, arithmetic, cargoTariff, destinationSearch, unknown }

enum ArithmeticOperator { add, subtract, multiply, divide }

class ArithmeticExpression {
  final num left;
  final num right;
  final ArithmeticOperator operator;

  const ArithmeticExpression(this.left, this.operator, this.right);

  num? calculate() {
    switch (operator) {
      case ArithmeticOperator.add:
        return left + right;
      case ArithmeticOperator.subtract:
        return left - right;
      case ArithmeticOperator.multiply:
        return left * right;
      case ArithmeticOperator.divide:
        return right == 0 ? null : left / right;
    }
  }

  String get operatorLabel {
    switch (operator) {
      case ArithmeticOperator.add:
        return 'ditambah';
      case ArithmeticOperator.subtract:
        return 'dikurangi';
      case ArithmeticOperator.multiply:
        return 'dikali';
      case ArithmeticOperator.divide:
        return 'dibagi';
    }
  }
}

class ParsedCommand {
  final String normalizedText;
  final CommandIntent intent;
  final ArithmeticExpression? arithmetic;

  const ParsedCommand({
    required this.normalizedText,
    required this.intent,
    this.arithmetic,
  });
}

/// Mesin aturan lokal tanpa jaringan dan tanpa LLM.
class CommandParserService {
  static const Set<String> _greetings = {
    'halo',
    'hai',
    'hello',
    'selamat pagi',
    'selamat siang',
    'selamat sore',
    'selamat malam',
    'bantuan',
  };

  static const Set<String> _cargoWords = {
    'ongkir',
    'ongkos',
    'cargo',
    'kargo',
    'paket',
    'kirim',
    'pengiriman',
    'barang',
    'kg',
    'kilo',
    'kilogram',
    'reg',
    'reguler',
    'sp1',
    'sp2',
    'sp3',
    'next',
    'tarif',
    'harga',
    'biaya',
  };

  static String normalize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s.,+*/×:-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static ParsedCommand parse(String input) {
    final normalized = normalize(input);
    final arithmetic = _parseArithmetic(normalized);
    if (arithmetic != null) {
      return ParsedCommand(
        normalizedText: normalized,
        intent: CommandIntent.arithmetic,
        arithmetic: arithmetic,
      );
    }

    final words = normalized.split(' ').where((w) => w.isNotEmpty).toSet();
    final hasCargoWord = words.any(_cargoWords.contains) ||
        RegExp(r'\d\s*(kg|kilo|kilogram)\b').hasMatch(normalized);
    if (hasCargoWord) {
      return ParsedCommand(
        normalizedText: normalized,
        intent: CommandIntent.cargoTariff,
      );
    }

    if (_greetings.contains(normalized) || normalized == 'bisa apa') {
      return ParsedCommand(
        normalizedText: normalized,
        intent: CommandIntent.greeting,
      );
    }

    return ParsedCommand(
      normalizedText: normalized,
      intent: destinationTokens(input).isEmpty
          ? CommandIntent.unknown
          : CommandIntent.destinationSearch,
    );
  }

  static ArithmeticExpression? _parseArithmetic(String text) {
    final phrase = RegExp(
      r'^(?:tolong\s+)?(jumlahkan|tambahkan|kurangi|kurangkan|kalikan|kali|bagikan|bagi)\s+(-?\d+(?:[.,]\d+)?)\s+(?:dengan|dan)\s+(-?\d+(?:[.,]\d+)?)$',
    ).firstMatch(text);

    if (phrase != null) {
      final left = _number(phrase.group(2)!);
      final right = _number(phrase.group(3)!);
      final operator = switch (phrase.group(1)!) {
        'jumlahkan' || 'tambahkan' => ArithmeticOperator.add,
        'kurangi' || 'kurangkan' => ArithmeticOperator.subtract,
        'kalikan' || 'kali' => ArithmeticOperator.multiply,
        'bagikan' || 'bagi' => ArithmeticOperator.divide,
        _ => null,
      };
      if (left != null && right != null && operator != null) {
        return ArithmeticExpression(left, operator, right);
      }
    }

    final pattern = RegExp(
      r'(?:berapa|hitung(?:kan)?|hasil(?:nya)?)?\s*(-?\d+(?:[.,]\d+)?)\s*(tambah|plus|\+|dikurangi|kurang|minus|dikali|kali|x|×|dibagi|bagi|:|/)\s*(-?\d+(?:[.,]\d+)?)',
    );
    final match = pattern.firstMatch(text);
    if (match == null) return null;

    final left = _number(match.group(1)!);
    final right = _number(match.group(3)!);
    if (left == null || right == null) return null;

    final operator = switch (match.group(2)!) {
      'tambah' || 'plus' || '+' => ArithmeticOperator.add,
      'dikurangi' || 'kurang' || 'minus' => ArithmeticOperator.subtract,
      'dikali' || 'kali' || 'x' || '×' => ArithmeticOperator.multiply,
      'dibagi' || 'bagi' || ':' || '/' => ArithmeticOperator.divide,
      _ => null,
    };

    return operator == null
        ? null
        : ArithmeticExpression(left, operator, right);
  }

  static num? _number(String raw) {
    final value = raw.replaceAll(',', '.');
    return value.contains('.') ? double.tryParse(value) : int.tryParse(value);
  }
}
