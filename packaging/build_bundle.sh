#!/usr/bin/env bash
set -euo pipefail

# Move ros2-ros-workspace's top-level setup files out of $PREFIX before colcon runs.
# Using `mv` (rather than `cp`) ensures colcon cannot truncate hardlinked files
# in ~/.cache/rattler/cache/pkgs/ in-place, and moving them back afterwards
# restores the exact original inodes so rattler-build does not package them.
BACKUP_DIR="$SRC_DIR/_prefix_setup_backup"
mkdir -p "$BACKUP_DIR"
SETUP_FILES=(
  _local_setup_util.py
  _local_setup_util_sh.py
  _local_setup_util_ps1.py
  setup.sh setup.bash setup.zsh setup.fish setup.ps1
  local_setup.sh local_setup.bash local_setup.zsh local_setup.fish local_setup.ps1
)
for f in "${SETUP_FILES[@]}"; do
  if [ -e "$PREFIX/$f" ]; then
    mv "$PREFIX/$f" "$BACKUP_DIR/$f"
  fi
done

mkdir -p "${CCACHE_DIR:-/opt/sdk-ros-pixi/ccache}"
export CCACHE_NOHASHDIR=1
touch "$PREFIX/COLCON_IGNORE"

# Restrict PATH to the conda build prefix plus /usr/bin:/bin (for /bin/sh in
# fetch_sdk.cmake PATCH_COMMAND) so host tools/libraries in ~/.local or ~/.cargo
# cannot leak into CMake's find_package search paths.
export PATH="$PREFIX/bin:/usr/bin:/bin"
export CMAKE_PREFIX_PATH="$PREFIX"
export AMENT_PREFIX_PATH="$PREFIX"
export PYTHONNOUSERSITE=1
export CMAKE_GENERATOR=Ninja

colcon build \
  --base-paths . \
  --merge-install \
  --build-base "$SRC_DIR/_build" \
  --install-base "$PREFIX" \
  --packages-up-to intrinsic_sdk_cmake \
  --cmake-args \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
    -DINTRINSIC_SDK_CMAKE_BUILD_INBUILD=OFF \
    -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF \
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache

# Remove colcon's top-level prefix files and restore ros2-ros-workspace's original inodes.
rm -f \
  "$PREFIX/.colcon_install_layout" \
  "$PREFIX/COLCON_IGNORE"
for f in "${SETUP_FILES[@]}"; do
  rm -f "$PREFIX/$f"
  if [ -e "$BACKUP_DIR/$f" ]; then
    mv "$BACKUP_DIR/$f" "$PREFIX/$f"
  fi
done
rm -rf "$BACKUP_DIR" "$SRC_DIR/_build" "$SRC_DIR/log"

# Add all $PREFIX/opt/*_vendor/lib directories to the RPATH of libintrinsic_sdk_cmake.so
# and the vendored shared libraries so rattler-build relocates them to $ORIGIN-relative
# RPATHs. This ensures both link-time (-Wl,--copy-dt-needed-entries) and runtime library
# resolution work even without LD_LIBRARY_PATH.
VENDOR_RPATH="$PREFIX/lib"
for d in "$PREFIX"/opt/*_vendor/lib; do
  if [ -d "$d" ]; then
    VENDOR_RPATH="$VENDOR_RPATH:$d"
  fi
done
for so in "$PREFIX/lib/libintrinsic_sdk_cmake.so" "$PREFIX"/opt/*_vendor/lib/*.so*; do
  if [ -f "$so" ] && [ ! -L "$so" ]; then
    patchelf --set-rpath "$VENDOR_RPATH" "$so"
  fi
done

# Install an activation script so $CONDA_PREFIX/opt/*_vendor is also on
# CMAKE_PREFIX_PATH and LD_LIBRARY_PATH whenever the environment is activated.
mkdir -p "$PREFIX/etc/conda/activate.d"
cat > "$PREFIX/etc/conda/activate.d/ros-intrinsic-sdk-cmake-bundle.sh" <<'EOF'
if [ -n "${CONDA_PREFIX:-}" ] && [ -d "${CONDA_PREFIX}/opt" ]; then
  for _vendor_dir in "${CONDA_PREFIX}"/opt/*_vendor; do
    if [ -d "${_vendor_dir}" ]; then
      export CMAKE_PREFIX_PATH="${_vendor_dir}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
    fi
    if [ -d "${_vendor_dir}/lib" ]; then
      export LD_LIBRARY_PATH="${_vendor_dir}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    fi
  done
  unset _vendor_dir
fi
EOF
