# Estrutura de Repositório — Monorepo Mugen & mugenx (Elixir Umbrella)

---

## 1. Visão Geral

```text
mugen-umbrella/
├── apps/
│   ├── mugenx/            ← core compartilhado (licença permissiva: MIT ou Apache-2.0)
│   ├── mugen/             ← app OTP do domínio Mugen
│   ├── mugen_web/         ← Phoenix app/API do Mugen
│   ├── mugen_publisher/   ← app OTP do domínio do produto mugenx
│   ├── mugen_publisher_web/        ← Phoenix app/API do mugenx
│   ├── mugen_ingest/      ← workers e pipelines de ingest do Mugen
│   ├── mugen_realtime/    ← realtime/chat/presence/sessões síncronas
│   ├── mugen_feed/        ← geração/materialização de feeds
│   ├── mugen_ai/          ← embeddings, summaries, NLP workers
│   ├── mugen_indexer/     ← busca, ranking, projeções indexadas
│   └── mugenx_upload/     ← upload, processamento de assets e publicação
│
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   ├── runtime.exs
│   └── prod.exs
│
├── priv/
│   ├── repo/
│   │   ├── migrations/    ← migrations Ecto
│   │   └── seeds.exs
│   └── gettext/
│
├── infra/                 ← IaC e configuração de deploy
├── scripts/               ← tooling de desenvolvimento local
├── mix.exs                ← root do umbrella
├── mix.lock
└── justfile
```

**Stack:** Elixir · Erlang/OTP · Phoenix · Ecto · PostgreSQL · Oban · Finch · Bandit/Cowboy
**PDS:** implementação de referência oficial (`github.com/bluesky-social/atproto`) — não customizada

**Nota de nomenclatura:** neste doc, `mugenx` é o **core compartilhado**. O domínio do produto mugenx fica no app `mugen_publisher`.

---

## 2. Por que umbrella e não vários repositórios ou apps soltos

| Decisão                                                      | Justificativa                                                                                                                        |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `mugenx` separado                                            | É o núcleo compartilhado entre Mugen e o produto mugenx. Guarda contratos, wrappers, adapters, helpers e integrações comuns.       |
| `mugen` separado de `mugen_web`                              | Separa domínio de interface HTTP/WebSocket. Isso evita contaminar a lógica de negócio com camada web.                                |
| `mugen_publisher` separado de `mugen_publisher_web`                   | Mesma razão: domínio isolado da superfície de entrega.                                                                               |
| apps OTP especializados (`mugen_ingest`, `mugen_feed`, etc.) | Em Elixir isso faz muito sentido porque cada app pode ter sua própria árvore de supervisão e responsabilidades bem delimitadas.      |
| umbrella na raiz                                             | Desenvolvimento unificado, dependências internas simples (`in_umbrella: true`), runtime compartilhado e separação futura mais fácil. |

### Regra de dependência

```text
mugen_web         → pode depender de mugen e mugenx
mugen_publisher_web         → pode depender de mugen_publisher e mugenx

mugen_ingest       → pode depender de mugen e mugenx
mugen_realtime     → pode depender de mugen e mugenx
mugen_feed         → pode depender de mugen e mugenx
mugen_ai           → pode depender de mugen e mugenx
mugen_indexer      → pode depender de mugen e mugenx
mugenx_upload      → pode depender de mugen_publisher e mugenx

mugen              → pode depender de mugenx
mugen_publisher    → pode depender de mugenx

mugenx             → não depende de mugen nem mugen_publisher
mugen              → não depende de mugen_publisher
mugen_publisher    → não depende de mugen
```

---

## 3. Diferença conceitual para o modelo Go

No Go, você estava pensando em:

* módulos separados
* `go.work`
* binários independentes
* código compartilhado por import entre módulos

No Elixir umbrella, o equivalente mais próximo é:

* **apps OTP separados**
* dependências internas via `in_umbrella: true`
* múltiplos **entrypoints supervisionados**
* código compartilhado por apps internos
* tudo podendo rodar no mesmo cluster/runtime BEAM, mas com responsabilidade separada

### Diferença importante

Umbrella **não é microservices**.

