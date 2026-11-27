# MyVault — API (v1)

Base: `/api/v1`. JSON em todas as rotas. Rotas autenticadas exigem
`Authorization: Bearer <accessToken>`.

Erros: `{ "error": { "code": "...", "message": "...", "details"?: [...] } }`.

## Autenticação

| Método | Rota | Corpo | Resposta |
| --- | --- | --- | --- |
| POST | `/auth/register` | `{ email, password, device: { name, platform } }` | `201` tokens |
| POST | `/auth/login` | `{ email, password, device: { name, platform, id? } }` | tokens |
| POST | `/auth/refresh` | `{ refreshToken }` | tokens (refresh rotacionado) |
| POST | `/auth/logout` | — | `204` |
| GET | `/devices` | — | `{ devices: [{ id, name, platform, createdAt, lastSeenAt, current }] }` |
| DELETE | `/devices/:deviceId` | — | `204` (revoga dispositivo e sessões) |

Tokens: `{ userId, deviceId, accessToken, accessTokenExpiresIn, refreshToken }`.
`platform`: `android` · `windows` · `other`. `password` é a senha **da conta**
(12–256 caracteres), nunca a senha mestre.

Códigos relevantes: `INVALID_CREDENTIALS` (401), `INVALID_REFRESH_TOKEN` (401),
`REGISTRATION_DISABLED` (403), `EMAIL_UNAVAILABLE` (409), `RATE_LIMITED` (429).

## Envelope da chave do cofre

| Método | Rota | Corpo | Resposta |
| --- | --- | --- | --- |
| GET | `/vault/key-envelope` | — | `{ envelope, version, updatedAt }` ou `404` |
| PUT | `/vault/key-envelope` | `{ envelope, baseVersion }` | `{ version }` ou `409 ENVELOPE_VERSION_CONFLICT` |

Formato do `envelope`: ver `docs/security.md`.

## Sincronização

### `POST /sync/push`

```json
{
  "changes": [
    { "changeId": "uuid", "itemId": "uuid", "operation": "upsert", "baseVersion": 0,
      "cryptoVersion": 1, "encryptedData": "base64", "nonce": "base64(12 bytes)" },
    { "changeId": "uuid", "itemId": "uuid", "operation": "delete", "baseVersion": 3 }
  ]
}
```

Resposta `{ results: [...] }`, um por alteração:

- `{ changeId, itemId, status: "applied", version, revision }`
- `{ changeId, itemId, status: "conflict", serverItem }`
- `{ changeId, itemId, status: "rejected", reason: "base_version_not_found" | "change_id_reused" }`

### `GET /sync/pull?since=0&limit=200`

```json
{
  "items": [{ "id", "encryptedData", "nonce", "cryptoVersion", "version", "revision", "deleted", "updatedAt" }],
  "cursor": 42,
  "hasMore": false,
  "latestRevision": 42
}
```

## Saúde

`GET /health` (processo) e `GET /health/ready` (banco).
