# Releasing just_image

Version 2 releases use two immutable publications: native binaries in GitHub
Releases and the Dart package on pub.dev.

## 1. Prepare native binaries

1. Ensure `pubspec.yaml`, `Cargo.toml` and `binaryVersion` contain the same
   version.
2. Run the **Prepare native release** workflow manually with that version.
3. The workflow builds all 12 supported assets, creates
   `native-v<version>`, generates SHA-256 values and opens a pull request.
4. Review and merge the generated hash pull request.

Temporary Actions artifacts use one-day retention and are deleted after the
GitHub Release is created. Do not cache or upload Cargo `target/` directories.

## 2. Verify the release candidate

```bash
dart pub get
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
```

Also verify the independent consumers:

```bash
(cd example/cli && dart run bin/main.dart)
(cd example/flutter_app && flutter test)
```

No `PENDING` entry may remain in `lib/src/hook_helpers/hashes.dart`.

## 3. Publish

Create and push the final tag:

```bash
git tag v<version>
git push origin v<version>
```

The **Publish to pub.dev** workflow checks the version, the 12 GitHub Release
assets, the embedded hashes and a zero-configuration Linux installation before
publishing with pub.dev OIDC.
