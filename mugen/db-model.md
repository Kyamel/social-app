# Modelo de Banco de Dados — Mugen & mugenx (ATProtocol-first)

> **Versão:** 1.8
> **Produtos:** Mugen (Indexador / Social Network) · mugenx (App de publicação para scan groups)
> **Protocolo base:** AT Protocol (ATProto)
>
> **Changelog v1.8:** refatoração de naming e shape das tabelas de refs externas em `mugen_catalog`:
> `work_provider_refs` → `work_external_refs`; `staff_person_provider_refs` → `staff_person_external_refs`; `tag_provider_refs` → `tag_external_refs`; `scan_group_external_ids` → `scan_group_external_refs` — todas padronizadas com mesmo shape e convenção de naming `*_external_refs`; `mugen_catalog.external_links` atualizada: `provider_name` renomeado para `platform_name` (evita ambiguidade com providers de ingest), campo `target_kind` adicionado para distinguir destino do link (series | volume | publisher_page | storefront | official_site); todas as referências cruzadas no documento atualizadas.
>
> **Changelog v1.7:** `identity.local_users.did` tornado nullable — conta local existe antes de DID ATProto; adicionado campo `atproto_link_state text NOT NULL DEFAULT 'unlinked'` com estados `unlinked | linked | pending_migration | disabled`; campos de auditoria editorial em `mugen_catalog.tags` (`created_by_did`, `approved_by_did`) migrados para `created_by_user_id uuid FK → identity.local_users.id` e `approved_by_user_id uuid`; `work_scan_claims.decided_by_did` migrado para `decided_by_user_id uuid FK → identity.local_users.id` (null para decisões automáticas); `staff_people.actor_did`, `chapter_scanlations.*` e `scan_group_staff.member_did` documentados explicitamente como nullable com comentário de semântica; índices adicionados em `atproto_link_state` e `did WHERE did IS NOT NULL`.
>
> **Changelog v1.6:** `scan_catalog.chapters` migrado de `chapter_number float` + `volume_number float` para `chapter_key text`, `sort_number numeric(10,3)`, `display_number text`, `volume text` — consistente com `canonical.chapters` e `mugen_catalog.chapters`; UNIQUE atualizado para `(series_id, chapter_key, lang)`; adicionado campo opcional `canonical_chapter_uri` para reconciliação futura com o canônico; índices atualizados.
>
> **Changelog v1.5:** adicionada `canonical.external_refs`; `canonical.works` recebe `release_year`, `demographic`, `content_rating`, `genres text[]`; removido `canonical.cover`; GIN index em `genres`.
>
> **Changelog v1.4:** introduzida arquitetura em três planos; adicionado schema `canonical.*`; `activity.*` reescrito com `subject_work_uri` apontando exclusivamente para `canonical.*`; lexicons migrados para `org.mugens.*`.
>
> **Changelog v1.3:** adicionado schema `activity`; removido `mugen_catalog.work_follows`; adicionado `local.reading_progress`.
>
> **Changelog v1.2:** adicionados `volumes`, `chapters`, `chapter_external_refs` com UNIQUEs parciais, `scan_groups`, `staff_person_provider_refs`; renomeados `canonical_*_id` para `matched_*_id`; corrigido `editorial_assets`.
>
> **Changelog v1.1:** corrigida semântica de storage local; endurecido constraint XOR em `comment_subjects`; separado claims em observados vs. editoriais.

---

## 1. Visão Geral e Princípios de Design

### 1.1 Os dois produtos

| | **Mugen** | **mugenx** |
|---|---|---|
| **Papel na rede** | AppView global + Social Network | Origem soberana de catálogo + Surface social local |
| **Catálogo** | Canônico reconciliado (multi-provider) | Privado da scan (autoritativo local) |
| **Busca** | Global, indexada, cross-source | Local, limitada ao conteúdo da scan |
| **Usuários** | DID-first, rede federada | DID-first, pode hospedar contas locais |
| **Features sociais** | Completo: grupos, NLP, realtime, feed | Simples: comentários, likes, follows |
| **Data providers** | AniList, MangaDex, mugenx instances | Nenhum (é o provider) |
| **Papel ATProto** | AppView / Relay downstream | PDS ou PDS-adjacent |

### 1.2 Princípio central de modelagem

Todo dado pertence a exatamente uma das três camadas:

```
┌─────────────────────────────────────────────────────────────┐
│  CAMADA 1 — FEDERADA (records ATProto)                      │
│  Fatos públicos, portáveis, endereçáveis por AT URI         │
│  Fonte de verdade: PDS do ator                              │
│  Ex: posts, comentários, likes, follows, series/chapter ref │
├─────────────────────────────────────────────────────────────┤
│  CAMADA 2 — PROJEÇÃO / APPVIEW (banco local)                │
│  Índices consultáveis derivados dos records                 │
│  Não é fonte primária, é visão materializada                │
│  Ex: feed, threads, contadores, search docs                 │
├─────────────────────────────────────────────────────────────┤
│  CAMADA 3 — LOCAL / PRIVADO / OPERACIONAL                   │
│  Estados privados, UX local, pipelines internos             │
│  Nunca sai para a federação                                 │
│  Ex: preferências, bookmarks, jobs, analytics, NLP          │
└─────────────────────────────────────────────────────────────┘
```

**Regra de ouro:**
> Se algo precisa ser **comentável, citável, referenciável ou interoperável entre apps**, ele nasce como record ATProto com AT URI estável. Todo o resto é local.

### 1.3 Arquitetura em três planos

A separação fundamental do sistema. Cada plano tem dono, ciclo de vida e garantia de portabilidade diferentes.

```
┌─────────────────────────────────────────────────────────────────────┐
│  PLANO 1 — IDENTIDADE CANÔNICA                                      │
│  Pertence à rede. Publicado por did:plc:mugens-catalog.             │
│  Pequeno, estável, federado. Sobrevive à queda de qualquer app.     │
│  Lexicons: org.mugens.canonical.*                                   │
│  Schema de projeção local: canonical.*                              │
├─────────────────────────────────────────────────────────────────────┤
│  PLANO 2 — VALOR EDITORIAL E CONTEÚDO OPERACIONAL                   │
│  Mugen: ingest, reconciliação, staff, tags, score → mugen_catalog.* │
│  mugenx: páginas, releases, upload pipeline  → scan_catalog.*       │
│  Não federado por padrão. Pertence ao app, não à rede.              │
├─────────────────────────────────────────────────────────────────────┤
│  PLANO 3 — ATIVIDADE DO USUÁRIO                                     │
│  Publicada no PDS do usuário. Aponta para Plano 1.                  │
│  Nunca aponta para IDs internos de mugen_catalog ou scan_catalog.   │
│  Sobrevive à queda do Mugen e à queda de qualquer instância scan.   │
│  Lexicons: org.mugens.activity.*                                    │
│  Schema de projeção local: activity.*                               │
└─────────────────────────────────────────────────────────────────────┘
```

**Regra crítica:** `activity.subject_canonical_uri` aponta sempre para `at://did:plc:mugens-catalog/org.mugens.canonical.work/rkey` ou `.../canonical.chapter/rkey` — nunca para ID interno do Mugen ou do mugenx. O AppView resolve esse URI para exibição local.

### 1.4 Estrutura de schemas

```
Compartilhado (Mugen + mugenx)
├── canonical         — projeção local dos records canônicos (Plano 1)
├── identity          — identidade federada via DID
├── repo              — repositórios, records e commits ATProto
├── blob              — blobs do protocolo
├── graph             — interações sociais federáveis (follow, like, repost)
├── content           — projeção consultável de posts/comentários
├── activity          — relação do usuário com o catálogo (Plano 3)
├── label             — labels protocolares e labelers
├── local             — estados privados, moderação humana, UX local
└── ops               — infra: idempotência, rate limit, firehose cursors

Somente Mugen
├── mugen_catalog     — valor editorial reconciliado (Plano 2, overlay sobre canonical)
├── mugen_index       — índices globais de busca e ranking
├── mugen_feed        — feed materializado, snapshots, grupos
├── mugen_ai          — embeddings, summaries, NLP
├── mugen_realtime    — mensagens, sessões de leitura síncronas
├── mugen_moderation  — workflow humano avançado de moderação
├── mugen_ops         — pipeline de publicação canônica + assets editoriais
└── provider_ingest   — ingestão de providers externos (AniList, MangaDex)

Somente mugenx
├── scan_catalog      — releases, páginas, séries da instância (Plano 2)
├── scan_storage      — assets locais de storage (páginas, covers brutas, thumbnails)
├── scan_ops          — pipeline de upload, jobs, sync
└── scan_moderation   — moderação local da instância
```

---

## 2. Schemas Compartilhados

### 2.1 `canonical` — Projeção local do catálogo canônico (Plano 1)

O schema `canonical` é a projeção AppView dos records publicados pelo ator de serviço `did:plc:mugens-catalog` via `org.mugens.canonical.*`. Cada app mantém sua própria cópia local para queries rápidas — a fonte de verdade é sempre o PDS do ator de serviço, acessível via firehose.

**Regra de ouro deste schema:** sem DIDs de usuário, sem staff, sem páginas, sem score, sem covers. Só identidade e referências externas. Tudo editorial fica em `mugen_catalog`. Tudo operacional fica em `scan_catalog`.

**Autoridade canônica:** um único DID publica `org.mugens.canonical.*` — `did:plc:mugens-catalog`. AppViews só confiam nessa autoridade. Outros atores podem propor works, mas não canonizar. No futuro, uma allowlist com múltiplos maintainers pode ser introduzida sem quebrar o contrato.

```sql
-- ---------------------------------------------------------------------------
-- WORKS CANÔNICOS
-- Projeção de org.mugens.canonical.work
-- Publicado exclusivamente por did:plc:mugens-catalog
--
-- genres: vocabulário controlado, não enforçado por constraint de banco
-- (evita migration a cada expansão do vocabulário).
-- Valores esperados:
--   action | adventure | comedy | drama | fantasy | horror | mystery |
--   romance | sci_fi | slice_of_life | sports | thriller
-- Subgêneros (dark_fantasy, isekai, mecha…) pertencem a mugen_catalog.tags,
-- não ao canônico.
-- ---------------------------------------------------------------------------

canonical.works
  at_uri              text        PK
                                  -- at://did:plc:mugens-catalog/org.mugens.canonical.work/rkey
  rkey                text        NOT NULL UNIQUE
                                  -- slug estável, ex: "berserk", "one-piece"
  work_kind           text        NOT NULL
                                  -- manga | manhwa | manhua | novel | webtoon | oneshot
  original_language   text        NOT NULL    -- ISO 639-1, ex: "ja", "ko", "zh"
  primary_title       text        NOT NULL    -- título principal no idioma original
  primary_title_lang  text        NOT NULL    -- idioma do primary_title
  status              text        NOT NULL
                                  -- ongoing | completed | hiatus | cancelled
  release_year        int                     -- ano de início de publicação; null se desconhecido
  published_from      date                    -- data exata de início; null se desconhecida
  published_to        date                    -- null se ainda em publicação
  demographic         text
                                  -- shounen | shoujo | seinen | josei | kodomomuke | null
  content_rating      text
                                  -- general | teen | mature | adult
  genres              text[]      NOT NULL    DEFAULT '{}'
                                  -- vocabulário controlado descrito acima; array para multi-género
  indexed_at          timestamptz NOT NULL
  updated_at          timestamptz NOT NULL

-- ---------------------------------------------------------------------------
-- ALIASES / TÍTULOS ALTERNATIVOS
-- Projeção de org.mugens.canonical.alias
-- Um record por título alternativo. Permite busca multilíngue no AppView.
-- ---------------------------------------------------------------------------

canonical.aliases
  at_uri              text        PK
  work_at_uri         text        NOT NULL    FK → canonical.works.at_uri
  title               text        NOT NULL
  lang                text                    -- ISO 639-1; null = idioma desconhecido
  alias_kind          text        NOT NULL
                                  -- official | romanization | abbreviation | fan
  is_primary          bool        NOT NULL    DEFAULT false
  indexed_at          timestamptz NOT NULL

-- ---------------------------------------------------------------------------
-- RELAÇÕES ENTRE WORKS
-- Projeção de org.mugens.canonical.relation
-- Direcionada: source → target com tipo de relação.
-- ---------------------------------------------------------------------------

canonical.relations
  at_uri              text        PK
  source_work_uri     text        NOT NULL    FK → canonical.works.at_uri
  target_work_uri     text        NOT NULL    FK → canonical.works.at_uri
  relation_kind       text        NOT NULL
                                  -- sequel | prequel | side_story | spin_off
                                  -- adaptation | alternative_version | contains
  indexed_at          timestamptz NOT NULL

-- ---------------------------------------------------------------------------
-- REFERÊNCIAS EXTERNAS
-- Projeção de org.mugens.canonical.external_ref
-- Um record por referência externa. source é vocabulário aberto.
-- Permite query eficiente "qual work tem este AniList ID?" sem scan de jsonb.
-- Exemplos de source: "anilist", "mangadex", "myanimelist", "kitsu", "animeplanet"
-- ---------------------------------------------------------------------------

canonical.external_refs
  at_uri              text        PK
  work_at_uri         text        NOT NULL    FK → canonical.works.at_uri
  source              text        NOT NULL    -- vocabulário aberto, ex: "anilist"
  external_id         text        NOT NULL    -- ID no sistema externo
  url                 text                    -- URL canônica no sistema externo; opcional
  kind                text                    -- tipo de referência; opcional e aberto
                                  -- ex: "page" | "api" | "mirror"
  indexed_at          timestamptz NOT NULL
  UNIQUE (work_at_uri, source, external_id)
  -- uma mesma obra não tem dois external_refs para o mesmo (source, external_id)


-- ---------------------------------------------------------------------------
-- CHAPTERS CANÔNICOS
-- Projeção de org.mugens.canonical.chapter
-- Identidade mínima de um capítulo: número, volume, edição.
-- Sem páginas (scan_catalog), sem scan group (mugen_catalog).
--
-- volume: string livre para número do volume na edição específica
--   ex: "3", "Especial", "" (capítulo sem volume)
-- edition: string livre para identificar a edição da obra
--   ex: "Kanzenban", "Digital", "" (edição padrão/única)
-- Separados para permitir filtro por edição independente do volume.
-- ---------------------------------------------------------------------------

canonical.chapters
  at_uri              text        PK
                                  -- at://did:plc:mugens-catalog/org.mugens.canonical.chapter/rkey
  rkey                text        NOT NULL UNIQUE
  work_at_uri         text        NOT NULL    FK → canonical.works.at_uri
  chapter_key         text        NOT NULL
                                  -- slug editorial estável: "001", "001.5", "oneshot", "special-1"
  display_number      text        NOT NULL
                                  -- exibição na UI: "1", "1.5", "Oneshot", "Especial 1"
  sort_number         numeric(10,3) NOT NULL
                                  -- ordenação numérica correta sem float: 1.000, 1.500
  volume              text        NOT NULL    DEFAULT ''
  edition             text        NOT NULL    DEFAULT ''
  title               text                    -- título do capítulo; null se não tem
  indexed_at          timestamptz NOT NULL
  updated_at          timestamptz NOT NULL
  UNIQUE (work_at_uri, chapter_key, edition)
```

