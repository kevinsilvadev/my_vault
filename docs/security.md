# MyVault — Modelo de segurança

> **Status: protótipo.** Este documento descreve o desenho implementado. Ele
> não é uma certificação. **Não armazene credenciais reais** até que o modelo
> de ameaças seja revisado, os testes estejam passando nos dispositivos-alvo e
> a criptografia/gestão de chaves tenha passado por revisão especializada
> (fase 7 da especificação).

## 1. Princípio central

Toda criptografia acontece no cliente. O servidor recebe e armazena apenas
ciphertext e metadados de sincronização; ele **não recebe** a senha mestre, a
chave derivada nem a chave do cofre.

## 2. Hierarquia de chaves

```
senha mestre ──Argon2id(salt, m, t, p)──► KEK (256 bits, só em memória)
                                             │
                                             ▼ AES-256-GCM (AAD = versão + parâmetros + salt)
chave do cofre (256 bits aleatórios) ◄── envelope (pode ir ao servidor)
     │
     ▼ AES-256-GCM, nonce aleatório de 96 bits, AAD = "myvault/item/v1/<id>"
registros (JSON do item) ──► ciphertext||tag + nonce
```

| Elemento              | Onde fica                                    |
| --------------------- | -------------------------------------------- |
| Senha mestre          | Nunca persistida; zerada após a derivação (melhor esforço) |
| KEK                   | Apenas em memória, destruída logo após uso   |
| Chave do cofre        | Em memória somente enquanto desbloqueado; zerada ao bloquear |
| Envelope              | SQLite local e servidor (`key_envelopes`)    |
| Registros             | SQLite local e servidor (`vault_items`), sempre cifrados |
| Impressão da chave    | SQLite local (HMAC-SHA256 da chave do cofre com rótulo fixo) |

Implementação: `packages/vault_core/lib/src/crypto` e `.../vault`.

### Formato do envelope (`formatVersion = 1`)

```json
{
  "formatVersion": 1,
  "kdf": { "algorithm": "argon2id", "memoryKiB": 65536, "iterations": 3, "parallelism": 4, "salt": "<base64 16 bytes>" },
  "wrappedKey": { "nonce": "<base64 12 bytes>", "ciphertext": "<base64 32+16 bytes>" },
  "createdAt": "<ISO-8601>"
}
```

Os dados associados (AAD) do AES-GCM incluem versão, algoritmo, parâmetros e
salt. Adulterar qualquer um deles invalida a tag.

### Registros (`cryptoVersion = 1`)

- Conteúdo: JSON com `schemaVersion`, título, usuário, senha, URL,
  observações, categoria, favorito e datas. **Categoria e favorito também são
  cifrados** — o servidor não os vê.
- AAD vinculada ao `id` do item: um ciphertext não pode ser movido para outro
  registro.
- Após decifrar, o `id` interno é conferido com o `id` do registro.

## 3. Parâmetros do Argon2id

| Conjunto           | m        | t  | p | Uso |
| ------------------ | -------- | -- | - | --- |
| `minimum` (piso)   | 19 MiB   | 2  | 1 | Recomendação mínima OWASP. Envelopes abaixo disso são recusados (cliente e servidor). |
| `recommended`      | 64 MiB   | 3  | 4 | Padrão para novos cofres. |
| `maximum` (teto)   | 1 GiB    | 20 | 16 | Evita negação de serviço com envelope adulterado. |

**Pendente (decisão da especificação):** calibrar `recommended` por benchmark
nos dispositivos-alvo com `dart run bin/kdf_benchmark.dart` (Windows) e um
teste equivalente no Android. Meta: 0,5–1 s no aparelho mais lento.

**Política de atualização:** como os parâmetros ficam no envelope, um cofre
pode ser re-envelopado com parâmetros mais fortes ao trocar a senha mestre
(re-cifrar apenas a chave do cofre, não os registros). A troca de senha mestre
ainda não está implementada.

## 4. Biblioteca criptográfica

