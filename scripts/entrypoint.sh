#!/bin/sh
set -e

echo "============================================================================="
echo ">>> Starting Alloy"
echo "============================================================================="

ALLOY_HOME="/usr/local/alloy-vlogs"
ALLOY_BIN="${ALLOY_HOME}/bin/alloy"

: "${VICTORIALOGS_IP:=}"
: "${VICTORIALOGS_PORT:=9428}"
: "${MONITOR_AUTH_USERNAME:=}"
: "${MONITOR_AUTH_PASSWORD:=}"
: "${MONGODB_LOG_PATH:=/data/logs/mongodb/mongodb.log}"

if [ -z "${VICTORIALOGS_IP}" ]; then
  echo ">>> ERROR: VICTORIALOGS_IP is required" >&2
  exit 1
fi
if [ -z "${MONITOR_AUTH_USERNAME}" ]; then
  echo ">>> ERROR: MONITOR_AUTH_USERNAME is required" >&2
  exit 1
fi
if [ -z "${MONITOR_AUTH_PASSWORD}" ]; then
  echo ">>> ERROR: MONITOR_AUTH_PASSWORD is required" >&2
  exit 1
fi

if [ -z "${MONGODB_HOSTNAME}" ]; then
  if [ -r /host/etc/hostname ]; then
    MONGODB_HOSTNAME="$(tr -d '\r\n' < /host/etc/hostname)"
  else
    MONGODB_HOSTNAME="$(hostname)"
  fi
fi
: "${MONGODB_HOSTNAME:=mongodb}"

if [ -z "${MONGODB_JOB_NAME}" ]; then
  if [ -n "${MONGODB_SERVER_IP:-}" ]; then
    MONGODB_JOB_NAME="mongodb-${MONGODB_SERVER_IP}"
  elif [ -n "${MONGODB_INSTANCE_ID:-}" ]; then
    MONGODB_JOB_NAME="mongodb-${MONGODB_INSTANCE_ID}"
  elif [ -r /host/etc/machine-id ]; then
    MONGODB_INSTANCE_ID="$(tr -d '\r\n' < /host/etc/machine-id | cut -c1-12)"
    if [ -n "${MONGODB_INSTANCE_ID}" ]; then
      MONGODB_JOB_NAME="mongodb-${MONGODB_INSTANCE_ID}"
    fi
  fi

  if [ -z "${MONGODB_JOB_NAME}" ]; then
    echo ">>> ERROR: set MONGODB_SERVER_IP, MONGODB_INSTANCE_ID, or MONGODB_JOB_NAME" >&2
    exit 1
  fi
fi

VICTORIALOGS_PUSH_URL="http://${VICTORIALOGS_IP}:${VICTORIALOGS_PORT}/insert/loki/api/v1/push?preserve_json_keys=attr&_stream_fields=job,host,instance"

export VICTORIALOGS_PUSH_URL MONITOR_AUTH_USERNAME MONITOR_AUTH_PASSWORD
export MONGODB_LOG_PATH MONGODB_SERVER_IP MONGODB_INSTANCE_ID MONGODB_JOB_NAME MONGODB_HOSTNAME

echo ">>> Alloy binary: ${ALLOY_BIN}"

exec "${ALLOY_BIN}" run \
  --server.http.listen-addr=0.0.0.0:9081 \
  --storage.path="${ALLOY_HOME}/data" \
  "${ALLOY_HOME}/config.alloy"
