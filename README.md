# alloy-mongodb

GitHub Actions 使用 amd64/arm64 两个原生 Runner 分别构建镜像，暂不合并统一多架构 manifest。

默认本地构建镜像名：

```text
registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-alloy-vlogs-mongodb-amd64:1.0.0
registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-alloy-vlogs-mongodb-arm64:1.0.0
```

这里的主镜像名只用于 Docker build、Docker save 和 Release 打包，不需要登录主仓库。

## Alloy 部署

本项目使用 Grafana Alloy 读取宿主机挂载进容器的 MongoDB 日志文件，再通过 Loki Push API 写入 VictoriaLogs：

```bash
docker compose up -d
```

Compose 中列出 Alloy 运行所需的变量，并提供了可修改的示例值，请根据实际部署环境调整。`config/alloy.env` 不会挂载到容器内；`VICTORIALOGS_PUSH_URL` 由 entrypoint 根据 `VICTORIALOGS_IP` 和 `VICTORIALOGS_PORT` 自动生成，无需单独配置。`MONITOR_AUTH_USERNAME` 和 `MONITOR_AUTH_PASSWORD` 是与 `monitor-victorialogs-grafana` 项目共用的认证变量。

Compose 文件只列出通常需要修改的 5 个部署变量。可选的实例标识变量由 entrypoint 统一处理，具体规则见下文；默认的 `MONGODB_JOB_NAME` 根据宿主机 machine-id 生成。如果需要固定实例标识，可在 `environment` 中增加对应变量，或在启动容器时显式传入。

Compose 使用普通 bridge 网络即可。`network_mode: host` 不是必需项：日志通过只读 bind mount 进入容器，VictoriaLogs 使用明确的目标 IP 访问；只有需要访问宿主机 `localhost` 服务、使用宿主机端口绑定或依赖主机网络广播时，才考虑 host 网络。Alloy 的状态和文件读取位置保存在 `./alloy-data`，容器重启后可以继续从上次位置读取。

Alloy HTTP 服务在容器内监听 `9081`，Compose 默认不发布该端口到宿主机。需要临时访问 Alloy 调试页面或健康检查时，再在 Compose 服务中增加：

```yaml
ports:
  - "127.0.0.1:9081:9081"
```

变量优先级为：宿主机环境变量 `> docker compose --env-file 指定的文件 > Compose 默认值`。`config/alloy.env` 不会挂载进容器；它只是可选的 Compose 参数文件。

```bash
MONITOR_AUTH_USERNAME=myuser MONITOR_AUTH_PASSWORD=mypassword \
VICTORIALOGS_IP=10.206.0.5 MONGODB_SERVER_IP=10.206.0.8 \
docker compose --env-file ./config/alloy.env up -d
```

Alloy 启动脚本默认将 VictoriaLogs 地址设置为同一 Compose 网络中的服务名 `hap-monitor-logs`。Compose 中保留 `10.206.0.5` 作为独立部署的可编辑示例；同一 Compose 可改为 `hap-monitor-logs`，删除该变量或留空时由 entrypoint 使用默认值：

```yaml
VICTORIALOGS_IP: hap-monitor-logs
VICTORIALOGS_PORT: 9428
MONITOR_AUTH_USERNAME: myuser
MONITOR_AUTH_PASSWORD: mypassword
```

此默认值要求 Alloy 与 `monitor-victorialogs-grafana` 位于同一个 Compose 网络中。单独部署 Alloy 时，必须通过宿主机环境变量或 `config/alloy.env` 覆盖为 VictoriaLogs 所在主机的 IP 或可解析主机名。例如：

```bash
VICTORIALOGS_IP=10.206.0.5 docker compose --env-file ./config/alloy.env up -d
```

虽然变量名保留为 `VICTORIALOGS_IP`，但实际支持 IP、DNS 名称和 Compose 服务名。

`MONGODB_HOSTNAME` 默认从宿主机 `/etc/hostname` 自动获取，仅用于展示，不作为唯一标识。`MONGODB_JOB_NAME` 的生成优先级为：手工指定的 `MONGODB_JOB_NAME`，其次是 `mongodb-<MONGODB_SERVER_IP>`，再其次是 `mongodb-<MONGODB_INSTANCE_ID>`，最后使用宿主机 `/etc/machine-id` 前 12 位自动生成。如果这些标识都不可用，Alloy 会拒绝启动，避免产生重复来源标识。现场参数统一修改 `config/alloy.env` 中的 `VICTORIALOGS_IP`、`VICTORIALOGS_PORT`、`MONITOR_AUTH_USERNAME`、`MONITOR_AUTH_PASSWORD`、`MONGODB_SERVER_IP` 和 `MONGODB_LOG_PATH`；`VICTORIALOGS_PUSH_URL` 会由最终生效的地址和端口拼接生成。生产环境建议改用 Docker Secrets 或外部密钥管理，避免将密码直接写入镜像或配置文件。

容器内目录与 Alloy 部署文档保持一致：

