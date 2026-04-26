Sim. Para apontar esse fork para o **AppView do Mugen**, o mais interessante separa em 3 camadas:

**1. Backend ATProto/AppView**
A principal env é:

```env
EXPO_PUBLIC_BLUESKY_PROXY_DID=did:web:api.mugen.alguma-coisa
```

Ela é usada em [src/lib/constants.ts](/home/lucas/dev/web/mugen/social-app/src/lib/constants.ts:225) para montar o header:

```ts
atproto-proxy: <DID>#bsky_appview
```

Então o AppView do Mugen precisa ter um DID válido e expor o serviço `#bsky_appview`. Se ele também cuidar de notificações, precisa considerar `#bsky_notif`.

Se você tiver chat próprio:

```env
EXPO_PUBLIC_CHAT_PROXY_DID=did:web:chat.mugen.alguma-coisa
```

Se não tiver, deixa vazio e ele continua usando `did:web:api.bsky.chat`.

**2. Coisas que hoje ainda apontam para Bluesky**
Mesmo mudando o AppView, várias integrações continuam indo para serviços da Bluesky por fallback:

```env
EXPO_PUBLIC_METRICS_API_HOST=
EXPO_PUBLIC_GROWTHBOOK_API_HOST=
EXPO_PUBLIC_GROWTHBOOK_CLIENT_KEY=
GEOLOCATION_DEV_URL=
LIVE_EVENTS_DEV_URL=
APP_CONFIG_DEV_URL=
```

Se você quer um app Mugen “limpo”, eu não deixaria métricas e feature flags mandando dados para Bluesky. O código hoje usa fallback para `https://events.bsky.app`, então o ideal é apontar para endpoints seus ou alterar o código para desabilitar métricas em dev/fork.

Exemplo:

```env
EXPO_PUBLIC_METRICS_API_HOST=https://events.mugen...
EXPO_PUBLIC_GROWTHBOOK_API_HOST=https://growthbook.mugen...
APP_CONFIG_DEV_URL=https://app-config.mugen...
```

Ou remover/desligar essas chamadas no código.

**3. Identidade do app**
Para ter “meu próprio app” mesmo, não basta AppView. Você vai querer trocar em [app.config.js](/home/lucas/dev/web/mugen/social-app/app.config.js:48):

```js
name: 'Mugen'
slug: 'mugen'
scheme: 'mugen'
android.package: 'algum.pacote.mugen'
ios.bundleIdentifier: 'algum.pacote.mugen'
```

Também trocar:

- `xyz.blueskyweb.app`
- `bsky.app`
- `bluesky://`
- `updates.bsky.app`
- nomes de share extension/notificação
- intent filters/app links
- Firebase `google-services.json` para o novo package Android

Um ponto importante: push notification tem hardcode em [src/lib/notifications/notifications.ts](/home/lucas/dev/web/mugen/social-app/src/lib/notifications/notifications.ts:32):

```ts
serviceDid: PUBLIC_APPVIEW_DID
appId: 'xyz.blueskyweb.app'
```

Para push do Mugen funcionar direito, isso provavelmente precisa virar algo baseado em `BLUESKY_PROXY_DID` e no novo app id, não no AppView público da Bluesky.

Para começar do jeito mais pragmático, eu faria assim:

```env
EXPO_PUBLIC_ENV=development
EXPO_PUBLIC_BLUESKY_PROXY_DID=did:web:SEU_APPVIEW_MUGEN
EXPO_PUBLIC_CHAT_PROXY_DID=
EXPO_PUBLIC_METRICS_API_HOST=http://127.0.0.1:9
EXPO_PUBLIC_GROWTHBOOK_API_HOST=http://127.0.0.1:9
EXPO_PUBLIC_GROWTHBOOK_CLIENT_KEY=
EXPO_PUBLIC_SENTRY_DSN=
EXPO_PUBLIC_BITDRIFT_API_KEY=
```

Aí primeiro valida: login, feed, perfil, post, notificações básicas. Depois você troca branding/package/Firebase/links para transformar isso de “fork apontando para Mugen” em app Mugen de verdade.