### Copied from https://catalog.redhat.com/software/containers/rhceph/grafana-rhel9/65788f9b931f85d84e770f5e?architecture=amd64&image=6571d84b8373b9f5b604534f&container-tabs=dockerfile on 11th January 2024
# Build stage 1

FROM openshift/golang-builder:rhel_8_golang_1.19 AS builder

COPY $REMOTE_SOURCE $REMOTE_SOURCE_DIR

WORKDIR $REMOTE_SOURCE_DIR/app

ENV GOFLAGS="-mod=vendor"

RUN go run -mod vendor build.go -dev build

# Build stage 2
FROM registry.redhat.io/ubi9/ubi-minimal:latest

# Update the image to get the latest CVE updates
RUN microdnf update -y

ENV PATH=/usr/share/grafana/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    GF_PATHS_CONFIG="/etc/grafana/grafana.ini" \
    GF_PATHS_DATA="/var/lib/grafana" \
    GF_PATHS_HOME="/usr/share/grafana" \
    GF_PATHS_LOGS="/var/log/grafana" \
    GF_PATHS_PLUGINS="/usr/share/grafana/plugins-bundled" \
    GF_PATHS_PROVISIONING="/etc/grafana/provisioning" \
    GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS="grafana-piechart-panel"

COPY plugins.tar /plugins.tar
RUN rm -rf $GF_PATHS_HOME && mkdir -p $GF_PATHS_HOME
COPY --from=builder $REMOTE_SOURCE_DIR/app/bin/grafana /usr/bin/grafana
COPY --from=builder $REMOTE_SOURCE_DIR/app/bin/grafana-server /usr/bin/grafana-server
COPY --from=builder $REMOTE_SOURCE_DIR/app/bin/grafana-cli /usr/bin/grafana-cli
COPY --from=builder $REMOTE_SOURCE_DIR/app/conf $GF_PATHS_HOME/conf/
COPY --from=builder $REMOTE_SOURCE_DIR/app/docs $GF_PATHS_HOME/docs/
COPY --from=builder $REMOTE_SOURCE_DIR/app/public $GF_PATHS_HOME/public/
COPY --from=builder $REMOTE_SOURCE_DIR/app/scripts $GF_PATHS_HOME/scripts/

RUN rm -rf /etc/grafana && mkdir -p /etc/grafana
COPY --from=builder $REMOTE_SOURCE_DIR/app/conf/sample.ini $GF_PATHS_CONFIG
COPY --from=builder $REMOTE_SOURCE_DIR/app/conf/ldap.toml /etc/grafana/ldap.toml
COPY ./run.sh /run.sh

# Create grafana user/group
RUN microdnf install -y shadow-utils
RUN groupadd -r -g 472 grafana
RUN useradd -r -u 472 -g grafana -d /etc/grafana -s /sbin/nologin -c "Grafana Dashboard" grafana

# Install grafana dashboards from Ceph
RUN microdnf install -y tar ceph-grafana-dashboards

# Copy ceph-dashboard yaml
COPY ceph-dashboard.yml "$GF_PATHS_PROVISIONING/dashboards/"

# Unpack plugins and update permissions
RUN mkdir -p "$GF_PATHS_HOME/.aws" && \
    mkdir -p "$GF_PATHS_PROVISIONING/datasources" \
             "$GF_PATHS_PROVISIONING/dashboards" \
             "$GF_PATHS_PROVISIONING/notifiers" \
             "$GF_PATHS_PROVISIONING/plugins" \
             "$GF_PATHS_PROVISIONING/access-control" \
             "$GF_PATHS_PROVISIONING/alerting" \
             "$GF_PATHS_LOGS" \
             "$GF_PATHS_PLUGINS" \
             "$GF_PATHS_DATA" && \
    tar -C "$GF_PATHS_PLUGINS" -xvf /plugins.tar && \
    chown -R grafana:grafana "$GF_PATHS_DATA" "$GF_PATHS_HOME/.aws" "$GF_PATHS_LOGS" "$GF_PATHS_PLUGINS" "$GF_PATHS_PROVISIONING" && \
    chmod -R 775 "$GF_PATHS_DATA" "$GF_PATHS_HOME/.aws" "$GF_PATHS_LOGS" "$GF_PATHS_PLUGINS" "$GF_PATHS_PROVISIONING" /run.sh

EXPOSE 3000

USER grafana
WORKDIR /
ENTRYPOINT [ "/run.sh" ]

# Build specific labels
LABEL maintainer="Boris Ranto <branto@redhat.com>"
LABEL com.redhat.component="grafana-container"
LABEL version=9.4.12
LABEL name="grafana"
LABEL description="Red Hat Ceph Storage Grafana container"
LABEL summary="Grafana container on RHEL 9 for Red Hat Ceph Storage"
LABEL io.k8s.display-name="Grafana on RHEL 9"
LABEL io.openshift.tags="rhceph ceph dashboard grafana"