```text
/usr/local/alloy-vlogs/bin/alloy    # Alloy 程序
/usr/local/alloy-vlogs/config.alloy # Alloy 配置
/usr/local/alloy-vlogs/data        # Alloy 运行状态和读取位置
```

`VICTORIALOGS_PUSH_URL` 默认带有 `preserve_json_keys=attr` 和 `_stream_fields=job,host,instance`，用于保留 MongoDB 慢查询 JSON 字段并控制 VictoriaLogs 的 stream 字段。

### 部署变量

部署时需要确认下面 5 项：

| 变量 | 配置状态 | 默认值 | 示例 | 用途 |
|---|---|---|---|---|
| `VICTORIALOGS_IP` | 需要确认 | `hap-monitor-logs` | `10.206.0.5` | VictoriaLogs 地址；同一 Compose 可填写服务名 |
| `VICTORIALOGS_PORT` | 需要确认 | `9428` | `9428` | VictoriaLogs HTTP 端口 |
| `MONITOR_AUTH_USERNAME` | 必填 | 无 | `myuser` | VictoriaLogs 认证用户名 |
| `MONITOR_AUTH_PASSWORD` | 必填 | 无 | `mypassword` | VictoriaLogs 认证密码，生产环境必须修改 |
| `MONGODB_SERVER_IP` | 建议填写 | 使用 machine-id 自动生成 | `10.206.0.8` | 生成唯一任务名 `mongodb-10.206.0.8` |

可选变量和默认值：

| 变量 | 是否填写 | 默认值 | 用途 |
|---|---|---|---|
| `MONGODB_LOG_PATH` | 否 | `/data/logs/mongodb/mongodb.log` | 容器内日志路径，需与挂载目标一致 |
| `MONGODB_JOB_NAME` | 否 | 自动生成 | 手工指定唯一任务名时使用，建议以 `mongodb-` 开头 |
| `MONGODB_INSTANCE_ID` | 否 | 空 | 没有服务器 IP 时，指定稳定实例标识 |
| `MONGODB_HOSTNAME` | 否 | 自动读取宿主机 hostname | 仅用于展示，不作为唯一标识 |
| `VICTORIALOGS_PUSH_URL` | 不填写 | 自动生成 | Alloy 写入 VictoriaLogs 的地址 |


### 镜像内置路径与运行参数

容器启动后由 `/usr/local/bin/entrypoint.sh` 完成参数处理，再启动 Alloy：

1. 检查认证变量；
2. 设置 VictoriaLogs 地址、端口和推送地址；
3. 生成 MongoDB 任务标识和 hostname；
4. 使用 `/usr/local/alloy-vlogs/config.alloy` 启动 Alloy。

| 项目 | 容器内路径或值 | Compose 处理 | 用途 |
|---|---|---|---|
| 启动脚本 | `/usr/local/bin/entrypoint.sh` | 镜像内置 | 处理默认值、认证校验和实例标识 |
| Alloy 程序 | `/usr/local/alloy-vlogs/bin/alloy` | 镜像内置 | Alloy 可执行文件；指向基础镜像中的 Alloy 程序 |
| Alloy 配置 | `/usr/local/alloy-vlogs/config.alloy` | 镜像内置 | 读取日志、过滤慢查询并写入 VictoriaLogs |
| Alloy 状态目录 | `/usr/local/alloy-vlogs/data` | 挂载 `/data/alloy-data` | 保存文件读取位置，避免重启后重复采集 |
| MongoDB 日志 | `/data/logs/mongodb/mongodb.log` | 只读挂载宿主机日志文件 | Alloy 读取的日志文件 |
| 宿主机 hostname | `/host/etc/hostname` | 只读挂载 | 自动生成展示用 hostname |
| 宿主机 machine-id | `/host/etc/machine-id` | 只读挂载 | 生成稳定的唯一任务标识 |
| Alloy HTTP 服务 | `0.0.0.0:9081` | 默认不发布到宿主机 | 管理页面和健康检查；需要时手动映射端口 |

### 生成测试慢查询日志

:::warning 说明
- 以下命令仅用于测试采集链路，会向 `/data/logs/mongodb/mongodb.log` 追加 15 条耗时大于 1000ms 的 MongoDB 慢查询日志。日志中的表 ID、数据库名、UUID 和签名均为脱敏示例；每条日志写入时使用当前 UTC 时间。
- `/data/logs/mongodb/mongodb.log` 注意改为实际的日志路径
:::

#### Linux 基础命令版

不依赖 Python，使用 Bash、`date` 和 `cat`：

随机生成 3 个表名，共写入 15 条日志；每个表写入 5 条，每次写入间隔 1 秒，确保同一 `ns` 有多个时间点。