**Índices:**
```sql
-- Works
CREATE INDEX ON canonical.works (rkey);
CREATE INDEX ON canonical.works (status);
CREATE INDEX ON canonical.works (work_kind);
CREATE INDEX ON canonical.works (release_year);
CREATE INDEX ON canonical.works USING GIN (genres);
  -- permite WHERE 'action' = ANY(genres) com suporte de índice

-- Aliases
CREATE INDEX ON canonical.aliases (work_at_uri);
CREATE INDEX ON canonical.aliases (title text_pattern_ops); -- prefix search

-- Relations
CREATE INDEX ON canonical.relations (source_work_uri, relation_kind);
CREATE INDEX ON canonical.relations (target_work_uri);

-- External refs
CREATE INDEX ON canonical.external_refs (work_at_uri);
CREATE INDEX ON canonical.external_refs (source, external_id);
  -- lookup rápido: "qual work tem anilist_id = 30002?"

-- Chapters
CREATE INDEX ON canonical.chapters (work_at_uri, sort_number);
CREATE INDEX ON canonical.chapters (work_at_uri, chapter_key);
CREATE INDEX ON canonical.chapters (work_at_uri, edition, sort_number);
```

---

### 2.2 `identity` — Identidade federada

O schema `identity` é a raiz absoluta do sistema. `social.users` não é mais a raiz; todo ator é identificado primariamente por DID.

```sql
identity.actors
  did               text        PK          -- ex: did:plc:abc123
  kind              text        NOT NULL    -- person | service | organization
  status            text        NOT NULL    -- active | deactivated | tombstoned | suspended
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL

identity.handles
  id                bigserial   PK
  did               text        NOT NULL    FK → identity.actors.did
  handle            text        NOT NULL    -- ex: user.bsky.social
  handle_normalized text        NOT NULL    -- lowercase, sem @
  is_current        bool        NOT NULL    DEFAULT true
  valid_from        timestamptz NOT NULL
  valid_to          timestamptz             -- null = ainda vigente
  UNIQUE (handle_normalized) WHERE is_current = true

identity.did_documents
  did               text        PK          FK → identity.actors.did
  doc_json          jsonb       NOT NULL    -- PLC doc completo
  doc_cid           text
  fetched_at        timestamptz NOT NULL
  version           int         NOT NULL    DEFAULT 1

identity.profiles
  -- projeção do record de perfil (app.bsky.actor.profile ou lexicon próprio)
  did               text        PK          FK → identity.actors.did
  display_name      text
  description       text
  avatar_blob_cid   text                    FK → blob.blobs.cid
  banner_blob_cid   text                    FK → blob.blobs.cid
  profile_record_uri text                   -- AT URI do record de perfil
  profile_record_cid text
  indexed_at        timestamptz NOT NULL

identity.accounts
  -- hospedagem de conta: existe tanto no Mugen quanto no mugenx
  did               text        PK          FK → identity.actors.did
  home_pds_url      text        NOT NULL
  repo_status       text        NOT NULL    -- active | deactivated | takendown
  hosting_status    text        NOT NULL    -- hosted_here | remote | unknown
  created_at        timestamptz NOT NULL
  deactivated_at    timestamptz

identity.local_users
  -- extensão local e privada da conta no app.
  -- Existe independentemente de ATProto: usuário cria conta com email e vincula
  -- DID depois. did é nullable para suportar bootstrap sem infraestrutura ATProto.
  id                uuid        PK
  did               text        UNIQUE      FK → identity.actors.did  -- nullable
  home_app          text        NOT NULL    -- 'mugen' | 'mugenx'
  account_mode      text        NOT NULL    DEFAULT 'atproto'
                                -- atproto | local_legacy | service
  email             text                    -- privado, nunca federado
  email_verified_at timestamptz
  password_hash     text
  email_verification_token_hash text
  email_verification_code_hash text
  email_verification_sent_at timestamptz
  email_verification_expires_at timestamptz
  email_verification_attempts int NOT NULL DEFAULT 0
  atproto_link_state text       NOT NULL    DEFAULT 'unlinked' -- legacy
                                -- unlinked:          conta local sem DID ATProto
                                -- linked:            did preenchido e verificado
                                -- pending_migration: DID em processo de vinculacao
                                -- disabled:          vinculo revogado ou conta desativada
  preferences_json  jsonb       NOT NULL    DEFAULT '{}'::jsonb
  feature_flags_json jsonb      NOT NULL    DEFAULT '{}'::jsonb
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  last_seen_at      timestamptz
  last_login_at     timestamptz

identity.user_sessions
  -- Sessões de login (web/app). Permite múltiplos dispositivos e revogação granular.
  id                uuid        PK
  user_id           uuid        NOT NULL    FK → identity.local_users.id
  refresh_token_hash text       -- legacy (auth local)
  session_token_hash text       -- sessão local ATProto
  expires_at        timestamptz NOT NULL
  last_used_at      timestamptz
  user_agent        text
  ip                text
  auth_source       text        NOT NULL    DEFAULT 'atproto'
                                -- atproto | local_legacy | api_key
  revoked_at        timestamptz
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL

identity.oauth_login_states
  -- estados efêmeros do fluxo OAuth ATProto
  id                      uuid        PK
  home_app                text        NOT NULL
  input_identifier        text        NOT NULL
  resolved_did            text        FK → identity.actors.did
  resolved_handle         text
  pds_url                 text
  authorization_issuer    text        NOT NULL
  redirect_uri            text        NOT NULL
  state                   text        NOT NULL
  nonce                   text        NOT NULL
  code_verifier           text        NOT NULL
  code_challenge          text        NOT NULL
  dpop_private_jwk         text        NOT NULL
  dpop_public_jwk          jsonb       NOT NULL
  dpop_jkt                 text        NOT NULL
  pkce_method             text        NOT NULL    DEFAULT 'S256'
  status                  text        NOT NULL    DEFAULT 'pending'
  expires_at              timestamptz NOT NULL
  consumed_at             timestamptz
  created_at              timestamptz NOT NULL    DEFAULT now()
  updated_at              timestamptz NOT NULL

identity.atproto_credentials
  -- tokens e chaves do ATProto (armazenados apenas no backend)
  id                      uuid        PK
  local_user_id           uuid        NOT NULL    FK → identity.local_users.id
  did                     text        NOT NULL    FK → identity.actors.did
  handle                  text
  pds_url                 text        NOT NULL
  authorization_issuer    text        NOT NULL
  token_endpoint          text
  revocation_endpoint     text
  scope                   text        NOT NULL
  token_type              text        NOT NULL
  access_token_ciphertext text        NOT NULL
  refresh_token_ciphertext text       NOT NULL
  access_expires_at       timestamptz
  refresh_expires_at      timestamptz
  dpop_private_jwk        text        NOT NULL
  dpop_public_jwk         jsonb       NOT NULL
  subject                 text        NOT NULL
  status                  text        NOT NULL    DEFAULT 'active'
  last_refreshed_at       timestamptz
  last_used_at            timestamptz
  revoked_at              timestamptz
  created_at              timestamptz NOT NULL    DEFAULT now()
  updated_at              timestamptz NOT NULL

identity.api_keys
  -- Chaves para terceiros / integrações.
  id                uuid        PK
  user_id           uuid        NOT NULL    FK → identity.local_users.id
  key_prefix        text        NOT NULL
  key_hash          text        NOT NULL
  created_at        timestamptz NOT NULL    DEFAULT now()
  last_used_at      timestamptz
  revoked_at        timestamptz
```

**Índices:**
```sql
CREATE UNIQUE INDEX ON identity.handles (handle_normalized) WHERE is_current = true;
CREATE INDEX ON identity.actors (status);
CREATE INDEX ON identity.local_users (home_app);
CREATE INDEX ON identity.local_users (atproto_link_state);
CREATE INDEX ON identity.local_users (did) WHERE did IS NOT NULL;
CREATE UNIQUE INDEX ON identity.local_users (email) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX ON identity.user_sessions (refresh_token_hash);
CREATE UNIQUE INDEX ON identity.user_sessions (session_token_hash) WHERE session_token_hash IS NOT NULL;
CREATE INDEX ON identity.user_sessions (user_id);
CREATE INDEX ON identity.user_sessions (expires_at);
CREATE INDEX ON identity.user_sessions (revoked_at);
CREATE UNIQUE INDEX ON identity.oauth_login_states (state);
CREATE INDEX ON identity.oauth_login_states (expires_at);
CREATE INDEX ON identity.oauth_login_states (resolved_did);
CREATE INDEX ON identity.oauth_login_states (status);
CREATE INDEX ON identity.atproto_credentials (local_user_id);
CREATE INDEX ON identity.atproto_credentials (did);
CREATE INDEX ON identity.atproto_credentials (status);
CREATE UNIQUE INDEX ON identity.atproto_credentials (local_user_id, did) WHERE revoked_at IS NULL;
CREATE UNIQUE INDEX ON identity.api_keys (key_hash);
CREATE INDEX ON identity.api_keys (key_prefix);
CREATE INDEX ON identity.api_keys (user_id);
CREATE INDEX ON identity.api_keys (revoked_at);
```

---

### 2.3 `repo` — Repositórios e records ATProto

Fonte primária de todos os dados federados. Records são escritos aqui; tudo mais é derivado.

```sql
repo.repos
  did               text        PK          FK → identity.actors.did
  head_cid          text        NOT NULL
  rev               text        NOT NULL
  signing_key_ref   text
  last_seen_at      timestamptz
  last_indexed_at   timestamptz
  status            text        NOT NULL    -- active | takendown | suspended | deleted

repo.commits
  id                bigserial   PK
  repo_did          text        NOT NULL    FK → repo.repos.did
  rev               text        NOT NULL
  commit_cid        text        NOT NULL
  prev_commit_cid   text
  commit_json       jsonb
  received_at       timestamptz NOT NULL
  indexed_at        timestamptz
  UNIQUE (repo_did, rev)

repo.records
  id                bigserial   PK
  repo_did          text        NOT NULL    FK → repo.repos.did
  collection        text        NOT NULL    -- NSID ex: com.mugens.feed.post
  rkey              text        NOT NULL
  at_uri            text        NOT NULL    -- at://did/collection/rkey
  cid               text        NOT NULL
  record_type       text        NOT NULL    -- espelho de collection para índice
  record_json       jsonb       NOT NULL
  created_at_in_record timestamptz
  indexed_at        timestamptz NOT NULL
  is_deleted        bool        NOT NULL    DEFAULT false
  visibility_state  text        NOT NULL    DEFAULT 'visible'
                                            -- visible | takendown | filtered
  takedown_state    text        NOT NULL    DEFAULT 'none'
  UNIQUE (repo_did, collection, rkey)
  UNIQUE (at_uri)

repo.record_deletes
  id                bigserial   PK
  repo_did          text        NOT NULL
  collection        text        NOT NULL
  rkey              text        NOT NULL
  at_uri            text        NOT NULL
  deleted_at        timestamptz NOT NULL
  reason            text                    -- tombstone | user_delete | takedown

repo.record_links
  -- índice de referências entre records (reply, quote, embed, mention, subject)
  id                bigserial   PK
  source_at_uri     text        NOT NULL    FK → repo.records.at_uri
  source_cid        text        NOT NULL
  link_type         text        NOT NULL
                                -- reply_parent | reply_root | quote | subject
                                -- embed_record | mention_actor | facet_link | custom
  target_uri        text
  target_cid        text
  target_did        text
  target_url        text
  position          int
```

**Índices:**
```sql
CREATE INDEX ON repo.records (repo_did, collection, indexed_at DESC)
  WHERE is_deleted = false;
CREATE INDEX ON repo.records (collection, indexed_at DESC)
  WHERE is_deleted = false;
CREATE INDEX ON repo.record_links (target_uri, link_type);
CREATE INDEX ON repo.record_links (target_did);
```

---

### 2.4 `blob` — Blobs do protocolo

Blobs ATProto são objetos separados dos records, referenciados por CID. **Este schema cobre exclusivamente blobs que fazem parte da federação** — ou seja, assets cujo dono é um ator e que são referenciados por algum record via blob ref.

> **Distinção importante: blob ATProto vs. asset editorial**
>
> | Asset | Dono | Onde fica | Por quê |
> |---|---|---|---|
> | Cover publicada pela scan junto com a série | Ator (scan group) | `blob.blobs` + `blob.record_blob_refs` | Faz parte do record `org.mugenx.catalog.series`; qualquer app que resolver o AT URI precisa conseguir exibir a capa |
> | Cover editorial do Mugen (versão padronizada/recortada) | O próprio Mugen | `mugen_ops.editorial_assets` + R2/CDN externo | É um artefato de curadoria interna, como merge decisions e rankings — não pertence à federação |
> | Avatar/banner de usuário | Ator (usuário) | `blob.blobs` + `blob.record_blob_refs` | Parte do record de perfil federado |
> | Páginas de capítulo | Scan | **Nunca em `blob.blobs`** — R2/CDN local da scan | Payload técnico, muito pesado e não federado; referenciado apenas localmente em `scan_catalog.chapter_pages` |
>
> **Regra**: se o asset está vinculado a um record ATProto e outros apps precisam resolvê-lo via CID → `blob.blobs`. Se é asset editorial/derivado/interno do app → storage externo (R2/CDN), com referência em tabela do schema do app (`mugen_ops` ou `scan_ops`).

