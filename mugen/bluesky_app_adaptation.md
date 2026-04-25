# Adaptação do App Bluesky para o Mugen

Este documento descreve o que precisa mudar no app do Bluesky para ele virar o cliente social do Mugen e o que ainda falta no backend Phoenix para sustentar uma rede social estilo Bluesky, mas orientada a mangás.

## 1. Direção do produto

O Mugen deve reaproveitar a ideia central do Bluesky: identidade ATProtocol, posts, replies, reposts, quotes, likes, perfis, timelines, feeds e moderação por labels. A diferença principal é que o centro do produto não é apenas o autor do post; é a relação entre pessoas, posts e obras.

No Bluesky, um post normalmente vive no grafo social do autor e entra em feeds por follows, likes, reposts, replies e algoritmos. No Mugen, um post também deve poder viver dentro do contexto de uma obra, capítulo, scan group, tag, lista ou evento de leitura. A timeline continua existindo, mas páginas de obra e feeds por obra viram superfícies de primeira classe.

O Mugen também terá biblioteca de leitura e indexador de mangás. A leitura das obras não acontece dentro do app: o Mugen aponta para sites externos, scan groups, lojas, páginas oficiais ou instâncias mugenx. O app precisa tratar isso como parte natural da experiência.

## 2. O que adaptar no app Bluesky

### 2.1 Configuração de rede e identidade

- Trocar os endpoints padrão do Bluesky pelos endpoints do Mugen AppView.
- Manter login ATProtocol/OAuth como base, usando o fluxo já implementado no backend.
- Adicionar fluxo de cadastro, porque hoje o backend cobre login mas não criação de conta.
- Decidir se o cadastro será:
  - conta nova em um PDS externo;
  - conta nova em um PDS recomendado pelo Mugen;
  - conta local primeiro, com link ATProto depois;
  - ou um fluxo híbrido com convite/handle pré-configurado.
- Separar claramente:
  - sessão local do Mugen;
  - credencial OAuth/DPoP para falar com o PDS;
  - identidade pública do ator (`did`, handle, perfil).

### 2.2 Cliente de API e contratos

- Substituir chamadas específicas de `app.bsky.*` pelas rotas e lexicons do Mugen.
- Gerar ou escrever um cliente TypeScript para a OpenAPI do Mugen.
- Adicionar suporte aos lexicons próprios:
  - `org.mugens.feed.post`;
  - `org.mugens.feed.comment`;
  - `org.mugens.graph.like`;
  - `org.mugens.graph.repost`;
  - `org.mugens.graph.follow`;
  - `org.mugens.activity.library`;
  - `org.mugens.activity.chapter_progress`;
  - `org.mugens.activity.review`;
  - `org.mugens.activity.rating`;
  - `org.mugens.activity.favorite`.
- Preservar o modelo mental do Bluesky quando fizer sentido: post view, thread view, profile view, feed view e notification view.
- Evitar acoplar o app a IDs internos do banco. O app deve preferir AT URIs e só usar IDs locais quando estiver chamando endpoints do AppView.

### 2.3 Composer de posts

O composer do Bluesky precisa virar um composer com contexto de mangá.

Funcionalidades esperadas:

- Criar post solto, como no Bluesky.
- Criar post associado a uma obra (`subject_kind = work` ou `series`).
- Criar post associado a um capítulo (`subject_kind = chapter`).
- Responder a outro post preservando `reply_root_uri` e `reply_parent_uri`.
- Citar outro post com `quote_uri`.
- Detectar e enviar facets de menção, link e hashtag.
- Permitir imagens e GIFs.
- Remover ou desabilitar suporte a vídeo.
- Exibir seletor de obra/capítulo no composer.
- Permitir abrir o composer a partir da página de obra com o subject já preenchido.
- Permitir spoiler flag no post ou no anexo quando o assunto for capítulo/obra.

O ponto mais importante é que associar um post a uma obra não deve ser só uma hashtag textual. O record precisa carregar um subject estruturado, idealmente um AT URI canônico:

```json
{
  "$type": "org.mugens.feed.post",
  "text": "Esse arco ficou absurdo.",
  "subject": {
    "uri": "at://did:plc:mugens-catalog/org.mugens.canonical.work/one-piece",
    "kind": "work"
  },
  "facets": [],
  "createdAt": "2026-04-25T00:00:00Z"
}
```

### 2.4 Renderização de posts

O componente de post deve continuar suportando:

- autor;
- avatar;
- handle;
- texto;
- facets;
- imagens/GIFs;
- reply;
- quote;
- like;
- repost;
- contadores;
- menus de moderação.