```bash
sudo bash <<'BASH'
set -eu

LOG_FILE=/data/logs/mongodb/mongodb.log
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

DURATIONS=(1250 2387 43146 1680 9021 1380 2670 5120 1940 8030 1560 3290 6840 2210 9470)
TABLE_IDS=(
  "ws$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
  "ws$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
  "ws$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
)

for i in "${!DURATIONS[@]}"; do
  now="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
  epoch="$(date +%s)"
  uuid="$(cat /proc/sys/kernel/random/uuid)"
  table_id="${TABLE_IDS[$((i % ${#TABLE_IDS[@]}))]}"
  duration="${DURATIONS[$i]}"

  cat >> "$LOG_FILE" <<EOF
{"t":{"\$date":"$now"},"s":"I","c":"COMMAND","id":51803,"ctx":"conn$((100+i+1))","msg":"Slow query","attr":{"command":{"\$clusterTime":{"clusterTime":{"\$timestamp":{"i":$((i+1)),"t":$epoch}},"signature":{"hash":{"\$binary":{"base64":"REDACTED","subType":"0"}},"keyId":1}},"\$db":"example_db","find":"$table_id","filter":{"status":1,"sys_lock":{"\$ne":true}},"limit":2000,"lsid":{"id":{"\$uuid":"$uuid"}},"sort":{"utime":-1}},"cursorExhausted":true,"docsExamined":1010000,"durationMillis":$duration,"keysExamined":1010000,"nreturned":0,"ns":"example_db.$table_id","numYields":4095,"planCacheKey":"demo$i","planSummary":"IXSCAN { utime: 1 }","protocol":"op_msg","queryHash":"demo_hash_$i","reslen":249,"type":"command"}}
EOF
  sleep 1
done

echo "已写入 ${#DURATIONS[@]} 条测试慢查询日志：$LOG_FILE"
BASH
```

#### Python 版

Python 版本同样随机生成 3 个表名，共写入 15 条日志；每个表写入 5 条，每次写入间隔 1 秒，确保同一 `ns` 有多个时间点。

```bash
sudo python3 - <<'PY'
import json
import os
import secrets
import time
import uuid
from datetime import datetime, timezone

path = "/data/logs/mongodb/mongodb.log"
os.makedirs(os.path.dirname(path), exist_ok=True)

durations = [1250, 2387, 43146, 1680, 9021, 1380, 2670, 5120, 1940, 8030, 1560, 3290, 6840, 2210, 9470]
tables = ["ws" + secrets.token_hex(12) for _ in range(3)]

with open(path, "a", encoding="utf-8") as stream:
    for index, duration in enumerate(durations, 1):
        table = tables[(index - 1) % len(tables)]
        now = datetime.now(timezone.utc)
        epoch = int(now.timestamp())
        log = {
            "t": {"$date": now.isoformat(timespec="milliseconds").replace("+00:00", "Z")},
            "s": "I",
            "c": "COMMAND",
            "id": 51803,
            "ctx": f"conn{100 + index}",
            "msg": "Slow query",
            "attr": {
                "command": {
                    "$clusterTime": {
                        "clusterTime": {"$timestamp": {"i": index, "t": epoch}},
                        "signature": {
                            "hash": {"$binary": {"base64": "REDACTED", "subType": "0"}},
                            "keyId": 1,
                        },
                    },
                    "$db": "example_db",
                    "find": table,
                    "filter": {"status": 1, "sys_lock": {"$ne": True}},
                    "limit": 2000,
                    "lsid": {"id": {"$uuid": str(uuid.uuid4())}},
                    "sort": {"utime": -1},
                },
                "cursorExhausted": True,
                "docsExamined": 1010000,
                "durationMillis": duration,
                "keysExamined": 1010000,
                "nreturned": 0,
                "ns": f"example_db.{table}",
                "numYields": 4095,
                "planCacheKey": f"demo{index}",
                "planSummary": "IXSCAN { utime: 1 }",
                "protocol": "op_msg",
                "queryHash": f"demo_hash_{index}",
                "reslen": 249,
                "type": "command",
            },
        }
        stream.write(json.dumps(log, separators=(",", ":")) + "\n")
        stream.flush()
        time.sleep(1)

print(f"已写入 {len(durations)} 条测试慢查询日志：{path}")
PY
```

验证结果：

```bash
tail -n 5 /data/logs/mongodb/mongodb.log | jq -r '[.t["$date"], .attr.ns, .attr.durationMillis] | @tsv'
```

如果不填写 `MONGODB_SERVER_IP` 或 `MONGODB_INSTANCE_ID`，Compose 会只读挂载宿主机 `/etc/machine-id`，自动生成类似 `mongodb-a1b2c3d4e5f6` 的名称。虚拟机或服务器克隆后，请确认 machine-id 已重新生成。

Compose 仅列出通常需要修改的部署变量；全部支持的变量和默认规则以本 README 为准。通常修改 `config/alloy.env` 后使用 `--env-file` 启动即可；宿主机环境变量可以临时覆盖其中任意变量。认证只使用 `MONITOR_AUTH_USERNAME` 和 `MONITOR_AUTH_PASSWORD`，与 `monitor-victorialogs-grafana` 保持一致。

