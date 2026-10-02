include(FetchContent)
# Pinned to commits (not branches) so builds are reproducible and packages built from this repo are stable.
# To bump: pick a commit, then update the URL and the sha256 of its archive (curl -sL <url> | sha256sum).
FetchContent_Declare(
  googleapis
  URL https://github.com/googleapis/googleapis/archive/d6ec9a598ecbcb3458b9e09ad7339af0ab8a71fe.tar.gz
  URL_HASH SHA256=e6ebfb89657a03a5aac977529ac9c45d4cd39e3fb9a432369f260efe20dbb002
  DOWNLOAD_EXTRACT_TIMESTAMP FALSE
)
FetchContent_MakeAvailable(googleapis)

FetchContent_Declare(
  grpc_gateway
  URL https://github.com/grpc-ecosystem/grpc-gateway/archive/2cc5ecd8474fe67c0f1793e0ea6dbcb7819f1bd5.tar.gz
  URL_HASH SHA256=d8d26ffacfade76e111c228ef169d23a35fe82c9e1565c23a3f4e667502be81d
  DOWNLOAD_EXTRACT_TIMESTAMP FALSE
)
FetchContent_MakeAvailable(grpc_gateway)

FetchContent_Declare(
  cel_spec
  GIT_REPOSITORY https://github.com/google/cel-spec
  GIT_TAG        v0.25.1
)
FetchContent_MakeAvailable(cel_spec)