É um monorepo de **aplicações OTP** que podem:

* rodar juntas no mesmo release
* ou serem empacotadas em releases separados
* ou serem ativadas/desativadas conforme o deploy

Isso é extremamente útil para o seu caso, porque você quer:

* API
* firehose consumer
* indexação
* ingest
* realtime
* upload processing
* feed generation

Tudo isso combina muito bem com **apps OTP independentes dentro do mesmo umbrella**.

---

## 4. App `mugenx` (core compartilhado)

Código compartilhado entre Mugen e o produto mugenx.
Nenhuma lógica de produto aqui — apenas infraestrutura, contratos e integrações comuns.

```text
apps/mugenx/
├── lib/mugenx/
│   ├── application.ex
│   │
│   ├── atproto/
│   │   ├── identity/              -- resolução de DID, handles, PLC log
│   │   ├── repo/                  -- leitura/escrita de records, commits
│   │   ├── firehose/              -- cliente de firehose, cursor management
│   │   ├── lexicons/              -- NSIDs e payloads próprios
│   │   │   ├── com/mugens/
│   │   │   └── org/mugenx/
│   │   └── pds_client/            -- cliente HTTP para o PDS de referência
│   │
│   ├── repo/
│   │   └── shared_repo.ex         -- helpers, telemetry, tx wrappers
│   │
│   ├── blob_storage/
│   │   ├── behaviour.ex           -- behaviour Storage
│   │   ├── r2.ex
│   │   └── local.ex
│   │
│   ├── queue/
│   │   ├── behaviour.ex           -- interface lógica para enqueue/job dispatch
│   │   ├── oban.ex
│   │   └── inline.ex
│   │
│   ├── config/
│   │   ├── loader.ex
│   │   └── types.ex
│   │
│   ├── http/
│   │   ├── middleware/
│   │   └── json.ex
│   │
│   ├── logging/
│   │   └── logger.ex
│   │
│   ├── aturi/
│   │   ├── aturi.ex
│   │   └── tid.ex
│   │
│   └── telemetry/
│       ├── metrics.ex
│       └── spans.ex
│
└── mix.exs
```

### O que entra em `mugenx`

Entra:

* cliente do PDS
* cliente do firehose
* parsing de AT URI
* behaviors compartilhados
* wrappers de storage
* wrappers de queue/job
* config loader
* logging/telemetry

Não entra:

* regra de feed do Mugen
* catálogo canônico do Mugen
* uploads/publicação do produto mugenx (app `mugen_publisher`)
* lógica de produto

---

## 5. App `mugen`

Domínio principal do Mugen.
Nada de controller, endpoint, socket ou rendering aqui.

```text
apps/mugen/
├── lib/mugen/
│   ├── application.ex
│   │
│   ├── catalog/
│   │   ├── work.ex
│   │   ├── relation.ex
│   │   ├── tag.ex
│   │   ├── merge.ex
│   │   ├── claims.ex
│   │   └── canonicalization.ex
│   │
│   ├── social/
│   │   ├── post.ex
│   │   ├── comment.ex
│   │   ├── review.ex
│   │   └── follow.ex
│   │
│   ├── search/
│   │   ├── query.ex
│   │   └── ranking.ex
│   │
│   ├── moderation/
│   │   ├── case.ex
│   │   ├── trust.ex
│   │   └── submission.ex
│   │
│   ├── providers/
│   │   ├── provider.ex
│   │   ├── anilist/
│   │   └── mangadex/
│   │
│   ├── firehose/
│   │   ├── commit_handler.ex
│   │   ├── identity_handler.ex
│   │   └── label_handler.ex
│   │
│   ├── projections/
│   │   ├── posts.ex
│   │   ├── graph.ex
│   │   └── catalog_ref.ex
│
└── mix.exs
```

### Papel do `mugen`

Ele deve conter:

* regras de catálogo
* merge e canonicalização
* relações entre works
* social graph e interações do Mugen
* lógica de projeção da federação para o modelo interno
* funções de domínio puras ou quase puras

Minha recomendação: trate `mugen` como o **coração do produto**, não como um saco de arquivos utilitários.

