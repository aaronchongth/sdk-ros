# Intrinsic SDK for ROS

The Intrinsic SDK for ROS is a wrapper of the [Intrinsic
SDK](https://github.com/intrinsic-dev/sdk) that allows for software developers
to write ROS-based workflows that work with
[Flowstate](https://intrinsic.ai/flowstate), a web-based tool to build robot
solutions from concept to deployment.

The Intrinsic SDK for ROS is compatible with both [ROS 2 Lyrical Luth](https://docs.ros.org/en/lyrical/index.html) (default) and [ROS 2 Jazzy Jalisco](https://docs.ros.org/en/jazzy/index.html).

In addition to this [Intrinsic SDK for
ROS repository](https://github.com/intrinsic-dev/intrinsic_sdk_ros), there are
also:
 * [ROS-based SDK Examples](https://github.com/intrinsic-dev/sdk_examples_ros)
 * [The Intrinsic SDK](https://github.com/intrinsic-dev/sdk)
 * [Intrinsic SDK examples](https://github.com/intrinsic-dev/sdk-examples)
 * [Dev container project template](https://github.com/intrinsic-dev/project-template)

## Getting Started

Clone this repository into your ROS workspace.

```bash
cd ~/intrinsic_ws/src # Replace with source directory to your workspace.
git clone https://github.com/intrinsic-ai/sdk-ros.git
```

Source ROS and build the SDK.

```bash
source /opt/ros/lyrical/setup.bash  # Or: source /opt/ros/jazzy/setup.bash
cd ~/intrinsic_ws/
rosdep install -iry --from-paths src
colcon build \
  --cmake-args -DCMAKE_BUILD_TYPE=Release \
  --event-handlers=console_direct+
```

### Using the SDK in Python

To use the SDK in Python, you must additionally create a virtualenv and install a few dependencies which are not provided by the SDK, nor are the ones available in Ubuntu's apt new enough.

For example, you could:

```bash
# Setup the venv and activate it
python3 -m venv --system-site-packages venv
source ./venv/bin/activate
# Install the new dependencies
# (venv)
pip install -U grpcio protobuf retrying
# Test that it is working
# (venv)
python3 -c 'from intrinsic.world.python.object_world_client import ObjectWorldClient'
```

## Building with pixi (experimental)

As an alternative to apt + rosdep, the workspace can be built with [pixi](https://pixi.sh), using [RoboStack](https://robostack.github.io) ROS packages and conda-forge libraries.
This needs no ROS installed on the host.
The root `pixi.toml` targets `linux-64` with glibc >= 2.34 (Ubuntu 22.04 or newer, Debian 12 or newer), because the SDK uses `strerrordesc_np`.

### Fast build with the prebuilt SDK bundle (`lyrical` / `jazzy`)

The default `lyrical` and `jazzy` environments include `ros-<distro>-intrinsic-sdk-cmake-bundle`, a single `.conda` archive that pre-installs `intrinsic_sdk_cmake`, `intrinsic_sdk_bundle_library_py`, `inbuild`, and its 23 `*_vendor` dependencies into the pixi environment underlay.
When that bundle is present in `$CONDA_PREFIX`, the `build` task automatically passes `--packages-ignore` for those 25 packages and only compiles downstream packages (for example, `flowstate_interfaces` and `flowstate_ros_bridge` in ~50 seconds):

```bash
cd sdk-ros
pixi run -e lyrical build --packages-up-to flowstate_ros_bridge  # Or: -e jazzy
```

### Full source build without the prebuilt bundle (`lyrical-src` / `jazzy-src`)

To build `intrinsic_sdk_cmake` and the non-satisfied `*_vendor` packages from source inside the pixi environment instead of using the prebuilt bundle, use the `lyrical-src` or `jazzy-src` environment (~6 minutes cold):

```bash
cd sdk-ros
pixi run -e lyrical-src build --packages-up-to flowstate_ros_bridge  # Or: -e jazzy-src
```

### Isolation and running built packages

The `build` task adds the CMake arguments itself (Release, no tests, `-DINTRINSIC_SDK_CMAKE_BUILD_INBUILD=OFF`, `-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF`), so only pass colcon package-selection arguments.
It builds into `build/<env>` and installs into `install/<env>` (merged install).
It is isolated from the host: it runs with a clean environment (a sourced `/opt/ros` does not leak in), PATH is limited to the env plus `/usr/bin:/bin`, CMake searches the env first (`CMAKE_PREFIX_PATH`), and the Python user site (`~/.local`) is disabled.
`pixi run -e lyrical check-isolation` verifies the environment side of this.
To use the result:

```bash
pixi run --clean-env -e lyrical bash -c 'source install/lyrical/setup.bash && ros2 pkg executables flowstate_ros_bridge'
```

`-DINTRINSIC_SDK_CMAKE_BUILD_INBUILD=OFF` makes `intrinsic_sdk_cmake` download the released `inbuild` binary for the pinned SDK version instead of building it with Bazel.
The default (`ON`) keeps the Bazel build.

### Bundling a service container for Flowstate (`bundle-service`)

To build a service container image using [`service.pixi.Dockerfile`](intrinsic_sdk_bundle_library_py/resource/service.pixi.Dockerfile) (which downloads the prebuilt `.conda` bundle inside Docker and compiles only the target service package) and package it into a Flowstate `.bundle.tar` with `inbuild`:

```bash
cd sdk-ros
pixi run -e lyrical bundle-service flowstate_ros_bridge     # Or: -e jazzy
pixi run -e lyrical bundle-service flowstate_ros_gz_bridge  # Or: -e jazzy
```

This writes `./intrinsic_asset_bundles/<service_name>/<service_name>.bundle.tar`.

### Building and hosting the `.conda` SDK bundle

The `packaging` environment uses `rattler-build` (`packaging/recipe.yaml` and `packaging/build_bundle.sh`) to build `ros-lyrical-intrinsic-sdk-cmake-bundle` and `ros-jazzy-intrinsic-sdk-cmake-bundle` into `/opt/sdk-ros-pixi/channel/linux-64/`:

```bash
pixi run -e packaging build-bundle-lyrical
pixi run -e packaging build-bundle-jazzy
```

In `pixi.toml`, `[feature.lyrical-bundle.dependencies]` and `[feature.jazzy-bundle.dependencies]` can point either to the local `.conda` file (`{ path = "/opt/sdk-ros-pixi/channel/linux-64/..." }`) or directly to a GitHub Release asset URL (`{ url = "https://github.com/<owner>/sdk-ros/releases/download/<tag>/ros-<distro>-intrinsic-sdk-cmake-bundle-<version>-<hash>.conda" }`), without requiring a hosted conda channel.

## Building and packaging the flowstate_ros_bridge

See [Building the flowstate_ros_bridge bundle](flowstate_ros_bridge/README.md) for more details on how to build and package the bridge.