慢查询的 `durationMillis`、`ns`、`planSummary`、`docsExamined`、`reslen` 和 `attr` 保留在日志 JSON 中，不作为 Loki labels，避免高基数字段造成流数量和索引开销增长。

阿里云推送为可选模块。阿里云目标镜像地址按配置原样使用，Tag 可写可不写，不会由 Workflow 自动追加。配置完整时，流程为：

```text
docker build
docker tag 本地主镜像 阿里云镜像
docker push 阿里云镜像
```

例如：

```text
本地：a.com/a/hap-alloy-vlogs-mongodb-amd64:1.0.0
阿里云：registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-alloy-vlogs-mongodb-amd64:1.0.0
```

没有配置阿里云地址或账号密码时，`build-release` 仍然使用主镜像构建和发布；手动选择 `build-push-release` 时会直接跳过构建、打包和发布，并在 Actions Summary 中列出缺失配置。`pull-release` 只在阿里云地址、账号密码和镜像地址完整时执行。配置完整后，Push 或 Pull 产生的 Release 清单会记录实际使用的阿里云镜像地址。

## Workflow 运行记录清理

每次 Workflow 完整成功后，末尾的 `cleanup-successful-runs` Job 会通过 GitHub API 清理该 Workflow 其他已完成的运行记录（包括成功、失败和取消），只保留当前这次最新成功运行。当前运行、排队中和正在运行的记录不会删除。

该清理只处理 Actions 运行记录，不会删除 GitHub Release 或 Release 附件。如果需要清理历史 Release，需要单独执行 Release 清理策略。

清理 Job 需要 `actions: write` 权限，并且仅在当前构建、打包和 Release 流程成功（或对应模块被正常跳过）时执行；构建失败或通知失败时不会触发清理。清理 Job 使用 `continue-on-error: true`，清理 API 失败不会回滚已经成功的构建或 Release，需根据 Job 日志重新处理未删除的运行记录。

## Workflow 运行模式

### 构建速度与镜像体积

amd64 和 arm64 使用各自的原生 Runner 分别构建，不使用 QEMU 模拟。当前构建脚本已按架构启用 GitHub Actions Buildx 缓存，第一次构建仍需要拉取基础镜像，后续同架构构建会复用缓存。

官方 `grafana/alloy` 目前没有 Alpine 变体。当前使用完整的官方 `grafana/alloy:v1.21.2` 基础镜像，保留完整发行版运行环境，便于现有 entrypoint 读取宿主机 `machine-id`、生成唯一任务名和处理默认参数。Dockerfile 使用软链接引用 Alloy 程序，避免再次复制一份大二进制。

当前镜像包使用 `docker save | gzip` 打包，服务器上 `docker images` 显示的是解压后的层大小，通常会明显大于压缩后的镜像传输体积。

使用 `Actions → Image Make → Run workflow` 时，`operation` 请选择以下模式之一：

- `build-release`：构建并发布。
- `pull-release`：使用已有阿里云镜像发布。
- `build-push-release`：构建、推送阿里云并发布。

这里的 `push` 仅表示 GitHub 的自动提交触发事件，不是手动运行模式。提交到 `master` 时，默认 `PUSH_OPERATION=auto`，Workflow 会按 `.image-build.env` 和 Repository Variables 自动选择：阿里云 Push 配置完整时执行 `build-push-release`，未配置或配置不完整时自动执行 `build-release`；如果指定了具体 `PUSH_OPERATION`，则严格按指定模式执行。

Git push 的模式可以通过 `PUSH_OPERATION` 配置，默认值为 `auto`。可选值为 `auto`、`build-release`、`pull-release`、`build-push-release`；配置为具体模式后，push 会严格按指定模式执行。该配置可写在 `.image-build.env`，也可用同名 Repository Variable 覆盖；手动 `Run workflow` 使用页面中的 `operation`，不受 `PUSH_OPERATION` 影响。

手动输入项的含义：

- `tag`：可选的 GitHub Release tag；手动运行时留空直接使用 `latest`，不会自动追加到镜像地址
- `architectures`：选择 `amd64`、`arm64` 或 `all`；默认 `all`
- `create_release`：Release 模块开关；关闭后不会打包上传 Release
- `notify_hap`：HAP Webhook 通知模块开关；关闭或 URL 为空时只跳过通知
- `target_image_amd64`、`target_image_arm64`：覆盖两个架构的主镜像地址；留空时使用配置中的主镜像地址，地址未带 Tag 时由 Docker 按 `latest` 解析
- `aliyun_image_amd64`、`aliyun_image_arm64`：可选的阿里云目标镜像地址；留空时复用对应主镜像地址，填写后按原样使用

`pull-release` 需要提前存在可拉取的阿里云镜像和完整的阿里云凭据。如果只想构建而不创建 Release，可将 `create_release` 关闭；`build-release` 本身会创建 Release。

手动运行时可以不填写 `tag`，留空直接使用 `latest`；自动提交时使用 Repository Variable 或 `.image-build.env` 的 `IMAGE_TAG`，都未配置时使用 `latest`。
Tag 只用于 GitHub Release 和附件文件名，允许字母、数字、`.`、`_`、`-`；不支持 `/`、空格等字符。

