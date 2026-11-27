# MyVault — Arquitetura

## Visão geral

```
┌───────────────────────── Dispositivo (Android / Windows) ─────────────────────────┐
│  apps/mobile (Flutter)                                                            │
│   UI ─► VaultController ─► VaultService ───► LocalVaultStore (SQLite: ciphertext) │
│          AccountController ─► SyncEngine ─┘        ▲                              │
│                    │            │ RemoteSyncApi     │                              │
│                    ▼            ▼                   │                              │
│               MyVaultApi (HTTP + renovação de token)│   packages/vault_core       │
└────────────────────┼────────────────────────────────┼─────────────────────────────┘
                     │ HTTPS (somente ciphertext)
                     ▼
┌──────────────── server (Node.js + TypeScript + Express) ───────────────┐
│  auth/  (contas, sessões, dispositivos)   vault/ (envelope)  sync/     │
│  Services ─► Ports (interfaces) ─► infra/prisma ─► PostgreSQL          │
└────────────────────────────────────────────────────────────────────────┘
```

## Pacotes

| Caminho | Responsabilidade |
| --- | --- |
| `packages/vault_core` | Dart puro. Criptografia (Argon2id, AES-256-GCM, envelope), modelos, regras do cofre (`VaultService`), gerador de senhas, busca e motor de sincronização (`SyncEngine`). Não depende de Flutter, banco ou HTTP: usa as portas `LocalVaultStore` e `RemoteSyncApi`. |
| `apps/mobile` | Flutter (Android + Windows). Interface, SQLite (`SqliteVaultStore`), cliente HTTP (`MyVaultApi`), sessão segura (`AccountSessionStore`), bloqueio automático. |
| `server` | API Express. Módulos `auth`, `vault`, `sync`, cada um com `*.routes.ts` (HTTP + validação Zod), `*.service.ts` (regras) e `*.ports.ts` (interfaces de persistência). `infra/prisma` implementa as portas; os testes usam implementações em memória. |
| `infrastructure` | Docker Compose (PostgreSQL e, opcionalmente, a API). |

Uma única base Flutter atende Android e Windows (`apps/mobile`), como a
especificação sugere, evitando duplicação.

## Decisões

- **Portas e adaptadores.** As regras (`VaultService`, `SyncEngine`,
  `AuthService`, `SyncService`) dependem de interfaces. Isso permite testar
  toda a lógica sem banco, rede ou Flutter e trocar a persistência sem tocar
  nas regras.
- **Sem geração de código** no app (nada de `build_runner`): estado com
  `ChangeNotifier` e injeção via `InheritedWidget` (`AppScope`). Menos
  dependências e menos superfície de ataque.
- **Express 5** trata erros de handlers assíncronos nativamente; um único
  middleware de erro converte `AppError` em respostas `{ error: { code, message } }`.

## Sincronização

### Modelo de dados remoto (`vault_items`)

| Campo | Descrição |
| --- | --- |
| `(user_id, id)` | Chave composta; `id` é UUID gerado no cliente |
| `encrypted_data`, `nonce` | Ciphertext‖tag e nonce em base64; nulos em tombstones |
| `crypto_version` | Versão do formato criptográfico (`1`) |
| `version` | Concorrência otimista por registro |
| `revision` | Revisão monotônica do usuário (cursor de sincronização) |
| `deleted` | Tombstone de exclusão |

`applied_changes` guarda `(user_id, change_id) → resultado` para idempotência.

### Protocolo

1. **Fila local:** todo registro com `pending_change_id` está pendente. O
   conteúdo enviado é o estado atual do registro; `server_version` é a
   `baseVersion`. Cada nova edição gera um novo `changeId`.
2. **Push** (`POST /sync/push`, até 100 alterações): para cada uma, em transação
   com `SELECT … FOR UPDATE` na linha do usuário:
   - `changeId` já aplicado → devolve o mesmo resultado (idempotência);
   - `baseVersion` ≠ versão atual → `conflict` com a versão do servidor;
   - senão aplica, incrementa `version` e atribui nova `revision`.
3. **Pull** (`GET /sync/pull?since=<cursor>`): registros com `revision > since`
   em ordem, paginados, incluindo tombstones.
4. **Conflito no cliente:** a versão local vai para a tabela `conflicts`, o
   registro passa a refletir o servidor e o usuário escolhe: manter a local,
   manter a remota ou manter ambas (a local vira item novo). Nada é descartado
   sem confirmação.
5. **Edição durante o envio:** se o item mudou enquanto o push estava em voo,
   a nova edição continua pendente com base na versão recém-aceita.
6. **Servidor restaurado de backup:** se o cursor local for maior que
   `latestRevision`, o cliente ressincroniza do zero e reenfileira itens cuja
   versão local é mais nova que a do servidor.

Limitação conhecida: itens que o servidor perdeu por completo numa restauração
(não aparecem no pull) não são reenviados automaticamente.

### Vinculação de conta

O cofre local guarda o `userId` da conta à qual foi vinculado. Entrar em outra
conta, ou numa conta cujo envelope difere do local, é recusado — impede
misturar cofres.

## Esquema local (SQLite)

`meta(key, value)`, `records(...)` (espelha `vault_items` + campos de
pendência) e `conflicts(...)`. Migrações incrementais em
`apps/mobile/lib/data/local_database.dart`.