```sql
blob.blobs
  cid               text        PK          -- CID sha256-based
  owner_did         text        NOT NULL    FK → identity.actors.did
  mime_type         text        NOT NULL
  size_bytes        bigint      NOT NULL
  width             int
  height            int
  duration_ms       int
  created_at        timestamptz NOT NULL
  availability_state text       NOT NULL    DEFAULT 'available'
                                            -- available | cdn_only | unavailable | takendown

blob.record_blob_refs
  record_at_uri     text        NOT NULL    FK → repo.records.at_uri
  record_cid        text        NOT NULL
  blob_cid          text        NOT NULL    FK → blob.blobs.cid
  purpose           text        NOT NULL
                                -- avatar | banner | post_image | post_audio
                                -- chapter_cover | series_cover | page_image | thumbnail
  alt_text          text
  position          int
  PRIMARY KEY (record_at_uri, blob_cid, purpose)

blob.derived_assets
  -- variantes geradas a partir de um blob protocolar (thumbnails, transcodificações)
  blob_cid          text        NOT NULL    FK → blob.blobs.cid
  variant_kind      text        NOT NULL    -- thumbnail_sm | thumbnail_md | webp | avif
  storage_url       text        NOT NULL    -- URL no CDN/R2 do app
  width             int
  height            int
  codec             text
  created_at        timestamptz NOT NULL
  PRIMARY KEY (blob_cid, variant_kind)
```

---

### 2.5 `graph` — Interações sociais federáveis

Projeções de records representando o grafo social público.

```sql
graph.follows
  record_at_uri     text        PK          FK → repo.records.at_uri
  actor_did         text        NOT NULL    FK → identity.actors.did
  subject_did       text        NOT NULL    FK → identity.actors.did
  created_at        timestamptz NOT NULL
  is_deleted        bool        NOT NULL    DEFAULT false

graph.likes
  record_at_uri     text        PK          FK → repo.records.at_uri
  actor_did         text        NOT NULL
  subject_uri       text        NOT NULL
  subject_cid       text        NOT NULL
  created_at        timestamptz NOT NULL
  is_deleted        bool        NOT NULL    DEFAULT false

graph.reposts
  record_at_uri     text        PK          FK → repo.records.at_uri
  actor_did         text        NOT NULL
  subject_uri       text        NOT NULL
  subject_cid       text        NOT NULL
  created_at        timestamptz NOT NULL
  is_deleted        bool        NOT NULL    DEFAULT false

graph.blocks
  record_at_uri     text        PK
  actor_did         text        NOT NULL
  subject_did       text        NOT NULL
  created_at        timestamptz NOT NULL
  is_deleted        bool        NOT NULL    DEFAULT false

graph.mutes
  -- local only, privado, nunca federado
  actor_did         text        NOT NULL
  subject_did       text        NOT NULL
  created_at        timestamptz NOT NULL
  PRIMARY KEY (actor_did, subject_did)

graph.bookmarks
  -- local only, privado, nunca federado
  id                uuid        PK
  actor_did         text        NOT NULL
  subject_uri       text        NOT NULL
  subject_kind      text        NOT NULL    -- post | series | chapter | track
  created_at        timestamptz NOT NULL

graph.counters
  -- Contadores desnormalizados por subject_uri para leitura rápida na UI.
  -- SEMÂNTICA: contam apenas interações de atores ativos, não deletadas e não
  -- moderadas (takedown). Registros com visibility != 'public' não são contados.
  -- São eventualmente consistentes — reconstruídos a partir de graph.likes/reposts
  -- e content.posts (reply_count). Nunca use como fonte de verdade para auditoria.
  subject_uri       text        PK
  like_count        int         NOT NULL    DEFAULT 0    -- likes não deletados
  repost_count      int         NOT NULL    DEFAULT 0    -- reposts não deletados
  reply_count       int         NOT NULL    DEFAULT 0    -- replies públicas diretas
  updated_at        timestamptz NOT NULL
```

**Índices:**
```sql
CREATE INDEX ON graph.follows (actor_did) WHERE is_deleted = false;
CREATE INDEX ON graph.follows (subject_did) WHERE is_deleted = false;
CREATE INDEX ON graph.likes (subject_uri) WHERE is_deleted = false;
CREATE INDEX ON graph.bookmarks (actor_did, subject_kind);
```

---

### 2.6 `content` — Projeção consultável de posts/comentários

Não é fonte primária. É uma projeção indexada de `repo.records` para queries de UI rápidas.

```sql
content.posts
  record_at_uri     text        PK          FK → repo.records.at_uri
  repo_did          text        NOT NULL
  record_cid        text        NOT NULL
  record_type       text        NOT NULL    -- NSID do lexicon
  text              text
  lang              text[]
  reply_root_uri    text
  reply_parent_uri  text
  quote_uri         text
  subject_uri       text                    -- AT URI do subject (série/capítulo/etc.)
  subject_kind      text                    -- series | chapter | track | work | post
  visibility        text        NOT NULL    DEFAULT 'public'
  created_at        timestamptz
  indexed_at        timestamptz NOT NULL

content.post_facets
  id                bigserial   PK
  post_uri          text        NOT NULL    FK → content.posts.record_at_uri
  facet_kind        text        NOT NULL    -- mention | hashtag | link
  byte_start        int         NOT NULL
  byte_end          int         NOT NULL
  target_did        text
  target_url        text
  tag_text          text

content.comment_subjects
  -- Mapeia um comentário para o subject de catálogo ao qual ele se refere.
  --
  -- REGRA DE INTEGRIDADE (XOR):
  --   subject_at_uri preenchido  → subject_local_id DEVE ser nulo
  --   subject_local_id preenchido → subject_at_uri DEVE ser nulo
  --   Ambos nulos é inválido. Ambos preenchidos é inválido.
  --
  -- QUANDO USAR CADA UM:
  --   subject_at_uri   — subject já foi publicado como record federado;
  --                      é a forma preferida e a que permite interoperabilidade cross-app.
  --   subject_local_id — subject ainda é rascunho local (federation_state = 'draft')
  --                      no mugenx; usado só internamente até publicação.
  --                      O Mugen nunca usa subject_local_id.
  --
  -- Quando o subject de 'draft' for publicado, o worker de federação deve atualizar
  -- este registro: preencher subject_at_uri e zerar subject_local_id.
  post_uri          text        PK          FK → content.posts.record_at_uri
  subject_kind      text        NOT NULL    -- series | chapter | volume | track
  subject_at_uri    text                    -- AT URI se subject é record federado
  subject_local_id  text                    -- UUID local somente se ainda não publicado
  position          int         NOT NULL    DEFAULT 0
  CONSTRAINT chk_subject_xor CHECK (
    (subject_at_uri IS NOT NULL AND subject_local_id IS NULL) OR
    (subject_at_uri IS NULL AND subject_local_id IS NOT NULL)
  )

content.thread_projections
  root_uri          text        NOT NULL
  post_uri          text        NOT NULL    FK → content.posts.record_at_uri
  depth             int         NOT NULL    DEFAULT 0
  path              text[]      NOT NULL
  PRIMARY KEY (root_uri, post_uri)
```

**Índices:**
```sql
CREATE INDEX ON content.posts (repo_did, created_at DESC);
CREATE INDEX ON content.posts (subject_uri, created_at DESC) WHERE subject_uri IS NOT NULL;
CREATE INDEX ON content.posts (reply_root_uri) WHERE reply_root_uri IS NOT NULL;
CREATE INDEX ON content.comment_subjects (subject_at_uri) WHERE subject_at_uri IS NOT NULL;
CREATE INDEX ON content.comment_subjects (subject_local_id) WHERE subject_local_id IS NOT NULL;
CREATE INDEX ON content.post_facets (post_uri);
CREATE INDEX ON content.post_facets (tag_text) WHERE tag_text IS NOT NULL;
CREATE INDEX ON content.thread_projections (root_uri, depth);
```

---

### 2.7 `activity` — Relação do usuário com o catálogo (Plano 3)

O schema `activity` são projeções AppView dos records de atividade publicados no PDS do usuário via `org.mugens.activity.*`. Todo dado aqui nasce federado — público por padrão, portável, endereçável por AT URI.

**Contrato fundamental de portabilidade:**
`subject_work_uri` aponta sempre para `canonical.works.at_uri` (`at://did:plc:mugens-catalog/org.mugens.canonical.work/rkey`). `subject_chapter_uri` aponta sempre para `canonical.chapters.at_uri`. Nunca para IDs internos de `mugen_catalog` ou `scan_catalog`. Esse contrato é o que garante que a biblioteca do usuário sobrevive à queda do Mugen ou de qualquer instância mugenx.

O AppView resolve o URI canônico para exibição local (`resolved_work_id` no Mugen, `resolved_series_id` no mugenx), mas essa resolução é local — não faz parte do record federado.

**Visibilidade:** `"private"` é uma convenção que AppViews cooperativos respeitam. Não é privacidade técnica no nível do protocolo — o record existe no PDS e é acessível. Usuário que quiser privacidade real simplesmente não cria o record federado e mantém o estado em `local.*`.

```sql
-- ---------------------------------------------------------------------------
-- LISTAS DE LEITURA
-- Record: org.mugens.activity.library
-- Um entry por (ator, work canônico). list_kind determina o estado atual.
-- subject aponta para canonical.works — portável independente de qualquer app.
-- ---------------------------------------------------------------------------

activity.work_list_entries
  record_at_uri       text        PK          FK → repo.records.at_uri
  actor_did           text        NOT NULL    FK → identity.actors.did
  subject_work_uri    text        NOT NULL    FK → canonical.works.at_uri
                                  -- at://did:plc:mugens-catalog/org.mugens.canonical.work/rkey
  list_kind           text        NOT NULL
                                  -- reading | completed | on_hold | dropped | plan_to_read
  visibility          text        NOT NULL    DEFAULT 'public'
  started_at          timestamptz
  completed_at        timestamptz
  created_at          timestamptz NOT NULL
  updated_at          timestamptz NOT NULL
  -- Resolução local pelo AppView (não parte do record federado)
  resolved_work_id    bigint                  FK → mugen_catalog.works.id
  resolved_series_id  uuid                    -- FK → scan_catalog.series.id (mugenx)
  UNIQUE (actor_did, subject_work_uri)
  CONSTRAINT chk_list_kind CHECK (list_kind IN
    ('reading','completed','on_hold','dropped','plan_to_read'))
  CONSTRAINT chk_visibility CHECK (visibility IN ('public','private'))

-- ---------------------------------------------------------------------------
-- STATUS DE LEITURA POR CAPÍTULO
-- Record: org.mugens.activity.chapter_progress
-- "Eu li este capítulo" — granularidade de capítulo, não de página.
-- Progresso intra-capítulo (última página lida) fica em local.reading_progress.
-- subject aponta para canonical.chapters — portável entre AppViews.
-- ---------------------------------------------------------------------------

activity.chapter_read_status
  record_at_uri         text        PK          FK → repo.records.at_uri
  actor_did             text        NOT NULL    FK → identity.actors.did
  subject_chapter_uri   text        NOT NULL    FK → canonical.chapters.at_uri
                                    -- at://did:plc:mugens-catalog/org.mugens.canonical.chapter/rkey
  visibility            text        NOT NULL    DEFAULT 'public'
  read_at               timestamptz NOT NULL
  created_at            timestamptz NOT NULL
  -- Resolução local pelo AppView
  resolved_chapter_id   bigint                  FK → mugen_catalog.chapters.id
  UNIQUE (actor_did, subject_chapter_uri)
  CONSTRAINT chk_visibility CHECK (visibility IN ('public','private'))

-- ---------------------------------------------------------------------------
-- REVIEWS
-- Record: org.mugens.activity.review
-- Uma review por (ator, work canônico). Comentável via AT URI do record.
-- ---------------------------------------------------------------------------

activity.work_reviews
  record_at_uri       text        PK          FK → repo.records.at_uri
  actor_did           text        NOT NULL    FK → identity.actors.did
  subject_work_uri    text        NOT NULL    FK → canonical.works.at_uri
  score               smallint                -- null = sem nota; 0-100
  body_text           text
  lang                text
  contains_spoilers   bool        NOT NULL    DEFAULT false
  visibility          text        NOT NULL    DEFAULT 'public'
  created_at          timestamptz NOT NULL
  updated_at          timestamptz NOT NULL
  resolved_work_id    bigint                  FK → mugen_catalog.works.id
  UNIQUE (actor_did, subject_work_uri)
  CONSTRAINT chk_score CHECK (score IS NULL OR (score BETWEEN 0 AND 100))
  CONSTRAINT chk_visibility CHECK (visibility IN ('public','private'))


activity.work_tag_votes
  work_id            bigint      NOT NULL    FK → mugen_catalog.works.id
  tag_id             bigint      NOT NULL    FK → mugen_catalog.tags.id
  actor_did          text        NOT NULL    FK → identity.actors.did

  vote               smallint    NOT NULL    DEFAULT 1
                                     -- 1 = acha apropriada / apoia
                                     -- -1 = acha inadequada / rejeita
  is_spoiler         bool        NOT NULL    DEFAULT false

  created_at         timestamptz NOT NULL
  updated_at         timestamptz NOT NULL

  PRIMARY KEY (work_id, tag_id, actor_did),

  CONSTRAINT chk_work_tag_votes_vote
    CHECK (vote IN (-1, 1))

CREATE INDEX ON activity.work_tag_votes (work_id, tag_id);
CREATE INDEX ON activity.work_tag_votes (actor_did, updated_at DESC);
CREATE INDEX ON activity.work_tag_votes (work_id, updated_at DESC);


activity.work_tag_proposals
  id                    bigserial   PK

  work_id               bigint      NOT NULL    FK → mugen_catalog.works.id
  actor_did             text        NOT NULL    FK → identity.actors.did

  -- Se a proposta usa uma tag já existente no catálogo
  tag_id                bigint                  FK → mugen_catalog.tags.id

  -- Se a proposta é de uma tag nova ainda não canonizada
  proposed_label        text
  proposed_slug         text
  proposed_kind         text
                                              -- genre | theme | setting | trope | attribute | content_warning
  proposed_description  text

  -- Metadados da associação sugerida à obra
  is_spoiler            bool        NOT NULL    DEFAULT false
  note                  text
  confidence            numeric(6,3)

  status                text        NOT NULL    DEFAULT 'pending'
                                              -- pending | accepted | rejected | withdrawn | superseded

  reviewed_by_did       text                    FK → identity.actors.did
  reviewed_at           timestamptz
  review_note           text

  -- Se a proposta gerar uma tag nova aprovada no catálogo
  resulting_tag_id      bigint                  FK → mugen_catalog.tags.id

  created_at            timestamptz NOT NULL
  updated_at            timestamptz NOT NULL

  CONSTRAINT chk_work_tag_proposals_target
    CHECK (
      (tag_id IS NOT NULL AND proposed_label IS NULL AND proposed_slug IS NULL AND proposed_kind IS NULL)
      OR
      (tag_id IS NULL AND proposed_label IS NOT NULL AND proposed_kind IS NOT NULL)
    ),

  CONSTRAINT chk_work_tag_proposals_status
    CHECK (status IN ('pending', 'accepted', 'rejected', 'withdrawn', 'superseded')),

  CONSTRAINT chk_work_tag_proposals_confidence
    CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1))

-- ---------------------------------------------------------------------------
-- RATINGS (nota sem texto)
-- Record: org.mugens.activity.rating
-- Separado de review: usuário pode dar nota sem escrever, ou ter os dois.
-- ---------------------------------------------------------------------------

activity.work_ratings
  record_at_uri       text        PK          FK → repo.records.at_uri
  actor_did           text        NOT NULL    FK → identity.actors.did
  subject_work_uri    text        NOT NULL    FK → canonical.works.at_uri
  score               smallint    NOT NULL    -- 0-100
  visibility          text        NOT NULL    DEFAULT 'public'
  created_at          timestamptz NOT NULL
  resolved_work_id    bigint                  FK → mugen_catalog.works.id
  UNIQUE (actor_did, subject_work_uri)
  CONSTRAINT chk_score CHECK (score BETWEEN 0 AND 100)
  CONSTRAINT chk_visibility CHECK (visibility IN ('public','private'))

-- ---------------------------------------------------------------------------
-- FAVORITOS
-- Record: org.mugens.activity.favorite
-- Curadoria afetiva — distinto de list_entry (que é estado de leitura).
-- ---------------------------------------------------------------------------

activity.work_favorites
  record_at_uri       text        PK          FK → repo.records.at_uri
  actor_did           text        NOT NULL    FK → identity.actors.did
  subject_work_uri    text        NOT NULL    FK → canonical.works.at_uri
  visibility          text        NOT NULL    DEFAULT 'public'
  position            int                     -- ordem na lista de favoritos
  created_at          timestamptz NOT NULL
  resolved_work_id    bigint                  FK → mugen_catalog.works.id
  UNIQUE (actor_did, subject_work_uri)
  CONSTRAINT chk_visibility CHECK (visibility IN ('public','private'))

-- ---------------------------------------------------------------------------
-- AGREGADO DE ATIVIDADE POR WORK CANÔNICO (AppView — não é record federado)
-- Cache de contadores derivado de activity.* via firehose.
-- Keyed por subject_work_uri (canônico) — não por ID interno.
-- ---------------------------------------------------------------------------

activity.work_activity_counts
  subject_work_uri      text        PK          FK → canonical.works.at_uri
  resolved_work_id      bigint                  FK → mugen_catalog.works.id
  list_reading_count    int         NOT NULL    DEFAULT 0
  list_completed_count  int         NOT NULL    DEFAULT 0
  list_plan_count       int         NOT NULL    DEFAULT 0
  list_dropped_count    int         NOT NULL    DEFAULT 0
  review_count          int         NOT NULL    DEFAULT 0
  rating_count          int         NOT NULL    DEFAULT 0
  rating_avg            numeric(4,2)            -- 0.00-100.00
  favorite_count        int         NOT NULL    DEFAULT 0
  updated_at            timestamptz NOT NULL
```

