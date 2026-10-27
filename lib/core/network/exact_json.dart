import 'dart:convert';

/// A JSON number retained before any binary floating-point conversion.
final class ExactNumber {
  ExactNumber(String value) : lexeme = value.trim() {
    if (!_number.hasMatch(lexeme) || lexeme.length > 512) {
      throw const FormatException('Invalid decimal number.');
    }
    final parts = lexeme.toLowerCase().split('e');
    final exponent = parts.length == 2 ? int.parse(parts[1]) : 0;
    if (exponent.abs() > 1000) {
      throw const FormatException('Decimal exponent is too large.');
    }
    final mantissa = parts[0];
    final point = mantissa.indexOf('.');
    var scale = (point < 0 ? 0 : mantissa.length - point - 1) - exponent;
    var coefficient = BigInt.parse(mantissa.replaceAll('.', ''));
    if (scale < 0) {
      coefficient *= BigInt.from(10).pow(-scale);
      scale = 0;
    }
    while (scale > 0 && coefficient % BigInt.from(10) == BigInt.zero) {
      coefficient ~/= BigInt.from(10);
      scale--;
    }
    _coefficient = coefficient;
    _scale = coefficient == BigInt.zero ? 0 : scale;
  }

  static final _number = RegExp(
    r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$',
  );
  static final _decimalMax = BigInt.parse('79228162514264337593543950335');
  final String lexeme;
  late final BigInt _coefficient;
  late final int _scale;

  static ExactNumber? tryParse(String value) {
    try {
      return ExactNumber(value);
    } on FormatException {
      return null;
    }
  }

  int compareTo(ExactNumber other) {
    final scale = _scale > other._scale ? _scale : other._scale;
    return (_coefficient * BigInt.from(10).pow(scale - _scale)).compareTo(
      other._coefficient * BigInt.from(10).pow(scale - other._scale),
    );
  }

  bool get fitsDotNetDecimal =>
      _scale <= 28 && _coefficient.abs() <= _decimalMax;
  bool get isMoney =>
      fitsDotNetDecimal &&
      _scale <= 2 &&
      compareTo(ExactNumber('0')) >= 0 &&
      compareTo(ExactNumber('10000000000000000')) < 0;
  bool get isWeight =>
      fitsDotNetDecimal &&
      compareTo(ExactNumber('0')) > 0 &&
      compareTo(ExactNumber('30')) <= 0;
  bool get isInteger => _scale == 0;

  String get plain {
    final negative = _coefficient.isNegative ? '-' : '';
    final digits = _coefficient.abs().toString().padLeft(_scale + 1, '0');
    if (_scale == 0) return '$negative$digits';
    final point = digits.length - _scale;
    return '$negative${digits.substring(0, point)}.${digits.substring(point)}';
  }

  String get moneyDisplay {
    if (!isMoney) throw const FormatException('Unsupported monetary value.');
    final parts = plain.split('.');
    return '${parts[0]}.${parts.length == 1 ? '00' : parts[1].padRight(2, '0')}';
  }

  @override
  String toString() => plain;
}

/// Decodes numeric tokens as [ExactNumber], including nested objects/arrays.
Object? decodeExactJson(String source) => _ExactParser(source).parse();

String encodeExactJson(Object? value) {
  if (value is ExactNumber) return value.lexeme;
  if (value == null || value is String || value is bool || value is int) {
    return jsonEncode(value);
  }
  if (value is List) return '[${value.map(encodeExactJson).join(',')}]';
  if (value is Map<String, Object?>) {
    return '{${value.entries.map((entry) => '${jsonEncode(entry.key)}:${encodeExactJson(entry.value)}').join(',')}}';
  }
  throw const FormatException('Only exact JSON values may be encoded.');
}

final class _ExactParser {
  _ExactParser(this.source);
  final String source;
  int position = 0;

  Object? parse() {
    if (source.length > 262144) {
      throw const FormatException('JSON response is too large.');
    }
    final result = _value(0);
    _whitespace();
    if (position != source.length) _invalid();
    return result;
  }

  Never _invalid() => throw const FormatException('Invalid JSON response.');

  void _whitespace() {
    while (position < source.length &&
        const [9, 10, 13, 32].contains(source.codeUnitAt(position))) {
      position++;
    }
  }

  bool _take(String character) {
    _whitespace();
    if (position < source.length && source[position] == character) {
      position++;
      return true;
    }
    return false;
  }

  Object? _value(int depth) {
    if (depth > 64) _invalid();
    _whitespace();
    if (position >= source.length) _invalid();
    if (source[position] == '"') return _string();
    if (_take('{')) {
      final map = <String, Object?>{};
      if (_take('}')) return map;
      do {
        _whitespace();
        if (position >= source.length || source[position] != '"') _invalid();
        final key = _string();
        if (map.containsKey(key) || !_take(':')) _invalid();
        map[key] = _value(depth + 1);
        if (_take('}')) return map;
      } while (_take(','));
      _invalid();
    }
    if (_take('[')) {
      final list = <Object?>[];
      if (_take(']')) return list;
      do {
        list.add(_value(depth + 1));
        if (_take(']')) return list;
      } while (_take(','));
      _invalid();
    }
    for (final literal in const ['true', 'false', 'null']) {
      if (source.startsWith(literal, position)) {
        position += literal.length;
        return literal == 'null' ? null : literal == 'true';
      }
    }
    final match = RegExp(
      r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
    ).matchAsPrefix(source, position);
    if (match == null) _invalid();
    position = match.end;
    return ExactNumber(match.group(0)!);
  }

  String _string() {
    final start = position++;
    var escaped = false;
    while (position < source.length) {
      final character = source[position++];
      if (character.codeUnitAt(0) < 32) _invalid();
      if (!escaped && character == '"') {
        return jsonDecode(source.substring(start, position)) as String;
      }
      if (!escaped && character == r'\') {
        escaped = true;
      } else {
        escaped = false;
      }
    }
    _invalid();
  }
}