## 架构基础镜像

amd64 和 arm64 的基础镜像地址可以完全不同，不能假设只替换镜像名中的架构字符串即可。请在 `.image-build.env` 中分别配置：

```bash
BASE_IMAGE_AMD64=registry.example.com/base/linux-amd64:3.23
BASE_IMAGE_ARM64=another.example.com/base/arm64-runtime:3.23
```

Workflow 会把对应值通过 `--build-arg BASE_IMAGE=...` 传给 Dockerfile。当前固定使用官方多架构 `grafana/alloy:v1.21.2`，直接手动构建会按当前 Docker 平台自动选择 amd64 或 arm64：

```bash
docker build -t alloy-mongodb:amd64 .
```

需要指定不同基础镜像时，再显式传入：

```bash
docker build --build-arg BASE_IMAGE=another.example.com/base/arm64-runtime:3.23 -t alloy-mongodb:arm64 .
```

如果基础镜像仓库是私有仓库，可配置 Secrets `BASE_REGISTRY_USERNAME` 和 `BASE_REGISTRY_PASSWORD`。Workflow 会从当前架构的 `BASE_IMAGE_*` 地址自动解析 Registry 并在构建前登录，不需要额外配置基础镜像 Registry 地址。

阿里云配置：

- Variable：`ALIYUN_REGISTRY`，默认 `registry.cn-hangzhou.aliyuncs.com`
- Secrets：`ALIYUN_REGISTRY_USERNAME`、`ALIYUN_REGISTRY_PASSWORD`
- `aliyun_image_amd64`、`aliyun_image_arm64`：阿里云目标镜像地址，按填写内容原样使用

HAP 配置：

- Secret：`HAP_WEBHOOK_URL`
- 可选：`HAP_WEBHOOK_APP_KEY`、`HAP_WEBHOOK_SIGN`

HAP URL 为空时跳过通知，并在 Actions Summary 中说明原因。

HAP Webhook 的请求体与 nginx-make 保持一致，使用固定的通用字段，不携带项目专用字段。`project_name` 使用 `RELEASE_NAME`（未配置时使用仓库名），版本和附件信息从当前 Release 自动生成。`attachment_urls` 按 HAP 约定以 JSON 字符串传递多个下载地址。请求使用 `Content-Type: application/json`，并按配置附带 `AppKey`、`Sign` 请求头。

请求体示例：

```json
{
  "project_name": "alloy-mongodb",
  "repository": "1447443432/alloy-mongodb",
  "version": "1.0.0",
  "tag": "1.0.0",
  "release_url": "https://github.com/1447443432/alloy-mongodb/releases/tag/1.0.0",
  "amd64_name": "hap-alloy-vlogs-mongodb-amd64_1.0.0.tar.gz",
  "amd64_url": "https://github.com/1447443432/alloy-mongodb/releases/download/1.0.0/hap-alloy-vlogs-mongodb-amd64_1.0.0.tar.gz",
  "amd64_sha256": "...",
  "arm64_name": "hap-alloy-vlogs-mongodb-arm64_1.0.0.tar.gz",
  "arm64_url": "https://github.com/1447443432/alloy-mongodb/releases/download/1.0.0/hap-alloy-vlogs-mongodb-arm64_1.0.0.tar.gz",
  "arm64_sha256": "...",
  "attachment_urls": "[\"https://.../amd64.tar.gz\",\"https://.../arm64.tar.gz\"]",
  "commit_sha": "e7daeca",
  "run_id": "123456789",
  "run_url": "https://github.com/1447443432/alloy-mongodb/actions/runs/123456789",
  "build_status": "success"
}
```

amd64 和 arm64 附件字段始终存在；如果某架构没有产物，对应值为空字符串。Webhook 只在 Release 成功后发送，URL 为空或模块关闭时跳过并在 Summary 中说明原因。

## 手动 Docker 构建

Dockerfile 兼容直接手动构建，默认使用官方多架构 `grafana/alloy:v1.21.2`：

```bash
docker build -t alloy-mongodb:amd64 .
```

在 arm64 主机上使用同一条命令即可；跨平台构建时指定平台：

```bash
docker buildx build --platform linux/arm64 --load -t alloy-mongodb:arm64 .
```

GitHub Actions 会根据矩阵自动传入 `TARGETARCH=amd64` 或 `TARGETARCH=arm64`。

## 项目配置文件

`.image-build.env` 是项目级默认配置。它使用简单的 `KEY=VALUE` 格式，支持 `#` 注释，适合直接复制到其他项目后修改。

`.github/workflows/image-make.yml` 和 `.github/image-make/` 不保存本项目的镜像仓库；项目个性化值集中在 `.image-build.env`，因此这套 Workflow 可以直接复制到其他项目使用。

配置覆盖顺序从高到低为：

1. 手动 `Run workflow` 输入
2. GitHub Repository Variables
3. `.image-build.env`
4. Workflow 默认值