**Índices:**
```sql
-- Listas de leitura
CREATE INDEX ON activity.work_list_entries (actor_did, list_kind)
  WHERE visibility = 'public';
CREATE INDEX ON activity.work_list_entries (subject_work_uri, list_kind)
  WHERE visibility = 'public';
CREATE INDEX ON activity.work_list_entries (resolved_work_id, list_kind)
  WHERE resolved_work_id IS NOT NULL AND visibility = 'public';

-- Progresso de capítulos
CREATE INDEX ON activity.chapter_read_status (actor_did, read_at DESC)
  WHERE visibility = 'public';
CREATE INDEX ON activity.chapter_read_status (subject_chapter_uri)
  WHERE visibility = 'public';
CREATE INDEX ON activity.chapter_read_status (resolved_chapter_id)
  WHERE resolved_chapter_id IS NOT NULL;

-- Reviews
CREATE INDEX ON activity.work_reviews (subject_work_uri, created_at DESC)
  WHERE visibility = 'public';
CREATE INDEX ON activity.work_reviews (actor_did, created_at DESC);

-- Ratings
CREATE INDEX ON activity.work_ratings (subject_work_uri)
  WHERE visibility = 'public';

-- Favoritos
CREATE INDEX ON activity.work_favorites (actor_did, position)
  WHERE visibility = 'public';
CREATE INDEX ON activity.work_favorites (subject_work_uri)
  WHERE visibility = 'public';

-- Contadores
CREATE INDEX ON activity.work_activity_counts (resolved_work_id)
  WHERE resolved_work_id IS NOT NULL;
```

---

### 2.8 `label` — Labels ATProto e labelers

Labels são objetos independentes e assináveis do protocolo. Separados de moderação humana interna.

```sql
label.labelers
  did               text        PK          FK → identity.actors.did
  service_url       text        NOT NULL
  policy_json       jsonb
  is_local          bool        NOT NULL    DEFAULT false
  is_trusted_default bool       NOT NULL    DEFAULT false
  created_at        timestamptz NOT NULL

label.labels
  id                bigserial   PK
  src_did           text        NOT NULL    FK → label.labelers.did
  uri               text
  cid               text
  val               text        NOT NULL    -- ex: porn | graphic-media | !warn | custom
  neg               bool        NOT NULL    DEFAULT false
  cts               timestamptz NOT NULL
  exp               timestamptz
  sig               text
  subject_kind      text        NOT NULL    -- repo | record | blob
  subject_did       text
  subject_uri       text
  subject_cid       text

label.subscriptions
  viewer_did        text        NOT NULL
  labeler_did       text        NOT NULL    FK → label.labelers.did
  mode              text        NOT NULL    -- hide | warn | show
  PRIMARY KEY (viewer_did, labeler_did)

label.reports_inbox
  id                bigserial   PK
  reporter_did      text        NOT NULL
  target_uri        text
  target_did        text
  reason_type       text        NOT NULL    -- spam | violation | misleading | other
  reason_text       text
  created_at        timestamptz NOT NULL
  status            text        NOT NULL    DEFAULT 'pending'
  triaged_case_id   bigint                  -- FK → local.moderation_cases.id
```

**Índices:**
```sql
CREATE INDEX ON label.labels (subject_uri) WHERE subject_uri IS NOT NULL;
CREATE INDEX ON label.labels (subject_did) WHERE subject_did IS NOT NULL;
CREATE INDEX ON label.labels (src_did, val);
CREATE INDEX ON label.reports_inbox (status, created_at);
```

---

### 2.9 `local` — Estados privados, preferências e moderação humana

```sql
local.user_preferences
  did               text        PK
  theme             text                    DEFAULT 'system'
  language          text                    DEFAULT 'pt'
  content_filters   jsonb       NOT NULL    DEFAULT '{}'
  notification_pref jsonb       NOT NULL    DEFAULT '{}'
  reader_pref       jsonb       NOT NULL    DEFAULT '{}'
  updated_at        timestamptz NOT NULL

local.feature_flags
  key               text        PK
  description       text
  enabled_default   bool        NOT NULL    DEFAULT false
  rollout_pct       int         NOT NULL    DEFAULT 0

local.user_feature_overrides
  did               text        NOT NULL
  flag_key          text        NOT NULL    FK → local.feature_flags.key
  enabled           bool        NOT NULL
  expires_at        timestamptz
  PRIMARY KEY (did, flag_key)

local.reading_progress
  -- Progresso intra-capítulo: última página lida, timestamp. Genuinamente privado.
  -- Distinto de activity.chapter_read_status (federado, "terminei este capítulo").
  -- Este registro existe só no AppView local — nunca sai para a federação.
  did               text        NOT NULL
  chapter_at_uri    text        NOT NULL    -- AT URI do capítulo
  last_page         int         NOT NULL    DEFAULT 1
  total_pages       int
  completed         bool        NOT NULL    DEFAULT false
  started_at        timestamptz NOT NULL
  updated_at        timestamptz NOT NULL
  PRIMARY KEY (did, chapter_at_uri)

local.notification_events
  id                bigserial   PK
  recipient_did     text        NOT NULL
  kind              text        NOT NULL    -- like | repost | follow | reply | mention
                                            -- chapter_release | review | list_add
                                            -- moderation | system
  actor_did         text
  subject_uri       text
  payload_json      jsonb
  seen              bool        NOT NULL    DEFAULT false
  created_at        timestamptz NOT NULL

local.notification_settings
  did               text        PK
  settings_json     jsonb       NOT NULL    DEFAULT '{}'

local.moderation_cases
  id                bigserial   PK
  subject_kind      text        NOT NULL    -- user | post | series | chapter | group
  subject_uri       text
  subject_did       text
  opened_at         timestamptz NOT NULL
  closed_at         timestamptz
  status            text        NOT NULL    DEFAULT 'open'
                                            -- open | under_review | resolved | appealed
  resolution        text                    -- no_action | warn | mute | suspend | takedown
  internal_notes    text
  reporter_did      text
  assignee_did      text

local.moderation_actions
  id                bigserial   PK
  case_id           bigint      NOT NULL    FK → local.moderation_cases.id
  actor_did         text        NOT NULL
  action_kind       text        NOT NULL    -- label | warn | mute | suspend | takedown | reverse
  label_val         text
  reason            text
  created_at        timestamptz NOT NULL

local.appeals
  id                bigserial   PK
  case_id           bigint      NOT NULL    FK → local.moderation_cases.id
  appellant_did     text        NOT NULL
  reason            text        NOT NULL
  submitted_at      timestamptz NOT NULL
  reviewed_at       timestamptz
  outcome           text                    -- upheld | overturned | partial
```

**Índices:**
```sql
CREATE INDEX ON local.notification_events (recipient_did, seen, created_at DESC);
CREATE INDEX ON local.moderation_cases (subject_uri) WHERE subject_uri IS NOT NULL;
CREATE INDEX ON local.moderation_cases (status, opened_at DESC);
```

---

### 2.10 `ops` — Infraestrutura operacional compartilhada

```sql
ops.idempotency_keys
  key               text        PK
  result_json       jsonb
  created_at        timestamptz NOT NULL
  expires_at        timestamptz NOT NULL

ops.firehose_cursors
  stream_name       text        PK          -- ex: 'relay_bsky', 'relay_mugens'
  upstream_url      text        NOT NULL
  cursor            bigint      NOT NULL    DEFAULT 0
  updated_at        timestamptz NOT NULL

ops.sync_events
  id                bigserial   PK
  stream_name       text        NOT NULL    FK → ops.firehose_cursors.stream_name
  seq               bigint      NOT NULL
  repo_did          text
  action_type       text        NOT NULL    -- commit | identity | account | tombstone | label
  payload_json      jsonb
  received_at       timestamptz NOT NULL
  processed_at      timestamptz
  status            text        NOT NULL    DEFAULT 'pending'
  error_message     text
  UNIQUE (stream_name, seq)

ops.rate_limit_counters
  key               text        NOT NULL
  window_start      timestamptz NOT NULL
  count             int         NOT NULL    DEFAULT 0
  PRIMARY KEY (key, window_start)

ops.event_dedupe_keys
  key               text        PK
  created_at        timestamptz NOT NULL
  expires_at        timestamptz NOT NULL
```

**Índices:**
```sql
CREATE INDEX ON ops.idempotency_keys (expires_at);
CREATE INDEX ON ops.sync_events (status, received_at);
```

---

## 3. Schemas Exclusivos do Mugen

### 3.1 `mugen_catalog` — Catálogo canônico reconciliado

O catálogo do Mugen é uma **visão editorial**, não uma fonte primária federada. Agrega dados de múltiplos providers numa entidade canônica local.

