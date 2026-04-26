# Android Dev

## Fisrt Time Setup

```sh
nix-shell
yarn
cp .env.example .env
cp google-services.json.example google-services.json
yarn prebuild
yarn android
```

## To test on an real android system
```sh
nix-shell
adb reverse tcp:8081 tcp:8081
yarn android
```

## On another shell
```sh
adb shell am start -a android.intent.action.VIEW -d "exp+bluesky://expo-development-client/?url=http%3A%2F%2F127.0.0.1%3A8081"
```