### 默认值与必填规则

需要注意：手动 `Run workflow` 页面显示的默认值，只对本次手动运行生效；`.image-build.env` 是项目级默认配置；Workflow 引擎本身不保存具体项目的镜像仓库默认值。

手动运行输入的默认值：

| 输入 | 默认值 | 是否必填 | 说明 |
|---|---|---|---|
| `operation` | `build-release` | 是 | `build-release` 构建并 Release；`pull-release` 拉取并 Release；`build-push-release` 构建、推送并 Release |
| `tag` | 空 | 否 | GitHub Release tag；手动运行时留空直接使用 `latest` |
| `architectures` | `all` | 是 | 构建 `amd64`、`arm64` 或两个架构 |
| `create_release` | `true` | 是 | 是否创建 GitHub Release |
| `notify_hap` | `false` | 是 | 是否启用 HAP 通知；还必须配置 Webhook URL |
| `target_image_amd64` | 空 | 否 | 空时使用 `.image-build.env` 或 Repository Variable；地址按原样使用，未带 Tag 时 Docker 使用 `latest` |
| `target_image_arm64` | 空 | 否 | 同上 |
| `aliyun_image_amd64` | 空 | 否 | 可选；留空时复用主 amd64 镜像地址，填写后按原样使用 |
| `aliyun_image_arm64` | 空 | 否 | 同上 |

当前项目 `.image-build.env` 中的默认值如下：

```text
IMAGE_TAG=1.0.0
ARCHITECTURES=all
PUSH_OPERATION=auto
RELEASE_NAME=hap-alloy-vlogs-mongodb
BASE_IMAGE_AMD64=grafana/alloy:v1.21.2
BASE_IMAGE_ARM64=grafana/alloy:v1.21.2
TARGET_IMAGE_AMD64=registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-alloy-vlogs-mongodb-amd64:1.0.0
TARGET_IMAGE_ARM64=registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-alloy-vlogs-mongodb-arm64:1.0.0
ALIYUN_REGISTRY=registry.cn-hangzhou.aliyuncs.com
ENABLE_ALIYUN_PUSH=true
ENABLE_RELEASE=true
ENABLE_HAP_WEBHOOK=true
```

没有默认值的配置：

- `HAP_WEBHOOK_URL`：没有默认值；为空时跳过 HAP 通知，并显示原因。
- `ALIYUN_REGISTRY_USERNAME`、`ALIYUN_REGISTRY_PASSWORD`：没有默认值；手动选择 `build-push-release` 或 `pull-release` 时必填。Git push 使用 `PUSH_OPERATION=auto` 时，缺失配置会自动选择 `build-release`，不会阻断普通构建发布；若指定推送或拉取模式，则按该模式严格校验。
- `BASE_REGISTRY_USERNAME`、`BASE_REGISTRY_PASSWORD`：没有默认值；只有基础镜像仓库为私有仓库时才需要。
- `TARGET_IMAGE_AMD64`、`TARGET_IMAGE_ARM64`：通用 Workflow 没有默认镜像地址；当前项目的默认值来自 `.image-build.env`，地址按原样使用。复制到其他项目时必须替换成新项目的镜像地址。

Dockerfile 的 `BASE_IMAGE` 默认值固定为 `grafana/alloy:v1.21.2`；CI 配置仍要求 `BASE_IMAGE_AMD64` 和 `BASE_IMAGE_ARM64` 都能解析到有效值，以避免架构基础镜像配置不明确。

## GitHub Actions 配置方法

所有 GitHub 端的配置入口都在仓库的：

```text
Settings → Secrets and variables → Actions
```

请分别进入 `Variables` 和 `Secrets` 标签页配置。配置完成后，打开：

```text
Actions → Image Make → Run workflow
```

手动执行一次验证。不要把密码、Webhook URL、AppKey 或 Sign 写入 README、`.image-build.env` 或 Workflow 文件。
Workflow 只在配置检查和 Release 相关步骤使用 HAP Secret；构建和 Package Job 不接收 HAP AppKey、Sign 等通知凭据。

### Repository Variables（可选覆盖项）

Variables 用于在 GitHub 侧覆盖非敏感配置，不是全部必填。在 `Settings → Secrets and variables → Actions → Variables → New repository variable` 中按需添加。当前项目已经有 `.image-build.env`，因此不需要把下面的值重复配置一遍；只有需要 GitHub 侧覆盖，或项目不提交 `.image-build.env` 时才配置 Variables。

