# Android release signing

Production Android builds must use a dedicated release/upload key. The repository never stores the keystore or its passwords.

## Configure a local or CI release environment

1. Create or obtain the production keystore.
2. Copy `key.properties.example` to `key.properties`.
3. Replace all placeholders with the real keystore path, alias and passwords.
4. Build from `app/` with `flutter build appbundle --release` for Play distribution or `flutter build apk --release` for direct APK distribution.

`key.properties`, `*.jks` and `*.keystore` are ignored by git. Never commit them.

## Android App Links certificate

The `https://whiteslove.me/flat-finder` App Link is verified against the signing certificate declared by the site's `/.well-known/assetlinks.json`.

After choosing the production signing setup, obtain its SHA-256 certificate fingerprint and update the site entry for package `com.flatfinder.flat_finder`. For a directly distributed APK, use the certificate that signs that APK. If Google Play App Signing is enabled, include the Play app-signing certificate used on installed Play builds as well.

A local keystore fingerprint can be inspected with:

```sh
keytool -list -v -keystore /path/to/flat-finder-upload-key.jks -alias flat-finder-upload
```

Do not copy the CI certificate from the pull-request workflow into `assetlinks.json`: that key is disposable and exists only to prove that release packaging works.
