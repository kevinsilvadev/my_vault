/// Lógica compartilhada do MyVault.
library;

export 'src/crypto/aes_gcm_cipher.dart' show AesGcmCipher, EncryptedPayload;
export 'src/crypto/kdf_params.dart';
export 'src/crypto/key_derivation.dart';
export 'src/crypto/vault_key_envelope.dart';
export 'src/exceptions.dart';
export 'src/generator/password_generator.dart';
export 'src/models/vault_item.dart';
export 'src/search/item_filter.dart';
export 'src/storage/local_vault_store.dart';
export 'src/storage/stored_record.dart';
export 'src/json_reader.dart';
export 'src/sync/sync_engine.dart';
export 'src/sync/sync_models.dart';
export 'src/vault/master_password_policy.dart';
export 'src/vault/vault_keyring.dart';
export 'src/vault/vault_service.dart';
export 'src/vault/vault_session.dart';