---

## 6. App `mugen_web`

Superfície HTTP do Mugen: API pública, endpoints de catálogo, busca, social e autenticação.

```text
apps/mugen_web/
├── lib/mugen_web/
│   ├── application.ex
│   ├── endpoint.ex
│   ├── router.ex
│   │
│   ├── controllers/
│   │   ├── actor_controller.ex
│   │   ├── feed_controller.ex
│   │   ├── catalog_controller.ex
│   │   ├── search_controller.ex
│   │   ├── social_controller.ex
│   │   └── auth_controller.ex
│   │
│   ├── plugs/
│   │   ├── request_id.ex
│   │   ├── auth.ex
│   │   ├── rate_limit.ex
│   │   └── admin_only.ex
│   │
│   ├── json/
│   │   ├── catalog_json.ex
│   │   ├── feed_json.ex
│   │   └── social_json.ex
│   │
│   └── channels/
│       └── user_socket.ex
│
└── mix.exs
```

### Papel do `mugen_web`

* validar input HTTP
* autenticar
* autorizar
* transformar request em chamada de domínio
* renderizar JSON
* expor API

Não deve conter:

* merge de catálogo
* indexação
* job pipeline
* regra de negócio complexa

---

## 7. App `mugen_publisher`

Domínio do produto mugenx.
Separado do Mugen porque o produto tem ciclo de vida e responsabilidade próprios.

```text
apps/mugen_publisher/
├── lib/mugen_publisher/
│   ├── application.ex
│   │
│   ├── catalog/
│   │   ├── series.ex
│   │   ├── chapter.ex
│   │   ├── page.ex
│   │   └── comment_projection.ex
│   │
│   ├── federation/
│   │   ├── publisher.ex
│   │   ├── series_sync.ex
│   │   ├── chapter_sync.ex
│   │   └── profile_sync.ex
│   │
│   ├── moderation/
│   │   ├── ban.ex
│   │   └── report.ex
│   │
│   ├── storage/
│   │   ├── asset.ex
│   │   └── image_pipeline.ex
│
└── mix.exs
```

---

## 8. App `mugen_publisher_web`

Superfície HTTP do produto mugenx (domínio em `mugen_publisher`).

```text
apps/mugen_publisher_web/
├── lib/mugen_publisher_web/
│   ├── application.ex
│   ├── endpoint.ex
│   ├── router.ex
│   │
│   ├── controllers/
│   │   ├── catalog_controller.ex
│   │   ├── reader_controller.ex
│   │   ├── social_controller.ex
│   │   └── admin_controller.ex
│   │
│   ├── plugs/
│   │   ├── auth.ex
│   │   └── instance_scope.ex
│   │
│   └── json/
│       ├── reader_json.ex
│       └── catalog_json.ex
│
└── mix.exs
```

---

## 9. Apps especializados do runtime

Aqui está uma das grandes vantagens do modelo umbrella em Elixir.

No Go você tinha vários binários.
No Elixir, você pode ter **apps OTP especializados**, cada um com seu supervisor, workers e filas.

---

### 9.1 `mugen_ingest`

```text
apps/mugen_ingest/
├── lib/mugen_ingest/
│   ├── application.ex
│   ├── workers/
│   │   ├── anilist_sync_worker.ex
│   │   ├── mangadex_sync_worker.ex
│   │   └── merge_worker.ex
│   ├── pipelines/
│   │   ├── raw_to_match.ex
│   │   └── match_to_canonical.ex
│   └── scheduler.ex
└── mix.exs
```

Função:

* ingest de providers
* sincronização incremental
* transformação raw → canonical
* jobs agendados

**Ferramenta recomendada:** Oban

---

### 9.2 `mugen_indexer`

```text
apps/mugen_indexer/
├── lib/mugen_indexer/
│   ├── application.ex
│   ├── workers/
│   │   ├── search_projection_worker.ex
│   │   └── ranking_worker.ex
│   └── projectors/
│       ├── work_search_docs.ex
│       └── trending_score.ex
└── mix.exs
```

Função:

* projeções de busca
* ranking
* materialização de documentos de pesquisa