Mas deve adicionar contexto de catálogo:

- card compacto da obra quando `subject_uri` apontar para obra;
- card compacto do capítulo quando apontar para capítulo;
- link para a página da obra no Mugen;
- indicação de spoiler;
- agrupamento visual quando uma thread inteira gira em torno da mesma obra;
- fallback quando o subject ainda não foi resolvido pelo AppView.

Posts sem subject continuam válidos. A regra é: o Mugen favorece posts contextualizados por obra, mas não precisa proibir posts soltos.

### 2.5 Feeds e timelines

O app deve manter telas parecidas com o Bluesky, mas os feeds principais mudam.

Feeds mínimos:

- Home: pessoas seguidas + posts recomendados.
- Following: apenas atores seguidos.
- Discover: recomendações globais.
- Work feed: posts associados a uma obra.
- Chapter feed: posts associados a um capítulo.
- Hashtag feed: posts com hashtag.
- Profile feed: posts de um ator.
- Mentions/replies: interações com o usuário.

Feeds específicos do Mugen:

- Obras em alta.
- Discussões recentes das obras da minha biblioteca.
- Novos capítulos das obras que acompanho.
- Reviews recentes de obras que sigo.
- Posts de scan groups seguidos.

O app Bluesky tem bastante UI reaproveitável para timeline e thread, mas a origem dos dados deve mudar para endpoints do AppView Mugen. O feed generator do Bluesky não deve ser copiado diretamente como regra de produto; no Mugen, `mugen_feed` deve materializar feeds com conhecimento de catálogo.

### 2.6 Busca e descoberta

A busca precisa deixar de ser apenas busca social.

O app deve ter busca unificada para:

- obras;
- capítulos;
- autores/staff;
- scan groups;
- usuários;
- posts;
- hashtags;
- listas/editoriais.

O resultado ideal mistura catálogo e social: buscar "Berserk" deve mostrar a obra, aliases, capítulos, posts recentes, reviews, hashtags relacionadas e links externos de leitura/compra.

### 2.7 Biblioteca de leitura

O app precisa de uma área que não existe no Bluesky como feature central.

Funcionalidades mínimas:

- adicionar obra à biblioteca;
- mudar estado: lendo, completo, pausado, abandonado, planejo ler;
- marcar capítulo como lido;
- avaliar obra;
- escrever review;
- favoritar obra;
- ver atividade pública de leitura de outros usuários;
- abrir link externo para leitura.

Importante: o progresso fino de página deve ser local/privado (`local.reading_progress`). O record federado deve representar eventos portáveis, como "li este capítulo" ou "essa obra está na minha lista".

### 2.8 Páginas de obra e capítulo

O app precisa introduzir telas novas:

- página de obra;
- página de capítulo;
- página de scan group;
- página de staff/criador;
- página de tag/gênero;
- página de links externos de leitura.

A página de obra deve ser o equivalente, no Mugen, ao perfil de usuário no Bluesky: um hub social e informacional.

Ela deve conter:

- capa, títulos, aliases e metadados;
- status, ano, demografia, gêneros e classificação;
- capítulos conhecidos;
- links externos;
- botão de adicionar à biblioteca;
- rating/review;
- feed da obra;
- posts em alta;
- reviews;
- scan groups relacionados;
- obras relacionadas.

### 2.9 Mídia

O Mugen deve suportar:

- imagens;
- GIFs;
- thumbnails;
- alt text;
- labels de conteúdo;
- limite de tamanho e dimensões.

O Mugen não deve suportar vídeo neste primeiro ciclo. No app, isso significa:

- esconder botões de vídeo;
- remover caminhos de upload/processamento de vídeo da UI;
- garantir que embeds de vídeo não sejam criados;
- tratar vídeo externo como link comum, não como mídia nativa.

### 2.10 Moderação e labels

O app deve reaproveitar a mentalidade do Bluesky para labels, blocks, mutes e reports, mas com regras específicas:

- spoiler de capítulo;
- conteúdo adulto;
- gore/violência;
- obra sensível;
- scan group bloqueado;
- hashtag mutada;
- obra mutada;
- usuário bloqueado;
- domínio externo bloqueado ou suspeito.

O usuário deve conseguir mutar:

- ator;
- obra;
- capítulo;
- hashtag;
- scan group;
- palavra-chave.

### 2.11 Notificações

O app precisa notificar:

- likes;
- reposts;
- replies;
- quotes;
- mentions;
- follows;
- respostas em post de uma obra seguida;
- novos capítulos de obra na biblioteca;
- reviews novas de obras seguidas;
- atividade relevante de scan groups seguidos.

