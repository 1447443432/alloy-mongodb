ARG BASE_IMAGE=grafana/alloy:v1.21.2
FROM ${BASE_IMAGE}

RUN mkdir -p /usr/local/alloy-vlogs/bin /usr/local/alloy-vlogs/data \
    && ln -s /bin/alloy /usr/local/alloy-vlogs/bin/alloy

COPY config/alloy-config.alloy /usr/local/alloy-vlogs/config.alloy
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9081

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
