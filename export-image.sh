#!/bin/bash
set -e

IMAGE="registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-alloy-vlogs-mongodb-amd64:1.0.0"
OUT_DIR="./image-package"
OUT_FILE="${OUT_DIR}/hap-alloy-vlogs-mongodb-amd64-1.0.0.tar.gz"

mkdir -p "${OUT_DIR}"

echo ">>> 导出镜像: ${IMAGE}"
echo ">>> 输出文件: ${OUT_FILE}"

docker image inspect "${IMAGE}" >/dev/null

docker save "${IMAGE}" | gzip -c > "${OUT_FILE}"

ls -lh "${OUT_FILE}"

echo ">>> 导出完成"