```sql
mugen_catalog.works
  id                bigserial   PK
  canonical_slug    text        UNIQUE NOT NULL
  primary_title     text        NOT NULL
  content_rating    text                    -- general | teen | mature | adult
  demographic       text
  format            text                    -- manga | manhwa | manhua | novel | webtoon
  status            text                    -- ongoing | completed | hiatus | cancelled
  country_of_origin text
  release_year      int
  start_date        date
  end_date          date
  chapters_count    int
  volumes_count     int
  original_language text                    -- ISO 639-1, quando disponível
  source            text                    -- anilist source (ex: original | light_novel | game)
  editorial_basis   text        NOT NULL    -- internal | anilist | mangadex | merged
  visibility        text        NOT NULL    DEFAULT 'public'

  federation_state        text        NOT NULL    DEFAULT 'local'
                                                  -- local | linked | published | deprecated
  linked_canonical_at_uri text
  linked_canonical_cid    text
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL

-- Política de merge (resumo):
-- metadata por campo (work_metadata_refs) com prioridades explícitas
--   ex: demographic/status/content_rating → MangaDex; format → AniList; release_year → AniList
-- tags: AniList prioritário
-- relations: união; em conflito direto, AniList vence
-- matching inicial: MangaDex → AniList via external refs (ex: links.al)

mugen_catalog.work_descriptions
  id          bigserial   PK
  work_id     bigint      NOT NULL    FK → mugen_catalog.works.id
  lang        text        NOT NULL
  description text        NOT NULL
  is_primary  bool        NOT NULL    DEFAULT false
  updated_at  timestamptz NOT NULL
  created_at  timestamptz NOT NULL    DEFAULT now()

mugen_catalog.work_titles
  id                bigserial   PK
  work_id           bigint      NOT NULL    FK → mugen_catalog.works.id
  lang              text        NOT NULL
  title             text        NOT NULL
  title_kind        text        NOT NULL    -- official | romanized | synonym | unofficial
  is_primary        bool        NOT NULL    DEFAULT false
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL

  UNIQUE (work_id, lang, title, title_kind)

CREATE UNIQUE INDEX uq_work_titles_primary_per_lang
  ON mugen_catalog.work_titles (work_id, lang)
  WHERE is_primary = true;

-- Metadados por campo (proveniência + merge field-level)
mugen_catalog.work_metadata_refs
  id                 bigserial   PK
  work_id            bigint      NOT NULL    FK → mugen_catalog.works.id
  field_name         text        NOT NULL    -- content_rating | demographic | format | status | release_year | etc
  value_text         text        NOT NULL
  provider_id        text        NOT NULL    FK → provider_ingest.providers.id
  source_external_id text        NOT NULL
  raw_work_id        bigint                  FK → provider_ingest.raw_works.id
  created_at         timestamptz NOT NULL    DEFAULT now()
  updated_at         timestamptz NOT NULL
  UNIQUE (work_id, field_name, provider_id)

-- Evidências de títulos por provider (proveniência).
mugen_catalog.work_title_refs
  id                bigserial   PK
  work_id           bigint      NOT NULL    FK → mugen_catalog.works.id
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  source_external_id text       NOT NULL    -- id da obra no provider
  raw_work_id       bigint                  FK → provider_ingest.raw_works.id
  lang              text        NOT NULL
  title             text        NOT NULL
  title_kind        text        NOT NULL
  is_primary        bool        NOT NULL    DEFAULT false
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  UNIQUE (work_id, provider_id, lang, title, title_kind)

-- Evidências de descrições por provider (proveniência).
mugen_catalog.work_description_refs
  id                bigserial   PK
  work_id           bigint      NOT NULL    FK → mugen_catalog.works.id
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  source_external_id text       NOT NULL    -- id da obra no provider
  raw_work_id       bigint                  FK → provider_ingest.raw_works.id
  lang              text        NOT NULL
  description       text        NOT NULL
  is_primary        bool        NOT NULL    DEFAULT false
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  UNIQUE (work_id, provider_id, lang, description)

mugen_catalog.work_relations
  id                bigserial   PK
  source_work_id    bigint      NOT NULL    FK → mugen_catalog.works.id
  target_work_id    bigint      NOT NULL    FK → mugen_catalog.works.id
  relation_kind     text        NOT NULL    -- sequel | prequel | spinoff | adaptation
                                            -- alternative | side_story | character | summary
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  UNIQUE (source_work_id, target_work_id, relation_kind)
  CHECK (source_work_id != target_work_id)

mugen_catalog.work_relation_refs
  -- Evidência externa que sustenta uma relação entre dois works internos.
  -- Distinto de work_external_refs: aqui o dado responde
  -- "de onde veio a evidência desta relação?", não "qual provider ID é este work?"
  id                 bigserial   PK
  relation_id        bigint      NOT NULL    FK → mugen_catalog.work_relations.id
  provider_id        text        NOT NULL    FK → provider_ingest.providers.id
  source_external_id text        NOT NULL
  target_external_id text        NOT NULL
  relation_kind      text        NOT NULL
  created_at         timestamptz NOT NULL    DEFAULT now()
  updated_at         timestamptz NOT NULL
  UNIQUE (provider_id, source_external_id, target_external_id, relation_kind)

-- ---------------------------------------------------------------------------
-- LINKS NAVEGÁVEIS / EDITORIAIS
-- Links para UX: lojas, sites oficiais, plataformas de leitura, editoras.
-- NÃO é tabela de identidade/reconciliação — para isso existem as *_external_refs.
--
-- platform_name: nome da plataforma de destino (não confundir com providers de ingest)
--   ex: amazon | bookwalker | viz | kodansha | shueisha | cmoa | comixology
-- target_kind: o que o link aponta dentro da plataforma
--   ex: series | volume | publisher_page | storefront | official_site
-- link_kind: categoria do link para agrupamento na UI
--   ex: official_site | publisher | store | reading_platform
-- ---------------------------------------------------------------------------

mugen_catalog.external_links
  id                bigserial   PK
  subject_kind      text        NOT NULL    -- work | volume
  subject_id        bigint      NOT NULL
  label             text        NOT NULL
  url               text        NOT NULL
  link_kind         text        NOT NULL    -- official_site | publisher | store | reading_platform
  platform_name     text                    -- amazon | bookwalker | viz | kodansha | shueisha
  target_kind       text                    -- series | volume | publisher_page | storefront | official_site
  region_code       text
  lang              text
  is_official       bool        NOT NULL    DEFAULT false
  sort_order        int         NOT NULL    DEFAULT 0
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL

CREATE INDEX ON mugen_catalog.external_links (subject_kind, subject_id, link_kind);

mugen_catalog.external_link_external_refs
  id                bigserial   PK
  external_link_id   bigint      NOT NULL    FK → mugen_catalog.external_links.id
  provider_id        text        NOT NULL    FK → provider_ingest.providers.id
  external_id        text                    -- id do link no provider, se existir
  source_subject_kind text       NOT NULL    -- work | chapter | volume | publisher | author
  source_external_id text        NOT NULL    -- entidade externa da qual o link foi extraído
  raw_link_key       text                    -- chave bruta / slug / url normalizada do provider
  linked_by          text        NOT NULL    DEFAULT 'auto'
                                             -- auto | editorial | imported
  linked_by_user_id  uuid                    FK → identity.local_users.id
  linked_at          timestamptz NOT NULL
  created_at         timestamptz NOT NULL    DEFAULT now()
  updated_at         timestamptz NOT NULL
CREATE INDEX ON mugen_catalog.external_link_external_refs (external_link_id);
CREATE INDEX ON mugen_catalog.external_link_external_refs (provider_id, source_external_id);
CREATE UNIQUE INDEX uq_external_link_ref_provider_key
  ON mugen_catalog.external_link_external_refs (provider_id, source_subject_kind, source_external_id, raw_link_key);

mugen_catalog.staff_people
  id                bigserial   PK
  canonical_name    text        NOT NULL
  name_native       text
  actor_did         text                    FK → identity.actors.did  -- nullable
                                -- vínculo com ator ATProto; preenchido quando estabelecido
  created_at        timestamptz NOT NULL

mugen_catalog.work_staff
  id                bigserial   PK
  work_id           bigint      NOT NULL    FK → mugen_catalog.works.id
  person_id         bigint      NOT NULL    FK → mugen_catalog.staff_people.id
  role              text        NOT NULL    -- story | art | translation | lettering | edit
  is_verified       bool        NOT NULL    DEFAULT false

mugen_catalog.tags
  id                bigserial   PK
  slug              text        UNIQUE NOT NULL
  label             text        NOT NULL
  kind              text        -- genre | theme | setting | trope | attribute | content_warning
  description       text

  -- Ciclo de vida editorial
  status            text        NOT NULL        DEFAULT 'active'
                                                -- active | deprecated | merged | locked
  redirect_to_tag_id bigint                     FK → mugen_catalog.tags.id
                                                -- preenchido quando status = 'merged'
  is_locked         bool        NOT NULL        DEFAULT false
                                                -- impede votos/edições da comunidade
  is_nsfw           bool        NOT NULL        DEFAULT false
  -- Rastreabilidade
  origin_kind        text        NOT NULL DEFAULT 'editorial'
                                    -- system | editorial | provider_promoted | community_approved
  -- Auditoria editorial: aponta para local_users.id (uuid), não para DID.
  -- Permite rastrear quem criou/aprovou sem depender de infraestrutura ATProto.
  created_by_user_id uuid                    FK → identity.local_users.id
  approved_by_user_id uuid                   FK → identity.local_users.id  -- nullable
  approved_at        timestamptz

  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  CONSTRAINT chk_no_self_redirect CHECK (redirect_to_tag_id != id)

mugen_catalog.tag_synonyms
  -- Aliases e nomes alternativos para uma tag canônica
  id                bigserial   PK
  tag_id            bigint      NOT NULL        FK → mugen_catalog.tags.id
  synonym           text        NOT NULL
  lang              text                        -- null = agnóstico de idioma
  source_kind       text        NOT NULL    -- provider | editorial | imported
  source_provider_id text                   FK → provider_ingest.providers.id
  UNIQUE (tag_id, synonym)

-- ---------------------------------------------------------------------------
-- TABELAS DE REFS EXTERNAS (família *_external_refs)
--
-- Semântica uniforme: mapeiam entidade interna ↔ entidade externa num provider.
-- Respondem à pergunta "qual provider ID corresponde a esta entidade interna?"
-- Suportam matching, merge, reconciliação e auditoria.
-- NÃO são links navegáveis (para isso: external_links).
-- NÃO são evidência de relação (para isso: work_relation_refs).
--
-- Família:
--   work_external_refs          — works vs. providers (AniList, MangaDex…)
--   staff_person_external_refs  — pessoas de staff vs. providers
--   tag_external_refs           — tags vs. providers
--   scan_group_external_refs    — scan groups vs. providers externos
-- ---------------------------------------------------------------------------
-- REGRA: *_external_refs vs *_refs (proveniência)
--
-- *_external_refs = identidade externa oficial (entidade tem ID próprio no provider).
--   Ex: work_external_refs, staff_person_external_refs, tag_external_refs.
--
-- *_refs (ex: work_title_refs, work_description_refs, work_tag_refs, work_relation_refs)
-- = evidência de proveniência (dado não tem ID próprio no provider, veio do payload).
--   Ex: um título ou descrição não possui ID externo, mas precisa de rastreio de origem.
--
-- Em resumo:
--   - tem ID próprio no provider → *_external_refs
--   - não tem ID próprio → *_refs (proveniência)
-- ---------------------------------------------------------------------------

mugen_catalog.work_external_refs
  id                bigserial   PK
  work_id           bigint      NOT NULL    FK → mugen_catalog.works.id
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  external_id       text        NOT NULL
  external_slug     text
  raw_work_id       bigint                  FK → provider_ingest.raw_works.id
  is_primary_source bool        NOT NULL    DEFAULT false
  linked_by         text        NOT NULL    DEFAULT 'auto'
                                            -- auto | editorial | imported
  linked_by_user_id uuid                    FK → identity.local_users.id
  linked_at         timestamptz NOT NULL
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  UNIQUE (provider_id, external_id)

mugen_catalog.staff_person_external_refs
  -- Vínculo oficial entre uma pessoa canônica e seus IDs em providers externos.
  id                bigserial   PK
  person_id         bigint      NOT NULL    FK → mugen_catalog.staff_people.id
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  external_id       text        NOT NULL
  external_slug     text
  external_name     text        NOT NULL    -- nome como aparece no provider
  is_primary_source bool        NOT NULL    DEFAULT false
  linked_by         text        NOT NULL    DEFAULT 'auto'
                                            -- auto | editorial | imported
  linked_by_user_id uuid                    FK → identity.local_users.id
  linked_at         timestamptz NOT NULL
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  UNIQUE (provider_id, external_id)

mugen_catalog.tag_external_refs
  -- Vínculo entre tag canônica e sua representação num provider externo.
  id                bigserial   PK
  tag_id            bigint      NOT NULL    FK → mugen_catalog.tags.id
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  external_id       text
  external_slug     text
  raw_name          text        NOT NULL
  raw_category      text
  linked_by         text        NOT NULL    DEFAULT 'auto'
                                            -- auto | editorial | imported
  linked_by_user_id uuid                    FK → identity.local_users.id
  linked_at         timestamptz NOT NULL
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  UNIQUE (provider_id, raw_name)

mugen_catalog.scan_group_external_refs
  -- Vínculo entre scan group interno e seus IDs em providers externos.
  -- ex: scan group identificado no MangaDex com external_id = "grupo-xyz"
  id                bigserial   PK
  scan_group_id     bigint      NOT NULL    FK → mugen_catalog.scan_groups.id
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  external_id       text        NOT NULL
  external_slug     text                    -- ex: slug amigável no MangaDex
  linked_by         text        NOT NULL    DEFAULT 'auto'
                                            -- auto | editorial | imported
  linked_by_user_id uuid                    FK → identity.local_users.id
  linked_at         timestamptz NOT NULL
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  UNIQUE (scan_group_id, provider_id, external_id)
  UNIQUE (provider_id, external_id)

mugen_catalog.work_tags
  work_id           bigint      NOT NULL    FK → mugen_catalog.works.id
  tag_id            bigint      NOT NULL    FK → mugen_catalog.tags.id

  weight            numeric(6,3)       NOT NULL    DEFAULT 1.0
  is_spoiler         bool        NOT NULL DEFAULT false
  is_primary         bool        NOT NULL DEFAULT false
  confidence         numeric(6,3)

  created_at         timestamptz NOT NULL    DEFAULT now()
  updated_at         timestamptz NOT NULL
  PRIMARY KEY (work_id, tag_id)

-- Evidências de tags por provider (proveniência).
mugen_catalog.work_tag_refs
  id                bigserial   PK
  work_id           bigint      NOT NULL    FK → mugen_catalog.works.id
  tag_id            bigint      NOT NULL    FK → mugen_catalog.tags.id
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  source_external_id text       NOT NULL    -- id da obra no provider
  raw_work_id       bigint                  FK → provider_ingest.raw_works.id
  weight            numeric(6,3) NOT NULL    DEFAULT 1.0
  is_spoiler         bool        NOT NULL DEFAULT false
  is_primary         bool        NOT NULL DEFAULT false
  confidence         numeric(6,3)
  created_at         timestamptz NOT NULL    DEFAULT now()
  updated_at         timestamptz NOT NULL
  UNIQUE (work_id, tag_id, provider_id)

mugen_catalog.scan_group_publications
  -- FATO OBSERVADO: o Mugen detectou que este scan group publicou esta série
  -- via firehose (record org.mugenx.catalog.series com subject relevante).
  -- Não implica que o Mugen reconciliou com um work canônico.
  id                bigserial   PK
  scan_actor_did    text        NOT NULL        FK → identity.actors.did
  scan_series_at_uri text       NOT NULL        -- AT URI do record federado da série
  scan_series_cid   text        NOT NULL
  first_seen_at     timestamptz NOT NULL
  last_seen_at      timestamptz NOT NULL
  is_active         bool        NOT NULL        DEFAULT true
  UNIQUE (scan_actor_did, scan_series_at_uri)

mugen_catalog.work_scan_claims
  -- CLAIM EDITORIAL: o Mugen decidiu (auto ou manualmente) que a série de
  -- uma scan corresponde a um work canônico específico.
  -- É uma decisão editorial do Mugen, não um fato bruto da federação.
  id                bigserial   PK
  work_id           bigint      NOT NULL        FK → mugen_catalog.works.id
  publication_id    bigint      NOT NULL        FK → mugen_catalog.scan_group_publications.id
  confidence        float       NOT NULL        DEFAULT 1.0  -- 0.0 a 1.0
  match_method      text        NOT NULL        -- auto_exact | auto_fuzzy | editorial | community
  status            text        NOT NULL        -- active | disputed | rejected
  -- Auditoria: quem tomou a decisão editorial. local_users.id para suportar
  -- bootstrap sem DID ATProto. Null para decisões automáticas (auto_exact/auto_fuzzy).
  decided_by_user_id uuid                       FK → identity.local_users.id  -- null = decisão automática
  decided_at        timestamptz NOT NULL
  UNIQUE (work_id, publication_id)

mugen_catalog.work_stats
  -- Contadores agregados derivados do schema activity e de content.posts.
  -- Nunca escrito diretamente — reconstruído a partir de activity.* e graph.*.
  -- Não contém DIDs de usuário: é uma visão numérica pura do catálogo.
  work_id           bigint      PK          FK → mugen_catalog.works.id
  view_count        bigint      NOT NULL    DEFAULT 0
  follow_count      int         NOT NULL    DEFAULT 0   -- de activity.work_list_entries
  review_count      int         NOT NULL    DEFAULT 0   -- de activity.work_reviews
  read_count        int         NOT NULL    DEFAULT 0   -- de activity.work_read_status (public)
  comment_count     int         NOT NULL    DEFAULT 0
  rating_avg        int
  rating_count      int
  global_rank       int
  trending_score    float
  updated_at        timestamptz NOT NULL

-- ---------------------------------------------------------------------------
-- VOLUMES
-- Entidade própria para obras que têm volumes numerados.
-- Permite tankobon, digital, omnibus, volumes especiais.
-- Nullable: obras sem estrutura de volume (webtoons, oneshots) não criam rows.
-- ---------------------------------------------------------------------------

mugen_catalog.volumes
  id                bigserial   PK
  work_id           bigint      NOT NULL    FK → mugen_catalog.works.id
  volume_number     numeric(8,2)            -- null = volume especial sem número
  display_number    text        NOT NULL    -- "1", "2", "Special", "Omnibus 1"
  canonical_title   text
  published_at      timestamptz
  cover_blob_cid    text                    FK → blob.blobs.cid
  created_at        timestamptz NOT NULL
  updated_at        timestamptz NOT NULL
  UNIQUE (work_id, volume_number)           -- NULL não viola UNIQUE no Postgres

-- ---------------------------------------------------------------------------
-- CAPÍTULOS CANÔNICOS
-- ---------------------------------------------------------------------------

mugen_catalog.chapters
  -- Capítulo canônico reconciliado. Um capítulo canônico pode ter múltiplas
  -- fontes (um provider + várias scans em idiomas diferentes).
  id                bigserial   PK
  work_id           bigint      NOT NULL    FK → mugen_catalog.works.id
  volume_id         bigint                  FK → mugen_catalog.volumes.id
  -- Numeração canônica do capítulo.
  -- chapter_key: identificador editorial estável para ordenação e referência.
  --   Ex: "001", "001.5", "special-1", "oneshot", "ex-2"
  -- sort_number: numeric para ordenação numérica quando aplicável.
  -- display_number: como exibir na UI ("1", "1.5", "Extra 1", "Oneshot")
  chapter_key       text        NOT NULL    -- slug editorial estável
  sort_number       numeric(10,3)           -- null para capítulos sem ordem numérica
  display_number    text        NOT NULL    -- texto de exibição na UI
  canonical_title   text
  status            text        NOT NULL    DEFAULT 'available'
                                            -- available | missing | licensed_out
  first_released_at timestamptz
  created_at        timestamptz NOT NULL
  updated_at        timestamptz NOT NULL
  UNIQUE (work_id, chapter_key)

mugen_catalog.chapter_external_refs
  -- Vínculo canônico ↔ provider (mesmo padrão de work_external_refs).
  id                bigserial   PK
  chapter_id        bigint      NOT NULL    FK → mugen_catalog.chapters.id
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  external_id       text        NOT NULL
  external_slug     text
  raw_chapter_id    bigint                  FK → provider_ingest.raw_chapters.id
  lang              text        NOT NULL
  published_at      timestamptz
  is_primary        bool        NOT NULL    DEFAULT false
  linked_by         text        NOT NULL    DEFAULT 'auto'
  linked_at         timestamptz NOT NULL
  created_at        timestamptz NOT NULL
  updated_at        timestamptz NOT NULL

CREATE UNIQUE INDEX uq_chapter_external_refs_primary_per_lang
  ON mugen_catalog.chapter_external_refs (chapter_id, lang)
  WHERE is_primary = true;

-- ---------------------------------------------------------------------------
-- SCAN GROUPS COMO ENTIDADE CANÔNICA
-- ---------------------------------------------------------------------------

mugen_catalog.scan_groups
  id                bigserial   PK
  actor_did         text                    FK → identity.actors.did  -- nullable
  display_name      text        NOT NULL
  short_name        text
  description       text
  website_url       text
  is_active         bool        NOT NULL    DEFAULT true
  primary_lang      text
  languages         text[]      NOT NULL    DEFAULT '{}'
  source_of_truth   text        NOT NULL    DEFAULT 'provider'
                                            -- atproto | manual | provider
  created_at        timestamptz NOT NULL
  updated_at        timestamptz NOT NULL

-- ---------------------------------------------------------------------------
-- STAFF
-- ---------------------------------------------------------------------------

mugen_catalog.chapter_scanlations
  id                bigserial   PK
  chapter_id        bigint      NOT NULL    FK → mugen_catalog.chapters.id
  scan_group_id     bigint      NOT NULL    FK → mugen_catalog.scan_groups.id
  raw_chapter_id    bigint                  FK → provider_ingest.raw_chapters.id
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  lang              text
  published_at      timestamptz
  created_at        timestamptz NOT NULL

mugen_catalog.scan_group_staff
  id                bigserial   PK
  scan_group_id     bigint      NOT NULL    FK → mugen_catalog.scan_groups.id
  member_did        text                    FK → identity.actors.did  -- nullable
                                -- vínculo com ator ATProto; null para membros sem DID conhecido
  display_name      text        NOT NULL
  role              text        NOT NULL    -- leader | translator | letterer | typesetter | qa
  is_active         bool        NOT NULL    DEFAULT true
  joined_at         timestamptz
  source            text        NOT NULL    -- atproto | manual
```