---

### 9.3 `mugen_feed`

```text
apps/mugen_feed/
├── lib/mugen_feed/
│   ├── application.ex
│   ├── generators/
│   │   ├── following.ex
│   │   ├── discover.ex
│   │   └── work_updates.ex
│   └── workers/
│       └── feed_refresh_worker.ex
└── mix.exs
```

Função:

* geração de feeds
* pré-cálculo/materialização
* refresh incremental

---

### 9.4 `mugen_ai`

```text
apps/mugen_ai/
├── lib/mugen_ai/
│   ├── application.ex
│   ├── workers/
│   │   ├── embeddings_worker.ex
│   │   └── summaries_worker.ex
│   └── providers/
│       └── embedding_provider.ex
└── mix.exs
```

Função:

* NLP
* embeddings
* summaries
* pipelines assíncronos

---

### 9.5 `mugen_realtime`

```text
apps/mugen_realtime/
├── lib/mugen_realtime/
│   ├── application.ex
│   ├── presence.ex
│   ├── channels/
│   │   ├── reading_room_channel.ex
│   │   ├── chat_channel.ex
│   │   └── session_channel.ex
│   ├── sessions/
│   │   ├── room_supervisor.ex
│   │   ├── room_server.ex
│   │   └── sync_state.ex
│   └── guards/
│       └── connection_limits.ex
└── mix.exs
```

Função:

* WebSockets
* presence
* salas de leitura
* sincronização de eventos
* coordenação de sessões realtime

Minha opinião: essa parte é **exatamente onde Elixir mais brilha**.

---

### 9.6 `mugenx_upload`

```text
apps/mugenx_upload/
├── lib/mugenx_upload/
│   ├── application.ex
│   ├── workers/
│   │   ├── receive_upload_worker.ex
│   │   ├── process_image_worker.ex
│   │   └── publish_asset_worker.ex
│   ├── pipeline/
│   │   ├── optimize.ex
│   │   ├── thumbnail.ex
│   │   └── persist.ex
│   └── storage.ex
└── mix.exs
```

Função:

* upload chunked
* otimização de imagem
* geração de thumbnails
* persistência em R2/local storage
* publicação associada ao catálogo do mugenx (app `mugen_publisher`)

---

## 10. Banco de dados e migrations

No umbrella Elixir, o padrão idiomático é usar **Ecto.Repo** e manter migrations em `priv/repo/migrations`.

Você tem duas abordagens válidas.

---

### Opção A — Um único Repo compartilhado

Mais simples no começo.

```text
apps/mugenx/lib/mugenx/repo.ex
priv/repo/migrations/
```

Prós:

* simples
* menos boilerplate
* ótimo para MVP

Contras:

* separação de ownership menos explícita

---

### Opção B — Um Repo por produto ou contexto operacional

Exemplo:

* `Mugen.Repo`
* `MugenPublisher.Repo`

Prós:

* fronteiras mais explícitas
* possível separar deploy/ownership depois

Contras:

* complexidade maior
* geralmente exagero no início

### Minha recomendação

Para o seu estágio: **um Repo principal só**.

Exemplo:

```text
apps/mugenx/lib/mugenx/repo.ex
priv/repo/migrations/
```

E no banco você continua usando schemas lógicos:

* `identity`
* `repo`
* `blob`
* `graph`
* `content`
* `label`
* `local`
* `ops`
* `mugen_catalog`
* `mugen_index`
* `mugen_feed`
* `mugen_ai`
* `mugen_moderation`
* `mugen_ops`
* `provider_ingest`
* `scan_catalog`
* `scan_storage`
* `scan_ops`
* `scan_moderation`

Ou seja: **um Repo Ecto não impede múltiplos schemas SQL**.

---

## 11. Estrutura das migrations