[`package:cryptography`](https://pub.dev/packages/cryptography) (Dart puro):
Argon2id, AES-GCM e HMAC-SHA256, com o mesmo comportamento em Android e
Windows. Nenhum algoritmo próprio foi criado. Pontos a validar na revisão:

- Desempenho do Argon2id em Dart puro no Android (executado em isolate para
  não travar a interface). Se for lento demais, avaliar uma implementação nativa
  via FFI (ex.: libsodium) mantendo o mesmo formato.
- Versão travada no `pubspec.lock` e acompanhamento de avisos de segurança.

## 5. Nonces

- Cada cifragem gera um nonce novo de 96 bits a partir do CSPRNG do sistema.
  A API do `AesGcmCipher` **não aceita nonce externo**, impedindo reutilização
  acidental.
- Limite seguro com nonces aleatórios: ~2³² cifragens por chave — ordens de
  grandeza acima do uso de um cofre pessoal. Teste: 500 cifragens seguidas sem
  repetição (`crypto_test.dart`).

## 6. Desbloqueio, bloqueio e memória

- Senha errada → `InvalidMasterPasswordException`, lançada ao abrir o envelope,
  **antes** de ler qualquer registro: o erro é idêntico com ou sem itens.
- Registro adulterado → falha de tag; o item é ignorado e contado como ilegível,
  sem quebrar o cofre e sem exibir conteúdo parcial.
- Bloqueio manual, por inatividade (1–30 min, padrão 5) e ao ir para segundo
  plano no Android. Ao bloquear: a chave é zerada, a lista descriptografada é
  descartada e as telas abertas são fechadas.
- Área de transferência: limpa após 30 s se ainda contiver o valor copiado.
- **Limitação conhecida:** Dart tem coletor de lixo e strings imutáveis. Zerar
  buffers é melhor esforço; campos de texto e strings podem permanecer em
  memória até a coleta. Documentado para a revisão.

## 7. Detecção de substituição do envelope

Um servidor malicioso poderia trocar o envelope por outro, criado com a mesma
senha mas com uma chave que ele conhece, para ler itens criados depois. Defesa:

- Cada dispositivo guarda a impressão (HMAC) da chave do cofre na primeira
  abertura. Se o envelope mudar e abrir outra chave, o desbloqueio é recusado
  (`VaultKeyMismatchException`).
- No primeiro dispositivo novo de uma conta, a confiança é TOFU (trust on first
  use). Mitigação futura: exibir a impressão para conferência entre dispositivos.

## 8. Autenticação da conta (separada da senha mestre)

A conta autoriza a sincronização; ela **não desbloqueia** o cofre.

- **Senha da conta ≠ senha mestre.** Decisão: senhas independentes, para que o
  hash armazenado no servidor nunca sirva de oráculo para ataque offline contra
  a senha mestre (diferente de esquemas que derivam o hash de login da senha
  mestre). Custo: o usuário mantém duas senhas.
- Hash da senha da conta: scrypt (N=2¹⁷, r=8, p=1 — OWASP), com rehash
  automático se os parâmetros mudarem.
- Token de acesso JWT HS256 de 15 min; a cada requisição a sessão e o
  dispositivo são conferidos no banco (revogação imediata).
- Refresh token opaco de 256 bits, armazenado como SHA-256, **rotacionado a cada
  uso**. Reapresentar um token já consumido revoga a sessão inteira (detecção de
  roubo). No cliente, renovações concorrentes são agrupadas em uma só.
- Refresh token guardado no armazenamento seguro do SO
  (`flutter_secure_storage`: Android Keystore / Windows DPAPI).
- Login com e-mail inexistente executa um hash descartável: o tempo e a
  resposta são iguais aos de senha errada.
- Rate limiting: por IP nas rotas de autenticação e por conta nas falhas de login.
- `ALLOW_REGISTRATION=false` após criar a conta pessoal.
- Dispositivos: listagem, revogação (perdido/roubado) e logout.

## 9. API e infraestrutura

- HTTPS obrigatório em produção (`REQUIRE_HTTPS`, padrão em `NODE_ENV=production`),
  com `TRUST_PROXY` para TLS terminado no proxy reverso. O app recusa `http://`
  exceto para endereços locais de desenvolvimento.
- `helmet`, `Cache-Control: no-store`, CORS fechado por padrão, limite de corpo.
- Validação estrita (Zod `.strict()`): campos desconhecidos são recusados —
  o servidor não aceita, por engano, campos em claro como `title`.
- Autorização por usuário em toda operação; itens têm chave composta
  `(user_id, id)`, então adivinhar o `id` de outro usuário não dá acesso.
- Logs: apenas método, caminho, status e duração. Sem cabeçalhos, corpo, tokens
  ou conteúdo do cofre; `redact` como segunda barreira. Erros de validação não
  ecoam valores.
- Segredos (`JWT_SECRET`, senha do banco) apenas em `.env` fora do repositório.

## 10. Metadados visíveis ao servidor

E-mail da conta, nomes/plataformas dos dispositivos, quantidade de itens,
`id` (UUID aleatório), tamanho aproximado do ciphertext, versão, revisão,
flag de exclusão e datas de criação/alteração. **Não visíveis:** título,
usuário, senha, URL, observações, categoria, favorito.

## 11. Biometria (fase 6 — não implementada)

Plano: a biometria será uma conveniência local que libera uma cópia da chave do
cofre protegida pelo SO; **não substitui** a senha mestre.

- Android: chave AES no Android Keystore com `setUserAuthenticationRequired(true)`
  e `setInvalidatedByBiometricEnrollment(true)`, usada via `BiometricPrompt` com
  `CryptoObject` para cifrar a chave do cofre.
- Windows: Windows Hello (`KeyCredentialManager`) para derivar/abrir a chave.
- Fallback para senha mestre: após reinicialização do aparelho, mudança de
  biometria, revogação ou falhas repetidas.
- Ponto de integração previsto: `VaultService` ganha `unlockWithKey` e a
  `VaultSession` expõe uma exportação controlada da chave para o cofre do SO.

## 12. Riscos e decisões pendentes

- [ ] Threat modeling formal e revisão de segurança especializada.
- [ ] Calibração do Argon2id por benchmark e política de atualização.
- [ ] Troca de senha mestre (re-envelopar) e migração de `cryptoVersion`.
- [ ] Biometria (seção 11).
- [ ] `FLAG_SECURE` no Android (bloqueia capturas de tela) e desativar backup
      automático (`android:allowBackup="false"`) — exigem editar os arquivos
      gerados pelo `flutter create` (ver README).
- [ ] Backup/restauração cifrados e teste de restauração em dispositivo limpo.
- [ ] Limpeza periódica de `applied_changes` antigos e de refresh tokens
      consumidos/expirados.
- [ ] Recuperação: **perder a senha mestre torna o cofre irrecuperável.** Isso
      é intencional e é exibido ao criar o cofre.
- [ ] Hospedagem, domínio, TLS, backups do PostgreSQL e política de atualização.
- [ ] Normalização Unicode da senha mestre (NFC) entre plataformas — hoje a
      senha é usada como digitada (UTF-8).