**Índices:**
```sql
CREATE INDEX ON mugen_catalog.work_titles (work_id, lang);
CREATE INDEX ON mugen_catalog.work_titles (title) WHERE is_primary = true;
CREATE INDEX ON mugen_catalog.work_title_refs (work_id);
CREATE INDEX ON mugen_catalog.work_title_refs (provider_id, source_external_id);
CREATE INDEX ON mugen_catalog.work_description_refs (work_id);
CREATE INDEX ON mugen_catalog.work_description_refs (provider_id, source_external_id);
CREATE INDEX ON mugen_catalog.work_metadata_refs (work_id);
CREATE INDEX ON mugen_catalog.work_metadata_refs (provider_id, source_external_id);
CREATE INDEX ON mugen_catalog.work_staff (work_id);
CREATE INDEX ON mugen_catalog.work_staff (person_id);
CREATE INDEX ON mugen_catalog.work_tags (tag_id);
CREATE INDEX ON mugen_catalog.work_tag_refs (work_id);
CREATE INDEX ON mugen_catalog.work_tag_refs (tag_id);
CREATE INDEX ON mugen_catalog.work_tag_refs (provider_id, source_external_id);
CREATE INDEX ON mugen_catalog.scan_group_publications (scan_actor_did);
CREATE INDEX ON mugen_catalog.work_scan_claims (work_id, status);

-- Chapters canônicos
CREATE INDEX ON mugen_catalog.chapters (work_id, sort_number NULLS LAST);
CREATE INDEX ON mugen_catalog.chapters (volume_id) WHERE volume_id IS NOT NULL;

-- chapter_external_refs
CREATE UNIQUE INDEX uq_chapter_external_refs_provider
  ON mugen_catalog.chapter_external_refs (provider_id, external_id);
CREATE UNIQUE INDEX uq_chapter_external_refs_raw_to_one_canonical
  ON mugen_catalog.chapter_external_refs (raw_chapter_id)
  WHERE raw_chapter_id IS NOT NULL;
CREATE UNIQUE INDEX uq_chapter_external_refs_primary_per_lang
  ON mugen_catalog.chapter_external_refs (chapter_id, lang)
  WHERE is_primary = true;
CREATE INDEX ON mugen_catalog.chapter_external_refs (chapter_id, lang, is_primary);
CREATE INDEX ON mugen_catalog.chapter_external_refs (provider_id, external_id);

-- Scan groups
CREATE INDEX ON mugen_catalog.scan_groups (primary_lang);

-- Refs externas (família *_external_refs)
CREATE INDEX ON mugen_catalog.work_external_refs (work_id);
CREATE INDEX ON mugen_catalog.work_external_refs (provider_id, external_id);
CREATE INDEX ON mugen_catalog.staff_person_external_refs (person_id);
CREATE INDEX ON mugen_catalog.staff_person_external_refs (provider_id, external_id);
CREATE INDEX ON mugen_catalog.tag_external_refs (tag_id);
CREATE INDEX ON mugen_catalog.tag_external_refs (provider_id, raw_name);
CREATE INDEX ON mugen_catalog.scan_group_external_refs (scan_group_id);
CREATE INDEX ON mugen_catalog.scan_group_external_refs (provider_id, external_id);

-- Staff
CREATE INDEX ON mugen_catalog.chapter_scanlations (chapter_id);
CREATE INDEX ON mugen_catalog.chapter_scanlations (scan_group_id);
CREATE INDEX ON mugen_catalog.scan_group_staff (scan_group_id, is_active);
CREATE INDEX ON mugen_catalog.scan_group_staff (member_did) WHERE member_did IS NOT NULL;
```

---

### 3.2 `provider_ingest` — Ingestão de providers externos

```sql
provider_ingest.providers
  id                text        PK          -- 'anilist' | 'mangadex' | 'scan:xyz'
  name              text        NOT NULL
  base_url          text        NOT NULL
  provider_kind     text        NOT NULL    -- external_api | mugenx_instance | atproto_feed
  rate_limit_rps    int
  is_active         bool        NOT NULL    DEFAULT true
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL

provider_ingest.sync_state_global
  -- Estado de varredura global do provider (cursor incremental).
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  resource_kind     text        NOT NULL    -- works | chapters | staff | tags
  last_cursor       text
  last_run_at       timestamptz
  next_run_at       timestamptz
  status            text        NOT NULL    DEFAULT 'idle'
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  PRIMARY KEY (provider_id, resource_kind)

provider_ingest.entity_sync_state
  -- Agendamento fino por entidade (principalmente por obra).
  provider_id         text        NOT NULL REFERENCES provider_ingest.providers(id)
  resource_kind       text        NOT NULL    -- work | chapter | staff | tag
  external_id         text        NOT NULL
  parent_external_id  text
  priority            integer     NOT NULL    DEFAULT 100
  last_run_at         timestamptz
  last_success_at     timestamptz
  next_run_at         timestamptz NOT NULL
  status              text        NOT NULL    DEFAULT 'idle'
  failure_count       integer     NOT NULL    DEFAULT 0
  sync_reason         text        NOT NULL    DEFAULT 'refresh'
  last_error_code     text
  last_error_message  text
  created_at          timestamptz NOT NULL    DEFAULT now()
  updated_at          timestamptz NOT NULL
  PRIMARY KEY (provider_id, resource_kind, external_id)

provider_ingest.raw_works
  id                bigserial   PK
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  external_id       text        NOT NULL
  external_slug     text
  raw_json          jsonb       NOT NULL
  fetched_at        timestamptz NOT NULL
  ingest_status     text        NOT NULL    DEFAULT 'fetched'
                                            -- fetched | parsed | failed
  -- Estado operacional do pipeline de matching.
  -- matched_work_id é saída do pipeline de reconciliação, não vínculo oficial.
  -- O vínculo oficial é work_external_refs (ver mugen_catalog).
  matched_work_id   bigint                  FK → mugen_catalog.works.id
  match_status      text        NOT NULL    DEFAULT 'unmatched'
                                            -- unmatched | matched | conflict | rejected
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  UNIQUE (provider_id, external_id)

provider_ingest.raw_chapters
  id                bigserial   PK
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  external_id       text        NOT NULL
  external_slug     text
  raw_work_id       bigint                  FK → provider_ingest.raw_works.id
  raw_json          jsonb       NOT NULL
  fetched_at        timestamptz NOT NULL
  ingest_status     text        NOT NULL    DEFAULT 'fetched'
                                            -- fetched | parsed | failed
  -- Estado operacional do pipeline de matching.
  -- matched_chapter_id é saída do pipeline, não vínculo oficial.
  -- O vínculo oficial é chapter_external_refs.
  matched_chapter_id bigint                 FK → mugen_catalog.chapters.id
  match_status      text        NOT NULL    DEFAULT 'unmatched'
                                            -- unmatched | matched | conflict | rejected
  UNIQUE (provider_id, external_id)

provider_ingest.raw_tags
  id                bigserial   PK
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  external_id       text
  raw_name          text        NOT NULL
  raw_category      text
  raw_json          jsonb
  fetched_at        timestamptz NOT NULL
  created_at        timestamptz NOT NULL    DEFAULT now()
  updated_at        timestamptz NOT NULL
  UNIQUE (provider_id, raw_name)

provider_ingest.raw_staff_people
  -- Staff vindo de providers (AniList, MangaDex) antes de reconciliação.
  -- Análogo a raw_works: dado bruto que pode ser mesclado em staff_people canônico.
  id                bigserial   PK
  provider_id       text        NOT NULL    FK → provider_ingest.providers.id
  external_id       text        NOT NULL
  raw_json          jsonb       NOT NULL
  fetched_at        timestamptz NOT NULL
  ingest_status     text        NOT NULL    DEFAULT 'fetched'
  -- Estado operacional do pipeline de matching.
  -- matched_person_id é saída do pipeline, não vínculo oficial.
  -- O vínculo oficial é staff_person_external_refs (ver mugen_catalog).
  matched_person_id bigint                  FK → mugen_catalog.staff_people.id
  match_status      text        NOT NULL    DEFAULT 'unmatched'
  UNIQUE (provider_id, external_id)

provider_ingest.merge_decisions
  id                    bigserial   PK
  decision_kind         text        NOT NULL    -- auto | editorial
  decision_status       text        NOT NULL    DEFAULT 'accepted'
                                                -- accepted | rejected | superseded | reverted
  operation_kind        text        NOT NULL    -- attach | detach | reject | remap
  catalog_work_id       bigint      NOT NULL    FK → mugen_catalog.works.id
  provider_id           text        NOT NULL    FK → provider_ingest.providers.id
  external_id           text        NOT NULL
  raw_work_id           bigint                  FK → provider_ingest.raw_works.id
  rationale             text
  decided_by_user_id    uuid                    FK → identity.local_users.id
  decided_at            timestamptz NOT NULL
  confidence            numeric(6,3)
  supersedes_decision_id bigint                 FK → provider_ingest.merge_decisions.id

  CONSTRAINT chk_merge_decisions_confidence
    CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1))
```

