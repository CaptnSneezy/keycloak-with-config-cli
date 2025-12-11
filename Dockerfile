# --- Versions
ARG KC_VERSION=26.1.0

# --- Builder --- getting curl for healthcheck
FROM registry.access.redhat.com/ubi8 AS builder
LABEL stage=builder

RUN mkdir -p /mnt/rootfs
RUN dnf install --installroot /mnt/rootfs curl \
    --releasever 8 --setopt install_weak_deps=false --nodocs -y; \
    dnf --installroot /mnt/rootfs clean all

# --- Keycloak Base Image
FROM quay.io/keycloak/keycloak:${KC_VERSION}
COPY --from=builder /mnt/rootfs /

ENV KC_HEALTH_ENABLED=true
ENV KC_DB=postgres
ENV KC_HTTPS_KEY_STORE_FILE=/opt/keycloak/conf/truststore/server.p12

USER root

# --- Add start script
COPY scripts/kc-start.sh /opt/keycloak/kc-start.sh
RUN chmod +x /opt/keycloak/kc-start.sh

# --- Build Keycloak Server
RUN /opt/keycloak/bin/kc.sh build

# --- healthcheck with management port 9000
HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
    CMD curl -f -k --silent https://localhost:9000/health || exit 1

ENTRYPOINT ["/opt/keycloak/kc-start.sh"]