```text
priv/
└── repo/
    ├── migrations/
    │   ├── 20260311120000_create_shared_schemas.exs
    │   ├── 20260311120100_identity.exs
    │   ├── 20260311120200_repo.exs
    │   ├── 20260311120300_blob.exs
    │   ├── 20260311120400_graph.exs
    │   ├── 20260311120500_content.exs
    │   ├── 20260311120600_label.exs
    │   ├── 20260311120700_local.exs
    │   ├── 20260311120800_ops.exs
    │   ├── 20260311130000_mugen_catalog.exs
    │   ├── 20260311130100_mugen_index.exs
    │   ├── 20260311130200_mugen_feed.exs
    │   ├── 20260311130300_mugen_ai.exs
    │   ├── 20260311130400_mugen_moderation.exs
    │   ├── 20260311130500_mugen_ops.exs
    │   ├── 20260311130600_provider_ingest.exs
    │   ├── 20260311140000_scan_storage.exs
    │   ├── 20260311140100_scan_catalog.exs
    │   ├── 20260311140200_scan_ops.exs
    │   └── 20260311140300_scan_moderation.exs
    │
    └── seeds.exs
```

---

## 12. Configuração do umbrella

### Root `mix.exs`

O root do umbrella coordena os apps.

```elixir
defmodule Mugen.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp deps do
    []
  end
end
```

---

### Dependência entre apps

Exemplo em `apps/mugen_web/mix.exs`:

```elixir
defp deps do
  [
    {:mugen, in_umbrella: true},
    {:mugenx, in_umbrella: true},
    {:phoenix, "~> 1.7"}
  ]
end
```

Exemplo em `apps/mugen_ingest/mix.exs`:

```elixir
defp deps do
  [
    {:mugen, in_umbrella: true},
    {:mugenx, in_umbrella: true},
    {:oban, "~> 2.17"}
  ]
end
```

---

## 13. `config/`

```text
config/
├── config.exs
├── dev.exs
├── test.exs
├── prod.exs
└── runtime.exs
```

### `config/config.exs`

* repo
* endpoint
* telemetry
* json lib
* Oban
* PubSub

### `config/runtime.exs`

* `DATABASE_URL`
* `SECRET_KEY_BASE`
* `PDS_URL`
* `R2_BUCKET`
* `REDIS_URL` se usar
* flags por ambiente

---

## 14. `justfile`

```just
set shell := ["bash", "-cu"]
set dotenv-load := true

default:
  @just --list

dev:
  iex -S mix phx.server

dev-mugen:
  MIX_ENV=dev iex -S mix phx.server

test:
  mix test

fmt:
  mix format

lint:
  mix credo --strict

check:
  mix format --check-formatted
  mix credo --strict
  mix test

setup:
  mix deps.get
  mix ecto.setup

reset-db:
  mix ecto.reset

migrate:
  mix ecto.migrate

seeds:
  mix run priv/repo/seeds.exs

routes-mugen:
  mix phx.routes MugenWeb.Router

routes-scan:
  mix phx.routes MugenPublisherWeb.Router

oban:
  iex -S mix
```

---

## 15. Releases e deploy

Uma vantagem muito boa do umbrella é que você pode montar **releases separados** mesmo estando no mesmo monorepo.

Exemplos de release:

* `mugen_web`
* `mugen_ingest`
* `mugen_realtime`
* `mugen_publisher`
* `mugen_publisher_web`
* `mugenx_upload`

Ou um release maior com vários apps juntos.

### Exemplo de agrupamento

#### Deploy 1 — API pública do Mugen

* `mugenx`
* `mugen`
* `mugen_web`

#### Deploy 2 — ingest/index/feed workers

* `mugenx`
* `mugen`
* `mugen_ingest`
* `mugen_indexer`
* `mugen_feed`
* `mugen_ai`

#### Deploy 3 — realtime

* `mugenx`
* `mugen`
* `mugen_realtime`

#### Deploy 4 — produto mugenx

* `mugenx`
* `mugen_publisher`
* `mugen_publisher_web`
* `mugenx_upload`

Isso é bem mais elegante do que enfiar tudo em um único Phoenix app gigante.

---

## 16. PDS — Implementação de Referência

O PDS continua **fora do umbrella**.

```text
Repositório externo:
  github.com/bluesky-social/atproto
  → packages/pds

Integração no umbrella:
  apps/mugenx/lib/mugenx/atproto/pds_client/
    ← wrapper HTTP
    ← usado por mugen e mugen_publisher

Deploy:
  Uma instância de PDS compartilhada serve contas do Mugen e do mugenx.
  Referenciada por PDS_URL no runtime config.
```