Nem tudo precisa ser push no MVP. Mas o backend deve ter uma tabela/projeção de notificações desde cedo, porque isso afeta várias telas.

## 3. O que falta implementar no backend Mugen

### 3.1 Cadastro

Hoje o login ATProtocol está bem encaminhado, mas ainda falta cadastro.

Backlog:

- endpoint para iniciar cadastro;
- decisão sobre PDS alvo;
- validação de handle;
- criação ou vinculação de DID;
- criação de `identity.local_users`;
- estado `atproto_link_state`;
- onboarding inicial;
- criação/edição de perfil;
- tratamento de conta local ainda sem DID.

Sem isso, o app consegue logar usuários existentes, mas não consegue crescer como produto próprio.

### 3.2 Escrita de records ATProto

Para virar rede social, o backend precisa escrever records no PDS do usuário.

Backlog:

- wrapper para `com.atproto.repo.createRecord`;
- wrapper para `com.atproto.repo.deleteRecord`;
- wrapper para `com.atproto.repo.putRecord`, se records editáveis forem necessários;
- validação dos lexicons `org.mugens.*`;
- geração de rkeys;
- upload de blobs de imagem/GIF;
- refresh automático do token antes da escrita;
- tratamento de erro quando o PDS rejeita o record;
- idempotência para evitar duplicar posts/interações em retry.

O helper `Mugenx.Atproto.PDS.request/2` já existe e deve virar a base dessas operações.

### 3.3 Firehose, repo e projeções

O AppView precisa consumir a rede e materializar dados consultáveis.

Backlog:

- consumir firehose;
- persistir commits em `repo.*`;
- processar creates, updates e deletes;
- projetar posts em `content.posts`;
- projetar facets em `content.post_facets`;
- projetar replies/threads em `content.thread_projections`;
- projetar likes, reposts, follows e blocks em `graph.*`;
- projetar biblioteca/reviews/ratings em `activity.*`;
- resolver subjects canônicos para IDs locais;
- manter contadores derivados;
- suportar backfill/reindex.

Sem isso, o backend pode até criar records, mas o AppView não consegue responder timelines, páginas de obra ou contadores com performance.

### 3.4 API social

A OpenAPI atual ainda está centrada em autenticação e catálogo. Falta a API social.

Endpoints mínimos:

- `POST /api/posts`
- `GET /api/posts/{uri}`
- `DELETE /api/posts/{uri}`
- `GET /api/posts/{uri}/thread`
- `POST /api/posts/{uri}/like`
- `DELETE /api/posts/{uri}/like`
- `POST /api/posts/{uri}/repost`
- `DELETE /api/posts/{uri}/repost`
- `GET /api/feeds/home`
- `GET /api/feeds/following`
- `GET /api/feeds/discover`
- `GET /api/works/{id}/feed`
- `GET /api/chapters/{id}/feed`
- `GET /api/hashtags/{tag}/feed`
- `GET /api/profiles/{handleOrDid}`
- `GET /api/profiles/{handleOrDid}/posts`
- `POST /api/profiles/{did}/follow`
- `DELETE /api/profiles/{did}/follow`

Esses endpoints podem retornar views prontas para o app, no estilo AppView do Bluesky, em vez de expor o banco cru.

### 3.5 Biblioteca e atividade de leitura

Backlog:

- `GET /api/me/library`
- `POST /api/me/library`
- `PATCH /api/me/library/{workId}`
- `DELETE /api/me/library/{workId}`
- `POST /api/chapters/{id}/read`
- `DELETE /api/chapters/{id}/read`
- `POST /api/works/{id}/rating`
- `POST /api/works/{id}/review`
- `POST /api/works/{id}/favorite`
- projeções em `activity.*`;
- contadores em `activity.work_activity_counts`;
- integração com feeds: "obras da minha biblioteca".

Decisão importante: biblioteca pública deve ser federada; progresso fino e preferências privadas ficam locais.

### 3.6 Catálogo como subject social

O catálogo precisa estar pronto para servir de âncora dos posts.

Backlog:

- garantir AT URI canônico para obra;
- garantir AT URI canônico para capítulo quando existir;
- resolver links externos para obra/capítulo;
- expor summary compacto para embed em post;
- expor feed por subject;
- manter aliases para busca;
- tratar obra ainda não canonizada;
- mapear `org.mugenx.catalog.series/chapter` para canônico quando possível.

Essa camada é o que diferencia o Mugen de um fork visual do Bluesky.

### 3.7 Feeds materializados

Backlog:

- implementar `mugen_feed`;
- geração de home/following/discover;
- geração de feed por obra;
- geração de feed por capítulo;
- ranking por tempo, relações sociais, biblioteca e popularidade da obra;
- deduplicação de reposts;
- filtros de mute/block/labels;
- snapshots com expiração;
- cursor pagination;
- jobs Oban para refresh.

### 3.8 Busca

Backlog:

- busca de posts;
- busca de hashtags;
- busca de obras;
- busca de capítulos;
- busca de atores;
- busca de scan groups;
- ranking híbrido catálogo/social;
- indexação incremental via firehose;
- endpoint de autocomplete para o composer escolher obra/capítulo.

### 3.9 Imagens, GIFs e blobs

Backlog:

- endpoint de upload ou proxy para blob no PDS;
- validação de MIME;
- rejeitar vídeo;
- gerar thumbnails quando necessário;
- guardar metadados em `blob.blobs`;
- exigir alt text ou pelo menos suportar alt text;
- labels automáticos/manuais de mídia sensível.

### 3.10 Moderação

Backlog:

- reports;
- labels;
- mutes;
- blocks;
- ocultar post;
- ocultar obra/tag/scan group;
- regras de spoiler;
- filtros por conteúdo adulto;
- fila de revisão humana;
- integração de moderação no feed e na busca.

### 3.11 Notificações

Backlog:

- tabela/projeção de notificações;
- criar eventos a partir de likes, reposts, replies, quotes, mentions e follows;
- eventos de catálogo: capítulo novo, review nova, discussão quente;
- endpoint `GET /api/notifications`;
- marcar como lido;
- push notifications depois do MVP.

## 4. Ordem recomendada de implementação

### Fase 0: fazer o app falar com o Mugen

Objetivo: abrir o fork do Bluesky como cliente Mugen logado.

- apontar configuração para o AppView Mugen;
- adaptar sessão e auth;
- criar cliente OpenAPI;
- trocar branding e rotas iniciais;
- manter telas não suportadas escondidas;
- adicionar cadastro ou deixar claro que é login-only temporariamente.

### Fase 1: MVP social

Objetivo: posts, threads, likes, reposts e feeds básicos.

- criar records de post;
- upload de imagem/GIF;
- replies e quotes;
- like/repost/follow;
- projeções `content.*` e `graph.*`;
- feed following;
- profile feed;
- thread view;
- notifications básicas.

### Fase 2: Mugen de verdade

Objetivo: posts associados a mangás e biblioteca.

- seletor de obra/capítulo no composer;
- feed por obra;
- página de obra com feed social;
- biblioteca;
- capítulo lido;
- rating/review/favorite;
- busca unificada;
- links externos de leitura.

### Fase 3: AppView completo

Objetivo: experiência competitiva com Bluesky, mas orientada a mangás.

- discover feed;
- ranking por biblioteca e catálogo;
- moderação avançada;
- labels de spoiler;
- listas editoriais;
- scan groups;
- recomendações;
- push notifications;
- realtime opcional.

## 5. Decisões que ainda precisam ser fechadas

- O Mugen vai hospedar/recomendar um PDS ou só autenticar PDS externos?
- Cadastro cria conta ATProto de verdade ou cria conta local primeiro?
- `org.mugens.feed.post` substitui completamente `app.bsky.feed.post` ou o app mantém compatibilidade parcial?
- Post associado a obra deve exigir subject canônico ou aceitar subject local temporário?
- GIF será tratado como imagem animada no blob ou como embed externo?
- Biblioteca será pública por padrão ou privada por padrão?
- Reviews serão posts comuns com subject ou records próprios em `org.mugens.activity.review`?
- O feed de obra mostra qualquer post com subject da obra ou também posts com hashtags/links inferidos?
- O AppView deve indexar apenas lexicons do Mugen ou também conteúdo Bluesky normal para interoperabilidade?

## 6. Resumo prático

O app Bluesky dá uma base excelente para identidade, timeline, composer, thread, perfil, moderação e interações sociais. O trabalho principal no cliente é trocar o eixo da experiência: de "pessoas postando na timeline" para "pessoas conversando em torno de obras".

No backend, o maior buraco não é só endpoint HTTP. Falta o ciclo AppView completo: escrever records no PDS, consumir firehose, projetar records em tabelas consultáveis, gerar feeds, resolver subjects de catálogo, aplicar moderação e expor views prontas para o app.

O primeiro MVP deve ser pequeno: login, post, reply, like, repost, following feed e profile feed. Assim que isso estiver estável, o Mugen precisa adicionar a peça que justifica o produto: subject de obra/capítulo no composer, página de obra com feed social e biblioteca de leitura federada.
