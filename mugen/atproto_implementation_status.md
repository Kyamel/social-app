# AT-Protocol OAuth Status

Este arquivo resume o estado atual da implementacao AT-Protocol/OAuth no projeto Phoenix, com foco no ciclo de login federado no app `mugen`.

## Estado atual

O fluxo de login federado no backend do `mugen` esta fechado e agora cobre os pontos mais importantes para producao no lado OAuth:

- Resolucao de handle/DID, descoberta de Authorization Server/PDS, PKCE e PAR.
- DPoP por sessao com proofs ES256.
- `dpop_bound_access_tokens: true` no client metadata.
- Suporte a confidential client com `private_key_jwt` quando uma chave fixa do cliente esta configurada.
- Endpoint `/.well-known/jwks.json` no `mugen_web` para publicar a chave publica do cliente OAuth.
- Assinatura de `client_assertion` no PAR, no code exchange e no refresh.
- Persistencia e reutilizacao de `DPoP-Nonce` do Authorization Server.
- Retry automatico quando o Authorization Server responde `use_dpop_nonce`.
- Refresh inline de access token antes de requests autenticadas ao PDS.
- Helper de requests autenticadas ao PDS com `Authorization: DPoP ...` e claim `ath` no proof.
- Persistencia criptografada de tokens e chaves DPoP por credencial.
- Sessao local por cookie httpOnly continua funcionando como antes.

## Modulos principais

- `Mugenx.Atproto.ClientMetadata`
  - monta o metadata com `dpop_bound_access_tokens`
  - promove o client para confidential automaticamente quando existe chave configurada
  - calcula `jwks_uri` padrao

- `Mugenx.Atproto.ClientKeys`
  - carrega a chave privada fixa do cliente
  - publica JWKS
  - assina `client_assertion` com ES256

- `Mugenx.Atproto.DPoP`
  - agora suporta `nonce` e `ath`

- `Mugenx.Atproto.DPoPClient`
  - centraliza requests com DPoP
  - faz retry automatico em `use_dpop_nonce`

- `Mugenx.Atproto.TokenRefresher`
  - faz refresh inline com row lock
  - persiste a rotacao de tokens e o nonce do Authorization Server

- `Mugenx.Atproto.PDS`
  - helper para requests autenticadas ao PDS
  - usa refresh inline e envia `ath`

- `MugenWeb.AtprotoAuthController`
  - expõe `/.well-known/jwks.json`
  - continua expondo `/oauth/client-metadata.json`

## Configuracao de producao

Para rodar como confidential client em producao, configure:

- `MUGEN_PUBLIC_BASE_URL`
- `MUGEN_ATPROTO_CLIENT_PRIVATE_JWK`
- opcionalmente `MUGEN_ATPROTO_OAUTH_SCOPE`

O `MUGEN_ATPROTO_CLIENT_PRIVATE_JWK` deve ser um JSON JWK EC P-256 privado. Sem essa chave, o app cai para metadata de public client.

Tambem existe suporte equivalente de config para `mugen_publisher`:

- `MUGEN_PUBLISHER_PUBLIC_BASE_URL`
- `MUGEN_PUBLISHER_ATPROTO_CLIENT_PRIVATE_JWK`
- `MUGEN_PUBLISHER_ATPROTO_OAUTH_SCOPE`

## O que ainda falta ou depende de decisao

- `mugen_publisher_web` ainda nao expõe o proprio `/.well-known/jwks.json`.
  - A infra de chave/config existe, mas a rota/controller correspondente foi adicionada apenas no `mugen_web`.

- Escopos expandidos de biblioteca ainda nao estao habilitados por padrao.
  - O sistema agora aceita escopo configuravel no metadata.
  - Por enquanto o default continua minimalista (`atproto`), o que combina com o objetivo atual de fechar o login federado.
  - Quando a sincronizacao federada da biblioteca for ativada, sera preciso decidir o conjunto final de scopes a declarar e pedir.

- Ainda nao existe feature de produto consumindo `Mugenx.Atproto.PDS.request/2`.
  - O helper de infraestrutura ja existe e esta pronto para ser usado por futuras operacoes autenticadas no PDS.

- Rotacao operacional da chave do confidential client ainda nao foi automatizada.
  - A base para JWKS e `kid` existe.
  - Se quiser rotacao sem downtime, sera preciso publicar mais de uma chave ativa por periodo de transicao.

## Validacao feita neste ciclo

- `mix precommit`
- testes novos cobrindo:
  - metadata/JWKS do confidential client
  - claims `nonce` e `ath` em DPoP
  - retry com `DPoP-Nonce`
  - refresh inline
  - request autenticada ao PDS com `ath`