---

## 17. Separação futura em repositórios distintos

Se no futuro você quiser separar licenças e repos, o umbrella facilita, mas menos “plug and play” do que Go com `go.work`.

O caminho natural seria:

```text
1. Extrair apps/mugenx para um repo próprio como lib Hex privada ou dependency git
2. Extrair o grupo de apps do Mugen para um repo próprio
3. Extrair o grupo de apps do mugenx (mugen_publisher, mugen_publisher_web, mugenx_upload) para outro repo próprio
4. Substituir `in_umbrella: true` por dependências git/path/hex
5. Ajustar releases e configs
```

### Importante

Se você realmente quer separar closed source e open source no futuro, **não misture regra de negócio de produto dentro de `mugenx`**.

`mugenx` deve ser:

* neutro
* reutilizável
* licenciado de forma permissiva
* sem contaminar a licença dos produtos

---

## 18. Resumo de entrypoints equivalentes

| Papel                     | App Elixir                  | Serve HTTP/WS? | Função                            |
| ------------------------- | --------------------------- | -------------: | --------------------------------- |
| API pública do Mugen      | `mugen_web`                 |         ✅ HTTP | API pública                       |
| Consumo da rede/federação | `mugen` + workers dedicados |              ❌ | Processa records e projeções      |
| Ingest de providers       | `mugen_ingest`              |              ❌ | AniList, MangaDex, sync           |
| Indexação                 | `mugen_indexer`             |              ❌ | Busca e ranking                   |
| NLP/AI                    | `mugen_ai`                  |              ❌ | Embeddings e summaries            |
| Feed                      | `mugen_feed`                |              ❌ | Materialização e refresh de feeds |
| Realtime                  | `mugen_realtime`            |    ✅ WebSocket | Chat e sessões síncronas          |
| API pública do mugenx      | `mugen_publisher_web`            |         ✅ HTTP | API pública                       |
| Upload e processamento     | `mugenx_upload`         |              ❌ | Upload, imagens, assets           |
| Federação/publicação       | `mugen_publisher`       |              ❌ | Publica records no PDS            |
| PDS externo               | —                           |         ✅ HTTP | PDS ATProto de referência         |

---

## 19. Estrutura recomendada final

Se eu estivesse montando o seu projeto hoje em Elixir, eu usaria isso:

```text
mugen-umbrella/
├── apps/
│   ├── mugenx
│   ├── mugen
│   ├── mugen_web
│   ├── mugen_ingest
│   ├── mugen_indexer
│   ├── mugen_feed
│   ├── mugen_ai
│   ├── mugen_realtime
│   ├── mugen_publisher
│   ├── mugen_publisher_web
│   └── mugenx_upload
├── config/
├── priv/
├── infra/
├── scripts/
├── mix.exs
└── justfile
```

---

## 20. Opinião arquitetural final

Eu faria **alguns ajustes em relação ao plano original em Go**:

### O que eu manteria

* separação entre produto compartilhado e produto específico
* separação entre Mugen e mugenx
* PDS externo
* catálogo, feed, indexer, ingest e realtime como responsabilidades explícitas

### O que eu mudaria no modelo Elixir

* eu **não pensaria em “um binário por responsabilidade” logo de cara**
* eu pensaria em **um app OTP por responsabilidade**
* eu separaria **domínio** de **web** desde o início
* eu usaria **Oban** para workloads assíncronos antes de introduzir complexidade extra
* eu evitaria criar apps demais muito cedo, mas já deixaria a fronteira pronta

### Minha recomendação prática

Comece com:

```text
mugenx
mugen
mugen_web
mugen_ingest
mugen_publisher
mugen_publisher_web
```

E só crie depois, quando doer de verdade:

```text
mugenx_upload
mugen_indexer
mugen_realtime
mugen_feed
mugen_ai
```

Porque em Elixir é fácil crescer bem a partir disso, mas também é fácil cair no erro de **fragmentar cedo demais**.