---

### 3.3 `mugen_index` — Índices de busca e ranking global

```sql
mugen_index.work_search_docs
  work_id           bigint      PK          FK → mugen_catalog.works.id
  search_vector     tsvector    NOT NULL
  title_tokens      text[]
  tag_slugs         text[]
  providers         text[]
  updated_at        timestamptz NOT NULL

mugen_index.chapter_release_index
  -- Índice de lançamentos para o feed de novidades e notificações.
  -- Aponta para chapter_scanlations porque o que interessa
  -- para o feed é "qual scan lançou qual capítulo em qual idioma".
  id                bigserial   PK
  work_id           bigint      NOT NULL    FK → mugen_catalog.works.id
  chapter_id        bigint      NOT NULL    FK → mugen_catalog.chapters.id
  chapter_scanlation_id bigint  NOT NULL    FK → mugen_catalog.chapter_scanlations.id
  scan_group_id     bigint                  -- nulo se fonte é provider, não scan
  chapter_key       text        NOT NULL    -- ex: "042", "042.5", "special-1"
  sort_number       numeric(10,3)           -- para ordenação numérica
  lang              text        NOT NULL
  released_at       timestamptz
  indexed_at        timestamptz NOT NULL

mugen_index.search_queries
  id                bigserial   PK
  actor_did         text
  query_text        text        NOT NULL
  results_count     int
  clicked_work_id   bigint
  session_id        uuid
  created_at        timestamptz NOT NULL
```

**Índices:**
```sql
CREATE INDEX ON mugen_index.work_search_docs USING GIN (search_vector);
CREATE INDEX ON mugen_index.chapter_release_index (work_id, released_at DESC);
CREATE INDEX ON mugen_index.chapter_release_index (chapter_id);
CREATE INDEX ON mugen_index.chapter_release_index (chapter_scanlation_id);
CREATE INDEX ON mugen_index.chapter_release_index (scan_group_id, released_at DESC)
  WHERE scan_group_id IS NOT NULL;
```

---

### 3.4 `mugen_feed` — Feed materializado

```sql
mugen_feed.snapshots
  id                bigserial   PK
  actor_did         text        NOT NULL
  feed_kind         text        NOT NULL    -- home | following | discover | work
  item_uri          text        NOT NULL    -- AT URI do post/record
  item_score        float       NOT NULL    DEFAULT 0
  item_reason       text                    -- 'follow' | 'trending' | 'recommended'
  inserted_at       timestamptz NOT NULL
  expires_at        timestamptz

mugen_feed.generation_runs
  id                bigserial   PK
  actor_did         text        NOT NULL
  feed_kind         text        NOT NULL
  started_at        timestamptz NOT NULL
  finished_at       timestamptz
  items_generated   int
  status            text        NOT NULL    -- running | done | failed
```

**Índices:**
```sql
CREATE INDEX ON mugen_feed.snapshots (actor_did, feed_kind, item_score DESC);
CREATE INDEX ON mugen_feed.snapshots (expires_at);
```

---

### 3.5 `mugen_ai` — Embeddings, NLP, summaries

```sql
mugen_ai.work_embeddings
  work_id           bigint      NOT NULL    FK → mugen_catalog.works.id
  model_id          text        NOT NULL
  field             text        NOT NULL    -- title | description | tags | combined
  vector            vector(1536)            -- pgvector
  created_at        timestamptz NOT NULL
  PRIMARY KEY (work_id, model_id, field)

mugen_ai.chapter_embeddings
  chapter_id        bigint      NOT NULL    FK → mugen_catalog.chapters.id
  model_id          text        NOT NULL
  field             text        NOT NULL
  vector            vector(1536)
  created_at        timestamptz NOT NULL
  PRIMARY KEY (chapter_id, model_id, field)

mugen_ai.thread_summaries
  id                bigserial   PK
  root_uri          text        NOT NULL
  model_id          text        NOT NULL
  summary_text      text        NOT NULL
  version           int         NOT NULL    DEFAULT 1
  created_at        timestamptz NOT NULL
  UNIQUE (root_uri, model_id, version)
```

---

### 3.6 `mugen_realtime` — Mensagens e sessões síncronas

Realtime não é federado via ATProto. É infra interna de estado efêmero.

```sql
mugen_realtime.channels
  id                uuid        PK
  owner_group_id    uuid
  name              text        NOT NULL
  kind              text        NOT NULL    -- text | announcement | reading_session
  created_at        timestamptz NOT NULL

mugen_realtime.messages
  id                bigserial   PK
  channel_id        uuid        NOT NULL    FK → mugen_realtime.channels.id
  author_did        text        NOT NULL
  content_text      text
  content_json      jsonb
  reply_to_id       bigint                  FK → mugen_realtime.messages.id
  created_at        timestamptz NOT NULL
  edited_at         timestamptz
  is_deleted        bool        NOT NULL    DEFAULT false

mugen_realtime.reading_sessions
  id                uuid        PK
  chapter_at_uri    text        NOT NULL
  host_did          text        NOT NULL
  control_mode      text        NOT NULL    -- host | collaborative | free
  status            text        NOT NULL    -- active | paused | ended
  started_at        timestamptz NOT NULL
  ended_at          timestamptz
  max_participants  int

mugen_realtime.reading_session_participants
  session_id        uuid        NOT NULL    FK → mugen_realtime.reading_sessions.id
  did               text        NOT NULL
  current_page      int         NOT NULL    DEFAULT 1
  joined_at         timestamptz NOT NULL
  left_at           timestamptz
  PRIMARY KEY (session_id, did)
```

---

### 3.7 `mugen_moderation` — Workflow avançado de moderação

```sql
mugen_moderation.work_submissions
  id                bigserial   PK
  submitter_did     text        NOT NULL
  proposed_work_json jsonb      NOT NULL
  status            text        NOT NULL    DEFAULT 'pending'
  reviewer_did      text
  review_notes      text
  submitted_at      timestamptz NOT NULL
  reviewed_at       timestamptz

mugen_moderation.verification_requests
  id                bigserial   PK
  requester_did     text        NOT NULL
  claim_kind        text        NOT NULL    -- staff_person | scan_group_owner
  evidence_json     jsonb
  status            text        NOT NULL    DEFAULT 'pending'
  reviewer_did      text
  created_at        timestamptz NOT NULL
  resolved_at       timestamptz
```

---

### 3.8 `mugen_ops` — Pipeline operacional do Mugen

```sql
mugen_ops.federation_publish_queue
  id                bigserial   PK
  record_kind       text        NOT NULL    -- work_claim | editorial_list | service_profile
  local_id          text        NOT NULL
  action            text        NOT NULL    -- create | update | delete
  payload_json      jsonb
  status            text        NOT NULL    DEFAULT 'pending'
                                            -- pending | published | failed | skipped
  attempts          int         NOT NULL    DEFAULT 0
  last_error        text
  published_at_uri  text
  created_at        timestamptz NOT NULL
  processed_at      timestamptz

mugen_ops.editorial_assets
  -- Assets editoriais internos do Mugen: covers canônicas, thumbnails de obras,
  -- imagens recortadas/padronizadas que NÃO são blobs ATProto.
  -- Fonte: providers externos, moderação editorial, NLP pipelines.
  id                bigserial   PK
  subject_kind      text        NOT NULL    -- work | person | tag | scan_group
  subject_id        text        NOT NULL    -- ID interno do subject
  asset_kind        text        NOT NULL    -- cover | thumbnail | banner | portrait
  variant_size      text        NOT NULL    DEFAULT 'original'
                                            -- original | sm | md | lg
  variant_format    text        NOT NULL    DEFAULT 'webp'
                                            -- webp | avif | jpg | png
  storage_key       text        NOT NULL    -- chave no R2/CDN editorial do Mugen
  width             int
  height            int
  mime_type         text        NOT NULL
  source_provider   text                    -- 'anilist' | 'mangadex' | 'manual' | 'nlp'
  source_url        text
  created_at        timestamptz NOT NULL
  UNIQUE (subject_kind, subject_id, asset_kind, variant_size, variant_format)

mugen_ops.ingest_jobs
  id                uuid        PK
  job_kind          text        NOT NULL
                                -- ingest_provider | index_work | merge_candidate
                                -- enrich_nlp | generate_feed | reindex_search
  payload_json      jsonb       NOT NULL
  status            text        NOT NULL    DEFAULT 'queued'
                                            -- queued | running | done | failed | retrying
  priority          int         NOT NULL    DEFAULT 5
  attempts          int         NOT NULL    DEFAULT 0
  max_attempts      int         NOT NULL    DEFAULT 3
  last_error        text
  scheduled_at      timestamptz NOT NULL    DEFAULT now()
  started_at        timestamptz
  completed_at      timestamptz

mugen_ops.instance_settings
  key               text        PK
  value_json        jsonb       NOT NULL
  updated_at        timestamptz NOT NULL
```

**Índices:**
```sql
CREATE INDEX ON mugen_ops.federation_publish_queue (status, created_at)
  WHERE status IN ('pending', 'failed');
CREATE INDEX ON mugen_ops.editorial_assets (subject_kind, subject_id);
CREATE INDEX ON mugen_ops.ingest_jobs (status, priority, scheduled_at)
  WHERE status IN ('queued', 'retrying');
```

---

## 4. Schemas Exclusivos do mugenx

### 4.1 `scan_catalog` — Catálogo autoritativo da scan

```sql
scan_catalog.series
  id                uuid        PK
  slug              text        UNIQUE NOT NULL
  primary_title     text        NOT NULL
  description       text
  cover_blob_cid    text                    FK → blob.blobs.cid
  content_rating    text        NOT NULL    DEFAULT 'safe'
  status            text        NOT NULL    -- ongoing | completed | hiatus | dropped
  language          text        NOT NULL    DEFAULT 'pt'
  record_at_uri     text        UNIQUE
  record_cid        text
  federation_state  text        NOT NULL    DEFAULT 'draft'
                                            -- draft | published | unlisted | takendown
  created_at        timestamptz NOT NULL
  updated_at        timestamptz NOT NULL

scan_catalog.series_credits
  id                uuid   PK
  series_id         uuid        NOT NULL    FK → scan_catalog.series.id
  contributor_did   text                    FK → identity.actors.did
  display_name      text        NOT NULL
  role              text        NOT NULL    -- translation | lettering | quality_check
                                            -- typesetting | proofreading | scanning
  is_primary        bool        NOT NULL    DEFAULT false

scan_catalog.chapters
  id                uuid        PK
  series_id         uuid        NOT NULL    FK → scan_catalog.series.id
  chapter_key       text        NOT NULL
  sort_number       numeric(10,3) NOT NULL
  display_number    text        NOT NULL
  volume            text        NOT NULL    DEFAULT ''
  title             text
  lang              text        NOT NULL    DEFAULT 'pt'
  published_at      timestamptz
  record_at_uri     text        UNIQUE
  record_cid        text
  canonical_chapter_uri text               -- FK lógica → canonical.chapters.at_uri
  federation_state  text        NOT NULL    DEFAULT 'draft'
                                -- draft | publishing | published | failed
  created_at        timestamptz NOT NULL
  UNIQUE (series_id, chapter_key, lang)

scan_catalog.chapter_pages
  id                bigserial   PK
  chapter_id        uuid        NOT NULL    FK → scan_catalog.chapters.id
  page_number       int         NOT NULL
  asset_id          uuid        NOT NULL    FK → scan_storage.assets.id
  width             int
  height            int
  UNIQUE (chapter_id, page_number)

scan_storage.assets
  id                uuid        PK
  storage_key       text        UNIQUE NOT NULL
  checksum_sha256   text        NOT NULL
  mime_type         text        NOT NULL
  size_bytes        bigint      NOT NULL
  width             int
  height            int
  availability      text        NOT NULL    DEFAULT 'available'
                                            -- available | processing | failed | deleted
  created_at        timestamptz NOT NULL

scan_catalog.chapter_read_state
  did               text        NOT NULL
  chapter_id        uuid        NOT NULL    FK → scan_catalog.chapters.id
  last_page         int         NOT NULL    DEFAULT 1
  completed         bool        NOT NULL    DEFAULT false
  started_at        timestamptz NOT NULL
  updated_at        timestamptz NOT NULL
  PRIMARY KEY (did, chapter_id)

scan_catalog.comments_projection
  post_at_uri       text        PK          FK → content.posts.record_at_uri
  subject_kind      text        NOT NULL    -- series | chapter
  series_id         uuid                    FK → scan_catalog.series.id
  chapter_id        uuid                    FK → scan_catalog.chapters.id
  author_did        text        NOT NULL
  text_preview      text
  created_at        timestamptz NOT NULL
  indexed_at        timestamptz NOT NULL
  is_hidden         bool        NOT NULL    DEFAULT false
```

