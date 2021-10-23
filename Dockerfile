#
# This Dockerfile packages a single SolarView proxy app (e.g. steca-fb, d0-fb).
#
# The image is created in two stages. The first stage downloads the binaries,
# stores the release date and selects the correct binaries for the architecture.
# The second image prepares runtime dependencies and defines the start command.
#

# 'buster' is preferred over 'stable' because bullseye requires at least
# libseccomp 2.4.2 on the host; for details, see
# https://github.com/debuerreotype/docker-debian-artifacts/issues/106#issuecomment-721887305
ARG RUNTIME_BASE_IMAGE=debian:buster-slim

# builder image, prepares the runtime image
FROM alpine AS builder
ARG TARGETARCH
ARG APP_NAME
RUN test -n "${APP_NAME}" || { echo >&2 "Missing build-arg: APP_NAME"; exit 1; }
ARG APP_ARCHIVE_URL="http://www.solarview.info/downloads/${APP_NAME}.zip"
ARG APP_ARCHIVE_FILE="/build/${APP_NAME}.zip"
ARG APP_BINARIES="${APP_NAME}"
ARG APP_HOME="/opt/${APP_NAME}"

WORKDIR "${APP_HOME}"
ADD "${APP_ARCHIVE_URL}" "${APP_ARCHIVE_FILE}"
# the 'unzip' package is used because busybox-unzip does not retain timestamps
RUN apk add unzip && unzip "${APP_ARCHIVE_FILE}"
RUN stat -c %y "${APP_ARCHIVE_FILE}" >.release_date
# select the binaries for the target architecture
RUN [ -z "${APP_BINARIES}" ] || { \
      target_arch="${TARGETARCH:-$(arch)}" && \
      case "${target_arch}" in \
        amd64)  sv_arch=x64   ;; \
        386)    sv_arch=x86   ;; \
        arm64)  sv_arch=rpi64 ;; \
        arm*)   sv_arch=rpi   ;; \
        mips)   sv_arch=7390  ;; \
        mipsel) sv_arch=71xx  ;; \
        *)      echo >&2 "Unsupported architecture: ${target_arch}" && exit 1;; \
      esac && \
      for binary in ${APP_BINARIES}; do \
        mv "${binary}" "${binary}.71xx" && \
        chmod +x "${binary}.${sv_arch}" && \
        ln -s "${binary}.${sv_arch}" "${binary}"; \
      done \
    }

# runtime image
FROM ${RUNTIME_BASE_IMAGE} AS runtime
ARG APP_NAME
ENV APP_NAME="${APP_NAME}"
ENV APP_HOME="/opt/${APP_NAME}"
ENV APP_RUNTIME="/var/opt/${APP_NAME}"
COPY --from=builder "${APP_HOME}" "${APP_HOME}"
# rpi binaries are linked against ld-linux-armhf.so.3
# which does not exist on debian arm/v6 (armel)
RUN case "${TARGETARCH:-$(arch)}" in \
      arm*) [ -e /lib/ld-linux-armhf.so.3 ] || [ ! -h /lib/ld-linux.so.3 ] || ln -s "$(realpath /lib/ld-linux.so.3)" /lib/ld-linux-armhf.so.3 ;; \
    esac
WORKDIR "${APP_RUNTIME}"

#
# When the container is started, the files from the release archive are copied to
# a runtime directory, which is mounted to the host. When a file on the host is
# newer, it is not overwritten. This technique allows to update the binaries and
# keep the user data without a special update mechanism.
#
CMD  [ "/bin/sh", "-c", "cp -u -a \"${APP_HOME}\"/* \"${APP_RUNTIME}/\" && \"./${APP_NAME}\" ${ARGS} && exec tail -f /dev/null" ]
VOLUME "${APP_RUNTIME}"
