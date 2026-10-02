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

# Build up the service using pixi and the prebuilt intrinsic_sdk_cmake .conda bundle:
#   - build: installs the locked pixi env (with prebuilt SDK bundle) and compiles only ${SERVICE_PACKAGE}
#   - runtime: debian:trixie-slim + pixi env + /opt/ros/overlay/install

ARG PIXI_VERSION=0.81.0
FROM ghcr.io/prefix-dev/pixi:${PIXI_VERSION} AS build

ARG ROS_DISTRO=lyrical
ARG SOURCE_DIR=src/sdk-ros
ARG OVERLAY_SOURCE=src
ARG SERVICE_PACKAGE
ARG SERVICE_NAME

WORKDIR /opt/sdk-ros-pixi/ws

# 1. Copy pixi manifest and lockfile first so Docker BuildKit caches the entire
#    pixi environment (including the prebuilt .conda bundle from GitHub Releases)
#    whenever pixi.toml and pixi.lock are unchanged.
COPY ${SOURCE_DIR}/pixi.toml ${SOURCE_DIR}/pixi.lock ./
RUN pixi install -e ${ROS_DISTRO} \
 && pixi shell-hook -e ${ROS_DISTRO} -s bash > /opt/sdk-ros-pixi/activate.sh

# 2. Copy workspace sources and build only the target service package.
#    Install into /opt/ros/overlay/install so `intrinsic_sdk_build bundle` finds
#    /opt/ros/overlay/install/share/${SERVICE_PACKAGE}/${SERVICE_NAME}_protos.desc.
COPY ${OVERLAY_SOURCE} /opt/sdk-ros-pixi/ws/src
RUN pixi run -e ${ROS_DISTRO} build \
      --base-paths /opt/sdk-ros-pixi/ws/src \
      --install-base /opt/ros/overlay/install \
      --packages-up-to ${SERVICE_PACKAGE} \
 && if [ -n "${SERVICE_NAME:-}" ] && \
       [ -f "/opt/ros/overlay/install/share/${SERVICE_PACKAGE}/${SERVICE_NAME}/${SERVICE_NAME}_protos.desc" ] && \
       [ ! -f "/opt/ros/overlay/install/share/${SERVICE_PACKAGE}/${SERVICE_NAME}_protos.desc" ]; then \
      ln -s "${SERVICE_NAME}/${SERVICE_NAME}_protos.desc" \
        "/opt/ros/overlay/install/share/${SERVICE_PACKAGE}/${SERVICE_NAME}_protos.desc"; \
    fi

# 3. Slim runtime stage: keeps the pixi environment at the exact same
#    /opt/sdk-ros-pixi/ws/.pixi path so RPATHs and shebangs do not relocate.
FROM debian:trixie-slim

ARG ROS_DISTRO=lyrical
ARG SERVICE_PACKAGE
ARG SERVICE_NAME
ARG SERVICE_EXECUTABLE_NAME=${SERVICE_NAME}_main

COPY --from=build /opt/sdk-ros-pixi/ws/.pixi/envs/${ROS_DISTRO} /opt/sdk-ros-pixi/ws/.pixi/envs/${ROS_DISTRO}
COPY --from=build /opt/sdk-ros-pixi/activate.sh /opt/sdk-ros-pixi/activate.sh
COPY --from=build /opt/ros/overlay/install /opt/ros/overlay/install

ENV SERVICE_PACKAGE=${SERVICE_PACKAGE} \
    SERVICE_NAME=${SERVICE_NAME} \
    SERVICE_EXECUTABLE_NAME=${SERVICE_EXECUTABLE_NAME} \
    RMW_IMPLEMENTATION=rmw_zenoh_cpp \
    ROS_HOME=/tmp \
    ZENOH_CONFIG_OVERRIDE='connect/endpoints=["tcp/zenoh-router.app-intrinsic-base.svc.cluster.local:7447"]'

CMD ["bash", "-c", ". /opt/sdk-ros-pixi/activate.sh && . /opt/ros/overlay/install/setup.bash && exec /opt/ros/overlay/install/lib/${SERVICE_PACKAGE}/${SERVICE_EXECUTABLE_NAME}"]
