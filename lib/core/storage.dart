import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class Vault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureVault implements Vault {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class StateStore {
  StateStore(this.vault);
  final Vault vault;
  // One encrypted record replaces the old state atomically at the OS storage layer.
  Future<Map<String, dynamic>> load() async {
    final raw = await vault.read('foxway.state.v1');
    if (raw == null) return {'schema': 1};
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['schema'] != 1) {
      throw const FormatException('Неподдерживаемая версия хранилища');
    }
    return j;
  }

  Future<void> save(Map<String, dynamic> state) =>
      vault.write('foxway.state.v1', jsonEncode({'schema': 1, ...state}));
}
