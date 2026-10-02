#!/usr/bin/env bash
# Copyright 2026 Intrinsic Innovation LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

ROS_DISTRO="${PIXI_ENVIRONMENT_NAME:-lyrical}"
ROS_DISTRO="${ROS_DISTRO%-src}"
SERVICE_PACKAGE=""
SERVICE_NAME=""
MANIFEST_PATH=""
DEFAULT_CONFIG=""
BUNDLE_DIR="./intrinsic_asset_bundles"
EXTRA_CONTAINER_ARGS=()

show_help() {
  cat <<EOF
Usage: $(basename "$0") <SERVICE_PACKAGE> [OPTIONS]
   or: $(basename "$0") --service_package <SERVICE_PACKAGE> [OPTIONS]

Build and bundle a ROS service container image for Flowstate using pixi and
service.pixi.Dockerfile. Can be run either from the sdk-ros repository root
(e.g. via \`pixi run -e lyrical bundle-service flowstate_ros_gz_bridge\`) or
from the root of a colcon workspace containing \`src/sdk-ros\`.

Options:
  -h, --help                         Show this help message and exit
  --service_package, --service-package PKG
                                     ROS package name (e.g. flowstate_ros_bridge, flowstate_ros_gz_bridge)
  --service_name, --service-name NAME
                                     Service name (auto-detected from *.manifest.textproto if omitted)
  --ros_distro, --ros-distro DISTRO  ROS distro: lyrical or jazzy (default: $ROS_DISTRO)
  --manifest_path, --manifest-path PATH
                                     Path to *.manifest.textproto (auto-detected if omitted)
  --default_config, --default-config PATH
                                     Path to *_default_config.pbtxt (auto-detected if omitted)
  --bundle_dir, --bundle-dir, --images_dir, --images-dir DIR
                                     Output directory (default: ./intrinsic_asset_bundles)
  --no-cache                         Do not use Docker build cache
  --keep-builder                     Do not stop the buildx builder after build
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    --service_package|--service-package)
      SERVICE_PACKAGE="$2"
      shift 2
      ;;
    --service_name|--service-name)
      SERVICE_NAME="$2"
      shift 2
      ;;
    --ros_distro|--ros-distro)
      ROS_DISTRO="$2"
      shift 2
      ;;
    --manifest_path|--manifest-path)
      MANIFEST_PATH="$2"
      shift 2
      ;;
    --default_config|--default-config)
      DEFAULT_CONFIG="$2"
      shift 2
      ;;
    --bundle_dir|--bundle-dir|--images_dir|--images-dir)
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --no-cache|--keep-builder)
      EXTRA_CONTAINER_ARGS+=("$1")
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 1
      ;;
    *)
      if [[ -z "$SERVICE_PACKAGE" ]]; then
        SERVICE_PACKAGE="$1"
        shift
      else
        echo "Unexpected positional argument: $1" >&2
        show_help >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$SERVICE_PACKAGE" ]]; then
  echo "Error: SERVICE_PACKAGE is required (e.g. flowstate_ros_bridge or flowstate_ros_gz_bridge)." >&2
  show_help >&2
  exit 1
fi

# Detect whether we are running from sdk-ros root or a parent colcon workspace root.
if [[ -f "pixi.toml" && -d "intrinsic_sdk_bundle_library_py" ]]; then
  SOURCE_DIR="."
  OVERLAY_SOURCE="."
elif [[ -f "src/sdk-ros/pixi.toml" ]]; then
  SOURCE_DIR="src/sdk-ros"
  OVERLAY_SOURCE="src"
else
  echo "Error: Run this script either from the sdk-ros root or from a workspace root containing src/sdk-ros." >&2
  exit 1
fi

DOCKERFILE="${SOURCE_DIR}/intrinsic_sdk_bundle_library_py/resource/service.pixi.Dockerfile"

# Locate the package directory under OVERLAY_SOURCE.
PKG_DIR=""
if [[ -d "${OVERLAY_SOURCE}/${SERVICE_PACKAGE}" && -f "${OVERLAY_SOURCE}/${SERVICE_PACKAGE}/package.xml" ]]; then
  PKG_DIR="${OVERLAY_SOURCE}/${SERVICE_PACKAGE}"
elif [[ -d "${SOURCE_DIR}/${SERVICE_PACKAGE}" && -f "${SOURCE_DIR}/${SERVICE_PACKAGE}/package.xml" ]]; then
  PKG_DIR="${SOURCE_DIR}/${SERVICE_PACKAGE}"
else
  PKG_DIR="$(python3 - "$OVERLAY_SOURCE" "$SERVICE_PACKAGE" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET
root = pathlib.Path(sys.argv[1])
target = sys.argv[2]
for pkg_xml in root.rglob("package.xml"):
    if ".pixi" in pkg_xml.parts or "build" in pkg_xml.parts or "install" in pkg_xml.parts:
        continue
    try:
        name = ET.parse(pkg_xml).getroot().findtext("name", "").strip()
        if name == target:
            print(pkg_xml.parent)
            break
    except Exception:
        pass
PY
)"
fi

if [[ -z "$PKG_DIR" || ! -d "$PKG_DIR" ]]; then
  echo "Error: Could not find package directory for '${SERVICE_PACKAGE}' under '${OVERLAY_SOURCE}'." >&2
  exit 1
fi

# Auto-detect manifest_path if not specified.
if [[ -z "$MANIFEST_PATH" ]]; then
  mapfile -t _manifests < <(find "$PKG_DIR" -maxdepth 2 -name "*.manifest.textproto" | sort)
  if [[ ${#_manifests[@]} -eq 0 ]]; then
    echo "Error: No *.manifest.textproto found in ${PKG_DIR}." >&2
    exit 1
  fi
  MANIFEST_PATH="${_manifests[0]}"
fi

# Auto-detect service_name from the manifest if not specified.
if [[ -z "$SERVICE_NAME" ]]; then
  SERVICE_NAME="$(python3 - "$MANIFEST_PATH" <<'PY'
import pathlib, re, sys
content = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r'id\s*\{\s*[^^{}]*name:\s*"([^"]+)"', content, re.DOTALL)
if not m:
    sys.exit(1)
print(m.group(1))
PY
)"
fi

# Auto-detect default_config if not specified.
if [[ -z "$DEFAULT_CONFIG" ]]; then
  mapfile -t _configs < <(find "$PKG_DIR" -maxdepth 2 -name "*_default_config.pbtxt" | sort)
  if [[ ${#_configs[@]} -gt 0 ]]; then
    DEFAULT_CONFIG="${_configs[0]}"
  fi
fi

# Ensure .dockerignore in current working directory excludes .pixi and build/install trees.
if [[ ! -f ".dockerignore" ]] || ! grep -q '^\*\*/\.pixi$' ".dockerignore" 2>/dev/null; then
  for entry in images intrinsic_asset_bundles build "**/build" log "**/log" install "**/install" .pixi "**/.pixi" .git "**/.git"; do
    grep -qxF "$entry" .dockerignore 2>/dev/null || echo "$entry" >> .dockerignore
  done
fi

echo "==> Building service container for ${SERVICE_PACKAGE} (service_name=${SERVICE_NAME}, distro=${ROS_DISTRO})"
python3 -m intrinsic_sdk_bundle_library_py.build container \
  --ros_distro "$ROS_DISTRO" \
  --service_package "$SERVICE_PACKAGE" \
  --service_name "$SERVICE_NAME" \
  --dockerfile "$DOCKERFILE" \
  --source-dir "$SOURCE_DIR" \
  --overlay-source "$OVERLAY_SOURCE" \
  --bundle_dir "$BUNDLE_DIR" \
  "${EXTRA_CONTAINER_ARGS[@]}"

BUNDLE_ARGS=(
  --service_package "$SERVICE_PACKAGE"
  --service_name "$SERVICE_NAME"
  --manifest_path "$MANIFEST_PATH"
  --bundle_dir "$BUNDLE_DIR"
)
if [[ -n "$DEFAULT_CONFIG" ]]; then
  BUNDLE_ARGS+=(--default_config "$DEFAULT_CONFIG")
fi

echo "==> Bundling ${SERVICE_NAME}.bundle.tar with inbuild"
python3 -m intrinsic_sdk_bundle_library_py.build bundle "${BUNDLE_ARGS[@]}"
echo "==> Done: ${BUNDLE_DIR}/${SERVICE_NAME}/${SERVICE_NAME}.bundle.tar"