| Name | 示例值/项目默认值 | 作用 |
|---|---|---|
| `IMAGE_TAG` | `latest` | Release tag；不配置时使用 `latest` |
| `PUSH_OPERATION` | `auto` | Git push 模式：`auto`、`build-release`、`pull-release` 或 `build-push-release` |
| `RELEASE_NAME` | `alloy-mongodb` | Release 名和 HAP `project_name`；不配置时使用仓库名 |
| `TARGET_IMAGE_AMD64` | `registry.example.com/project/image-amd64` | amd64 主镜像地址，按原样使用 |
| `TARGET_IMAGE_ARM64` | `registry.example.com/project/image-arm64` | arm64 主镜像地址，按原样使用 |
| `BASE_IMAGE_AMD64` | `grafana/alloy:v1.21.2` | amd64 Alloy 基础镜像 |
| `BASE_IMAGE_ARM64` | `grafana/alloy:v1.21.2` | arm64 Alloy 基础镜像 |
| `ALIYUN_REGISTRY` | `registry.cn-hangzhou.aliyuncs.com` | 阿里云 Registry 地址 |
| `ALIYUN_IMAGE_AMD64` | `registry.example.com/project/image-amd64` | 阿里云 amd64 镜像地址，按原样使用 |
| `ALIYUN_IMAGE_ARM64` | `registry.example.com/project/image-arm64` | 阿里云 arm64 镜像地址，按原样使用 |
| `ENABLE_ALIYUN_PUSH` | `true` | 阿里云 Push 模块开关 |
| `ENABLE_RELEASE` | `true` | GitHub Release 模块开关 |
| `ENABLE_HAP_WEBHOOK` | `true` | HAP Webhook 模块开关 |

本项目也可以把上述默认值写在 `.image-build.env`；两者同时存在时，Repository Variables 优先于 `.image-build.env`。`Run workflow` 页面中直接填写的输入优先级最高。

### Repository Secrets

Secrets 用于敏感配置。在 `Settings → Secrets and variables → Actions → Secrets → New repository secret` 中添加：

| Name | 是否必需 | 作用 |
|---|---|---|
| `ALIYUN_REGISTRY_USERNAME` | 使用阿里云 Push/Pull 时必需 | 阿里云 Registry 用户名 |
| `ALIYUN_REGISTRY_PASSWORD` | 使用阿里云 Push/Pull 时必需 | 阿里云 Registry 密码或 Access Token |
| `BASE_REGISTRY_USERNAME` | 基础镜像仓库私有时必需 | 基础镜像 Registry 用户名 |
| `BASE_REGISTRY_PASSWORD` | 基础镜像仓库私有时必需 | 基础镜像 Registry 密码或 Token |
| `HAP_WEBHOOK_URL` | 启用 HAP 通知时必需 | HAP Webhook 接收地址 |
| `HAP_WEBHOOK_APP_KEY` | 可选 | 作为 `AppKey` 请求头发送 |
| `HAP_WEBHOOK_SIGN` | 可选 | 作为 `Sign` 请求头发送 |

也兼容 `REGISTRY_USERNAME` 和 `REGISTRY_PASSWORD` 作为阿里云账号密码的通用别名，但建议统一使用 `ALIYUN_REGISTRY_USERNAME` 和 `ALIYUN_REGISTRY_PASSWORD`。

### HAP Webhook 配置示例

1. 在 HAP 中创建用于接收 Release 信息的 Webhook，并复制 Webhook URL。
2. 在 GitHub `Settings → Secrets and variables → Actions → Secrets` 中新增：

   ```text
   HAP_WEBHOOK_URL=https://your-hap.example.com/webhook/xxxxxxxx
   HAP_WEBHOOK_APP_KEY=your-app-key       # 如果 HAP 要求
   HAP_WEBHOOK_SIGN=your-sign             # 如果 HAP 要求
   ```

3. 在 Repository Variables 中设置：

   ```text
   ENABLE_HAP_WEBHOOK=true
   ```

4. 运行 `build-release` 或 `build-push-release`，Release 成功后才会执行 HAP 通知。

请求头和请求体如下：

```text
Content-Type: application/json
AppKey: <HAP_WEBHOOK_APP_KEY>   # 配置后才发送
Sign: <HAP_WEBHOOK_SIGN>        # 配置后才发送
```

Webhook URL 为空、`ENABLE_HAP_WEBHOOK` 不是 `true`，或 Release 没有成功时，不会调用 HAP；Actions Summary 会显示具体跳过原因。HAP 通知失败会使 Release Job 失败，便于及时发现接收端或签名配置错误。

### 阿里云 Push 配置示例

阿里云 ACR 镜像地址必须同时满足以下格式：

```text
<registry>/<namespace>/<repository>:<tag>
```

本项目默认使用以下命名，amd64 和 arm64 必须是两个不同的仓库名或至少是两个不同的镜像名：

```text
registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-alloy-vlogs-mongodb-amd64:1.0.0
registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-alloy-vlogs-mongodb-arm64:1.0.0
```

其中：

- `registry.cn-hangzhou.aliyuncs.com` 是 ACR Registry 地址，必须与 `ALIYUN_REGISTRY` 完全一致；
- `hap-mdy` 是 ACR 命名空间，必须是当前账号有 Push 权限的命名空间；
- `hap-alloy-vlogs-mongodb-amd64` 和 `hap-alloy-vlogs-mongodb-arm64` 是两个架构对应的镜像名称；
- `1.0.0` 是镜像 Tag，同时也是默认 Release Tag。