**Índices:**
```sql
CREATE INDEX ON scan_catalog.series (slug);
CREATE INDEX ON scan_catalog.series (record_at_uri) WHERE record_at_uri IS NOT NULL;
CREATE INDEX ON scan_catalog.chapters (series_id, sort_number);
CREATE INDEX ON scan_catalog.chapters (series_id, chapter_key);
CREATE INDEX ON scan_catalog.chapters (canonical_chapter_uri) WHERE canonical_chapter_uri IS NOT NULL;
CREATE INDEX ON scan_catalog.comments_projection (series_id, created_at DESC)
  WHERE series_id IS NOT NULL AND is_hidden = false;
CREATE INDEX ON scan_catalog.comments_projection (chapter_id, created_at DESC)
  WHERE chapter_id IS NOT NULL AND is_hidden = false;
```

---

### 4.2 `scan_ops` — Pipeline operacional do mugenx

```sql
scan_ops.upload_jobs
  id                uuid        PK
  submitter_did     text        NOT NULL
  series_id         uuid
  chapter_id        uuid
  status            text        NOT NULL    -- uploading | processing | published | failed
  total_pages       int
  processed_pages   int         NOT NULL    DEFAULT 0
  error_message     text
  created_at        timestamptz NOT NULL
  finished_at       timestamptz

scan_ops.federation_publish_queue
  id                bigserial   PK
  record_kind       text        NOT NULL    -- series | chapter | profile | credit
  local_id          uuid        NOT NULL
  action            text        NOT NULL    -- create | update | delete
  payload_json      jsonb
  status            text        NOT NULL    DEFAULT 'pending'
  attempts          int         NOT NULL    DEFAULT 0
  last_error        text
  created_at        timestamptz NOT NULL
  processed_at      timestamptz

scan_ops.instance_settings
  key               text        PK
  value_json        jsonb       NOT NULL
  updated_at        timestamptz NOT NULL
```

---

### 4.3 `scan_moderation` — Moderação local da instância mugenx

```sql
scan_moderation.hidden_comments
  post_at_uri       text        PK
  hidden_by_did     text        NOT NULL
  reason            text
  hidden_at         timestamptz NOT NULL

scan_moderation.banned_actors
  banned_did        text        PK
  banned_by_did     text        NOT NULL
  reason            text
  banned_at         timestamptz NOT NULL
  expires_at        timestamptz

scan_moderation.reports
  id                bigserial   PK
  reporter_did      text        NOT NULL
  target_uri        text
  target_did        text
  reason            text        NOT NULL
  status            text        NOT NULL    DEFAULT 'pending'
  created_at        timestamptz NOT NULL
```

---

## 5. Lexicons ATProto — Collections

### 5.1 Catálogo canônico (namespace `org.mugens.canonical`)

| NSID | Descrição | Federado? |
|---|---|---|
| `org.mugens.canonical.work` | Identidade mínima de uma obra (com genres, demographic, content_rating) | ✅ Sim |
| `org.mugens.canonical.chapter` | Identidade mínima de um capítulo (com volume + edition separados) | ✅ Sim |
| `org.mugens.canonical.alias` | Título alternativo de uma obra | ✅ Sim |
| `org.mugens.canonical.relation` | Relação entre obras (sequel, prequel, etc.) | ✅ Sim |
| `org.mugens.canonical.external_ref` | Referência externa (AniList, MangaDex, etc.) | ✅ Sim |

### 5.2 Atividade do usuário (namespace `org.mugens.activity`)

| NSID | Descrição | Federado? |
|---|---|---|
| `org.mugens.activity.library` | Lista de leitura (reading, completed, dropped…) | ✅ Sim |
| `org.mugens.activity.chapter_progress` | Marcar capítulo canônico como lido | ✅ Sim |
| `org.mugens.activity.review` | Review escrita de uma obra | ✅ Sim |
| `org.mugens.activity.rating` | Nota numérica de uma obra (sem texto) | ✅ Sim |
| `org.mugens.activity.favorite` | Favoritar uma obra | ✅ Sim |

### 5.3 Social compartilhado (namespace `org.mugens`)

| NSID | Descrição |
|---|---|
| `org.mugens.actor.profile` | Perfil público do ator |
| `org.mugens.feed.post` | Post público |
| `org.mugens.feed.comment` | Comentário com subject (série/capítulo) |
| `org.mugens.graph.follow` | Seguir um ator |
| `org.mugens.graph.like` | Curtir um record |
| `org.mugens.graph.repost` | Repostar um record |
| `org.mugens.graph.block` | Bloquear um ator |

### 5.4 Conteúdo operacional mugenx (namespace `org.mugenx`)

| NSID | Descrição | Federado? |
|---|---|---|
| `org.mugenx.catalog.series` | Série publicada pelo scan group | ✅ Sim |
| `org.mugenx.catalog.chapter` | Capítulo (release concreta) | ✅ Sim |
| `org.mugenx.catalog.scanGroup` | Perfil/identidade do scan group | ✅ Sim |
| `org.mugenx.catalog.credit` | Crédito de tradução/lettering por capítulo | ✅ Sim |
| `org.mugenx.catalog.releaseManifest` | Payload técnico completo (páginas) | ❌ Local |

### 5.5 Editorial Mugen (namespace `org.mugens.editorial`)

| NSID | Descrição | Federado? |
|---|---|---|
| `org.mugens.editorial.workClaim` | Claim editorial de identidade entre records | ⚠️ Opcional |
| `org.mugens.editorial.list` | Listas editoriais públicas curadas | ⚠️ Opcional |

---

## 6. Fluxo: Comentário Cross-App

```
1. Usuário do Mugen cria record com.mugens.feed.comment
   com subject_uri = "at://did:scanA/org.mugenx.catalog.chapter/xyz"

2. Record é publicado no PDS do ator

3. mugenx recebe o record via firehose (ops.sync_events)

4. mugenx projeta em:
   → content.posts
   → content.comment_subjects  (subject_at_uri = AT URI do capítulo local)
   → scan_catalog.comments_projection  (chapter_id = chapters.id local)

5. mugenx exibe o comentário na página do capítulo ✅

6. Mugen indexa globalmente via content.posts e
   mugen_index.chapter_release_index ✅
```

---

## 7. Mapa de schemas por produto

```
Schema                        Mugen    mugenx   Dono
──────────────────────────────────────────────────────────────────
canonical.*                     ✅         ✅        rede (did:plc:mugens-catalog)
identity.*                      ✅         ✅        compartilhado
repo.*                          ✅         ✅        compartilhado
blob.*                          ✅         ✅        compartilhado
graph.*                         ✅         ✅        compartilhado
content.*                       ✅         ✅        compartilhado
activity.*                      ✅         ✅        usuário (PDS do ator)
label.*                         ✅         ✅        compartilhado
local.*                         ✅         ✅        compartilhado
ops.*                           ✅         ✅        compartilhado
──────────────────────────────────────────────────────────────────
mugen_catalog.*                 ✅         ❌        Mugen (AppView)
mugen_index.*                   ✅         ❌        Mugen (AppView)
mugen_feed.*                    ✅         ❌        Mugen (AppView)
mugen_ai.*                      ✅         ❌        Mugen (AppView)
mugen_realtime.*                ✅         ❌        Mugen (AppView)
mugen_moderation.*              ✅         ❌        Mugen (AppView)
mugen_ops.*                     ✅         ❌        Mugen (AppView)
provider_ingest.*               ✅         ❌
─────────────────────────────────────────────────
scan_catalog.*                  ❌         ✅
scan_storage.*                  ❌         ✅
scan_ops.*                      ❌         ✅
scan_moderation.*               ❌         ✅
```

---

## 8. Notas de Implementação

### 8.1 Identidade e autenticação
A raiz de identidade é sempre `identity.actors.did`, nunca um `user_id` interno. `identity.local_users` é a extensão privada da conta no app — não a identidade em si. Contas hospedadas localmente têm `hosting_status = 'hosted_here'`; contas remotas têm `'remote'`.

### 8.2 Records e projeções
`repo.records` é a única fonte de verdade para dados federados. `content.posts`, `graph.*` e `scan_catalog.comments_projection` são projeções que podem ser reconstruídas a partir de `repo.records` + processamento do firehose. Nunca escreva diretamente em projeções como se fossem fonte primária.

### 8.3 Catálogo federado vs. local
No mugenx, `scan_catalog.series` e `scan_catalog.chapters` têm `record_at_uri` — quando preenchido, o registro já está na federação; quando nulo, é rascunho local. A publicação é orquestrada via `scan_ops.federation_publish_queue`. No Mugen, `mugen_catalog.works` é sempre local/editorial; o vínculo com instâncias mugenx é feito em duas etapas: primeiro `mugen_catalog.scan_group_publications` (fato observado via firehose), depois `mugen_catalog.work_scan_claims` (decisão editorial de reconciliação com um work canônico).

### 8.4 Blobs ATProto vs. assets de storage local
`blob.blobs` é exclusivo para blobs que fazem parte da federação: covers publicadas pela scan junto com o record `org.mugenx.catalog.series`, avatares, banners e imagens de posts. Qualquer app que resolver o AT URI correspondente precisa conseguir exibir esse asset pelo CID.

Assets editoriais internos do Mugen ficam em `mugen_ops.editorial_assets`, com `storage_key` apontando para o R2/CDN editorial do Mugen. Não têm AT URI e não pertencem à federação.

Páginas de capítulo e assets brutos do mugenx **nunca vão para `blob.blobs`**. Eles são payload técnico local, referenciados em `scan_catalog.chapter_pages` → `scan_storage.assets`.

### 8.5 Moderação em duas camadas
Labels (`label.labels`) são a saída protocolar, interoperável e assinável. Cases (`local.moderation_cases`) são o workflow humano interno com appeals e notas privadas. O fluxo é: report chega em `label.reports_inbox` → triagem para `local.moderation_cases` → ações resultam em `label.labels` (quando protocolar) ou `local.moderation_actions` (quando só interno).

### 8.6 Estratégia de escala de `repo.records`
`repo.records` tende a crescer muito com tração. Planeje desde o início para ao menos uma dessas estratégias:

- **Particionamento por tempo** (`PARTITION BY RANGE (indexed_at)`) — mais simples, facilita arquivamento de dados antigos.
- **Particionamento por `collection`** — útil se volumes por tipo forem muito desiguais.
- **Separação de storage quente/frio** — `record_json` completo pode migrar para object storage após N dias; o banco mantém apenas campos indexados.

A projeção em `content.posts` e `graph.*` é justamente o que permite que queries de UI nunca precisem full-scan em `repo.records`.

### 8.7 O que não implementar agora
Este documento é a **arquitetura-alvo**, não um checklist de implementação imediata. Os cinco fluxos críticos que provam o núcleo são:

1. mugenx publica série e capítulo como records ATProto
2. Mugen indexa esses records e exibe catálogo mínimo
3. Usuário comenta num capítulo usando `subject_uri` com AT URI estável
4. mugenx recebe o comentário via firehose e projeta em `comments_projection`
5. Mugen reconcilia série de scan com work canônico via `scan_group_publications` → `work_scan_claims`

### 8.8 Família de tabelas `*_external_refs` em `mugen_catalog`

A família `*_external_refs` segue um padrão uniforme de naming e shape. Todas as tabelas respondem à mesma pergunta: **"qual entidade externa corresponde a esta entidade interna num dado provider?"** São o núcleo de matching, reconciliação e auditoria de cada tipo de entidade.

**Membros da família:**

- `work_external_refs` — works vs. providers (AniList, MangaDex…)
- `staff_person_external_refs` — pessoas de staff vs. providers
- `tag_external_refs` — tags vs. providers
- `scan_group_external_refs` — scan groups vs. providers externos

**O que não é `*_external_refs`:**

- `external_links` — links navegáveis para UX (lojas, sites oficiais, editoras). Responde "qual link mostrar ao usuário?", não "qual ID externo é este work?".
- `work_relation_refs` — evidência externa de uma relação entre dois works internos. Responde "de onde veio a evidência desta relação?".

**Campos `matched_*_id` em `provider_ingest.raw_*`** são saída do pipeline de matching, nunca vínculo oficial. O vínculo oficial fica sempre nas tabelas `*_external_refs`.

### 8.9 Chapters, volumes e staff no Mugen

**Volumes como entidade própria:** `mugen_catalog.volumes` existe para obras que têm estrutura de volumes reais. Obras sem volumes (webtoons, oneshots) simplesmente não criam rows — `chapters.volume_id` fica nulo.

**Numeração de capítulos — três campos complementares:** `chapter_key` é o identificador editorial estável (slug imutável). `sort_number` é `numeric(10,3)` para ordenação correta sem problemas de float. `display_number` é o texto de exibição na UI.

**Dois níveis de staff de scan:**
- `chapter_scanlations` — quem publicou a release (scan group) por capítulo.
- `scan_group_staff` — membros do grupo.

Um membro pode estar em `scan_group_staff` sem aparecer em `chapter_scanlations` e vice-versa.

### 8.10 Separação entre catálogo, atividade do usuário e estado local

| Pergunta | Schema |
|---|---|
| "O que existe nesta obra?" (títulos, staff, capítulos, tags) | `mugen_catalog` — sem DIDs de usuário |
| "O que o usuário fez com esta obra?" (leu, avaliou, listou) | `activity` — federado no PDS, público por padrão |
| "Onde o usuário parou na leitura?" (última página, timestamp) | `local.reading_progress` — privado, nunca federado |
| "O usuário curtiu um post sobre esta obra?" | `graph.likes` — federado, é sobre o record, não sobre a obra |

**`mugen_catalog` não tem DIDs de usuário.** `work_stats` é a única tabela do catálogo que deriva de atividade, e ela contém apenas contadores agregados.

**`activity` é federado, portável e compartilhado entre Mugen e mugenx.** O `subject_at_uri` no record é o elo — aponta para o AT URI da série ou da obra publicada, que qualquer AppView sabe resolver.

**`local.reading_progress` é a única exceção intencional** — progresso de página é privado por natureza e não há benefício em federar.
