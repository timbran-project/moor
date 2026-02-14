# meadow_flutter

Flutter spike for `clients/meadow`.

## Run (Linux desktop)

Flutter desktop passes CLI args to `main(List<String> args)` via `--dart-entrypoint-args` (`-a`),
not via `-- ...`.

Recommended:

```bash
cd clients/meadow_flutter
./tool/run_linux.sh --server=http://localhost:8080 --username=archwizard --password=potrzebie --login
```

Without the helper script:

```bash
cd clients/meadow_flutter
flutter run -d linux \
  -a --server=http://localhost:8080 \
  -a --username=archwizard \
  -a --password=potrzebie \
  -a --login
```

## FlatBuffers codegen

```bash
cd clients/meadow_flutter
./tool/gen_flatbuffers.sh
```