如果改用其他地域或命名空间，必须同时修改 `ALIYUN_REGISTRY`、`ALIYUN_IMAGE_AMD64` 和 `ALIYUN_IMAGE_ARM64`，不能只修改 Registry 登录地址。Workflow 会在配置检查阶段校验两个 Aliyun 镜像地址的 Registry 是否一致，并校验路径中是否包含 `namespace/repository`；校验失败时不会进入构建和 Push。

```text
Repository Variables:
  ALIYUN_REGISTRY=registry.cn-hangzhou.aliyuncs.com
  ALIYUN_IMAGE_AMD64=registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-alloy-vlogs-mongodb-amd64:1.0.0
  ALIYUN_IMAGE_ARM64=registry.cn-hangzhou.aliyuncs.com/hap-mdy/hap-alloy-vlogs-mongodb-arm64:1.0.0
  ENABLE_ALIYUN_PUSH=true

Repository Secrets:
  ALIYUN_REGISTRY_USERNAME=<阿里云账号>
  ALIYUN_REGISTRY_PASSWORD=<阿里云密码或 Token>
```

阿里云 Registry、账号密码齐全且 `ENABLE_ALIYUN_PUSH=true` 时，`build-push-release` 执行 `docker tag` 和 `docker push`；阿里云目标地址留空时复用对应主镜像地址，填写后按原样使用。手动选择 `build-push-release`，或将 Git push 的 `PUSH_OPERATION` 指定为该模式时，缺少配置会停止后续构建、打包和 Release。`PUSH_OPERATION=auto` 时，缺少配置会自动降级为 `build-release`，并在 Summary 中说明原因。`pull-release` 不依赖 `ENABLE_ALIYUN_PUSH`，只检查完整的阿里云拉取配置。

### 配置后的验证建议

建议按以下顺序验证：

1. 先用 `build-release` 验证两个架构构建、打包和 Release。
2. 配置阿里云后用 `build-push-release` 验证 Tag、Push 和 Release 附件。
3. 配置 HAP 后再次运行 `build-release` 或 `build-push-release`，检查 Release Job 的 `HAP sync` 和通知步骤。
4. 检查 HAP 接收到的 `repository`、`version`、两个架构下载地址和 SHA256 是否正确。
5. 修改 Workflow 或 `.github/image-make/` 后，检查 Image Make 的 `Validate GitHub Actions workflows` Job 是否通过；它使用固定版本的 `actionlint` 检查 GitHub Actions 语法和表达式。
6. 运行 `python .github/image-make/test_release.py`，检查 Release manifest 的镜像来源和 digest 镜像识别。

如果某个可选模块没有配置，不要根据灰色步骤判断失败；查看 `Check module configuration` 和 `Release` 的 Actions Summary，其中会写明模块是关闭、缺少哪些配置，还是执行成功。

配置 Job 会在执行前检查所有模块，并把启用、跳过及缺失字段写入 Actions Summary。

### Workflow 静态检查

`image-make.yml` 的第一个 Job 会先运行 actionlint 和 Release manifest 测试。检查通过后才会进入 config、Build、Package 和 Release；检查失败时后续 Job 不会执行。它只检查 GitHub Actions 定义和最小脚本逻辑，不会执行 Docker 构建；需要本地检查时也可以安装同版本 `actionlint` 后运行：

```bash
actionlint
```

Workflow 使用固定的 Action commit 和 actionlint 镜像 digest，升级依赖时应重新验证对应版本的行为。

如果要求检查失败时禁止合并，请在 GitHub `Settings → Branches` 中将 `Image Make / Validate GitHub Actions workflows` 设置为受保护分支的必需状态检查。它只负责阻止合并；Push 到 `master` 时，Image Make 会在同一条 Workflow 内先检查再构建。

## CI 专用脚本

项目运行脚本仍放在 `scripts/`。镜像构建 Workflow 使用的辅助脚本单独放在 `.github/image-make/`：

```text
.github/image-make/config.py   # 配置覆盖、模块开关和 Summary
.github/image-make/build.sh    # 单架构构建、Aliyun Push 和本地打包
.github/image-make/package.sh  # 构建产物校验或 Release-only 打包
.github/image-make/release.py  # Release manifest 和 Summary
```

`RELEASE_NAME` 写入 Release manifest。压缩包名称会根据镜像最后一段和 tag 自动生成，例如 `hap-alloy-vlogs-mongodb-amd64_1.0.0.tar.gz`。构建上下文配置项使用 `BUILD_CONTEXT`，不要命名为 Docker 保留的 `DOCKER_CONTEXT`。复制这套 Workflow 到其他项目时，只需要修改 `.image-build.env`、Dockerfile 和必要的镜像配置，不需要把 CI 脚本混入项目业务 `scripts/`。

当前镜像使用 Grafana Alloy 官方完整多架构基础镜像；项目已移除无效的 `ALPINE_MIRROR` 和 `ALPINE_VERSION` 构建参数。
