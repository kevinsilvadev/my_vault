# MyVault

Gerenciador de senhas pessoal para **Windows e Android**, com sincronização pela
internet e **criptografia ponta a ponta**: o servidor só vê ciphertext.

> ⚠️ **Protótipo.** Não armazene credenciais reais antes da revisão de
> segurança (fase 7). Veja [docs/security.md](docs/security.md).

## Estrutura

```
myvault/
├── apps/mobile/          # Flutter: Android e Windows
├── packages/vault_core/  # Dart puro: criptografia, regras do cofre, sincronização
├── server/               # API Node.js + TypeScript + Express + Prisma
│   ├── src/{auth,vault,sync,infra,shared}/
│   ├── prisma/schema.prisma
│   └── test/
├── infrastructure/       # Docker Compose (PostgreSQL)
└── docs/                 # architecture.md, security.md, api.md
```

## Estado das fases

| Fase | Situação |
| --- | --- |
| 1. Estrutura | ✅ Monorepo, configs, Docker Compose, CI, documentação |
| 2. Cofre local | ✅ Argon2id + AES-256-GCM, envelope, criação/desbloqueio, SQLite, testes |
| 3. CRUD | ✅ Cadastro, edição, exclusão, busca, categorias, favoritos, gerador |
| 4. Backend | ✅ Contas, sessões, refresh rotativo, dispositivos, autorização, testes de acesso indevido |
| 5. Sincronização | ✅ Fila offline, idempotência, conflitos preservados, tombstones, recuperação |
| 6. Biometria | ⏳ Planejada (desenho em `docs/security.md` §11) |
| 7. Revisão | ⏳ Pendente — ver lista em `docs/security.md` §12 |

## Pré-requisitos (Windows)

| Ferramenta | Versão |
| --- | --- |
| Flutter SDK (inclui Dart) | 3.24 ou mais recente (stable) |
| Android Studio + Android SDK | atual |
| Visual Studio 2022 com "Desenvolvimento para desktop com C++" | para o build Windows |
| Node.js | 22 LTS (≥ 22.12) |
| Docker Desktop | para o PostgreSQL local |
| Git | qualquer versão recente |

Registre aqui as versões exatas validadas (`flutter --version`, `node --version`).

## Primeiros passos

### 1. Banco de dados

```bash
cd infrastructure
cp .env.example .env   # defina POSTGRES_PASSWORD
docker compose up -d db
```

### 2. API

```bash
cd server
cp .env.example .env   # ajuste DATABASE_URL e gere JWT_SECRET
npm install            # gera o package-lock.json — versione-o
npm run prisma:migrate -- --name init   # cria e aplica a migração inicial (versione prisma/migrations)
npm test
npm run dev            # http://localhost:3000/health
```

Depois de criar a sua conta, defina `ALLOW_REGISTRATION=false`.

### 3. Núcleo compartilhado

```bash
cd packages/vault_core
dart pub get
dart test
dart run bin/kdf_benchmark.dart   # calibra o Argon2id nesta máquina
```

### 4. App Flutter

As pastas de plataforma (`android/`, `windows/`) são geradas pelo Flutter e
não estão no repositório ainda. Gere-as uma vez (os arquivos de `lib/` e
`test/` existentes são preservados):

```bash
cd apps/mobile
flutter create --platforms=android,windows --org com.myvault --project-name myvault .
flutter pub get
flutter test
flutter run -d windows
```

Ajustes obrigatórios após o `flutter create` (Android):

- `android/app/src/main/AndroidManifest.xml`: adicionar
  `<uses-permission android:name="android.permission.INTERNET"/>` e
  `android:allowBackup="false"` em `<application>`.
- `android/app/build.gradle`: `minSdk` ≥ 23 (exigido pelo `flutter_secure_storage`).
- Recomendado: `FLAG_SECURE` na `MainActivity` para bloquear capturas de tela.

No emulador Android, a API local fica em `http://10.0.2.2:3000`. Fora de
endereços locais o app exige HTTPS.

## Uso

1. **Criar cofre** no primeiro dispositivo (senha mestre — nunca sai do aparelho).
2. **Conta e sincronização → Criar conta**: informe o servidor, e-mail e uma
   senha **da conta** (diferente da senha mestre). O envelope cifrado do cofre
   é enviado ao servidor.
3. No segundo dispositivo: **Conectar a uma conta existente** → entre com a
   conta → desbloqueie com a mesma senha mestre.

## Qualidade

- `server`: `npm run typecheck`, `npm run lint`, `npm test`
- `packages/vault_core`: `dart analyze`, `dart test`
- `apps/mobile`: `flutter analyze`, `flutter test`
- CI em `.github/workflows/ci.yml` roda tudo isso.

## Documentação

- [Arquitetura e protocolo de sincronização](docs/architecture.md)
- [Modelo de segurança, decisões e pendências](docs/security.md)
- [Referência da API](docs/api.md)
