# 部署说明

本文档列出部署到 1Panel 服务器所需要的全部文件、各自的来源与作用，以及首次部署、更新、回滚、备份的操作步骤。

## 1. 文件清单

| 文件 | 是否必需 | 来源 | 作用 |
| --- | --- | --- | --- |
| `compose.yaml` | MySQL 多租户模式必需 | 仓库自带 | 编排文件，使用 GHCR 镜像，端口 3000 与 10888 |
| `compose.standalone.yaml` | SQLite 独立模式必需 | 仓库自带 | 编排文件，仅端口 3000，与 `compose.yaml` **二选一** |
| `.env.example` | 模板 | 仓库自带 | 环境变量模板 |
| `.env` | MySQL 多租户模式必需 | 由 `.env.example` 复制 | 存放模型加密密钥 |
| `dataSource.example.json` | 模板 | 仓库自带 | MySQL 连接配置模板 |
| `data/multiTenant/dataSource.json` | MySQL 多租户模式必需 | 由模板复制并填写真实值 | 程序实际读取的数据库配置 |
| `data/` | 自动生成 | 容器启动时创建 | 数据目录，挂载到容器 `/app/data` |

只有 `data/` 一个挂载点。数据库配置通过挂载目录进入容器，不需要额外挂载单文件。

## 2. 目录结构

部署目录在 1Panel 编排所用的工作目录下，结构如下：

```text
deploy/
├── compose.yaml                # MySQL 多租户编排
├── compose.standalone.yaml     # SQLite 独立编排（二选一）
├── .env                        # 加密密钥，不提交版本库
├── .env.example
├── dataSource.example.json     # 模板，不直接使用
└── data/                       # 挂载到容器 /app/data
    ├── settings.json           # 程序自动生成
    ├── multiTenant/
    │   └── dataSource.json     # 手动放入，MySQL 连接配置
    ├── workspaces/             # 项目工作区
    └── tools/ nodes/ ext/      # 内置插件，首次启动自动初始化
```

`data/` 下的其余内容由程序管理，不要手工修改或删除。

## 3. 首次部署：MySQL 多租户

```sh
# 1. 进入部署目录，准备数据目录
mkdir -p data/multiTenant

# 2. 放入 MySQL 配置，并填写真实连接信息
cp dataSource.example.json data/multiTenant/dataSource.json

# 3. （可选）覆盖编排内置的默认密钥；不执行则直接使用默认值
cp .env.example .env
printf 'TOONFLOW_MULTI_TENANT_SECRET=%s\n' "$(openssl rand -base64 32)" > .env

# 4. 修正目录属主，容器以非 root 的 bun 用户运行
chown -R 1000:1000 data

# 5. 启动
docker compose -f compose.yaml up -d
```

启动后在 1Panel 容器日志中确认出现 `[服务启动成功]`，再进入管理页开启多租户，10888 创作入口才会监听。

## 4. 首次部署：SQLite 独立模式

```sh
mkdir -p data
chown -R 1000:1000 data
docker compose -f compose.standalone.yaml up -d
```

不需要 `.env`，也不需要 `dataSource.json`。该模式没有账号体系，反向代理必须开启访问密码。

## 5. 环境变量

| 变量 | 作用 | 必需 |
| --- | --- | --- |
| `TOONFLOW_DATA_DIR` | 数据目录，固定 `/app/data` | 是 |
| `TOONFLOW_SERVER_PORT` | 监听端口，默认 3000 | 否 |
| `TOONFLOW_MULTI_TENANT_SECRET` | 模型配置加密密钥，32 字节 Base64 | 否，编排内已内置默认值，可用 `.env` 覆盖 |

数据库连接信息**不支持环境变量**，只能写在 `data/multiTenant/dataSource.json`，程序仅从该文件读取。该文件格式：

```json
{
  "provider": "mysql",
  "mysql": {
    "host": "127.0.0.1",
    "port": 3306,
    "database": "toonflow",
    "user": "toonflow",
    "password": "真实密码"
  }
}
```

需要 TLS 时追加 `ssl` 字段，内容为 `{"ca": "证书内容"}`。

## 6. 镜像仓库认证与反向代理

镜像来自 GitHub 容器镜像服务（GHCR）。命名空间为私有时，1Panel 拉取前需要先配置认证：

1. 打开 GitHub → Settings → Developer settings → Personal access tokens，创建 Token 并勾选 `read:packages`。
2. 1Panel → 容器 → 镜像 → 仓库 → 添加：地址 `ghcr.io`，用户名填 GitHub 用户名，密码填上一步的 Token。
3. 若在 GitHub Packages 页面把镜像可见性改为 Public，则跳过以上步骤，直接拉取。

反向代理配置：

- 容器只绑定 `127.0.0.1`，公网访问统一经 1Panel 网站反向代理。
- 管理入口：新建反向代理站点，上游填 `http://127.0.0.1:3000`，申请证书并开启访问密码。
- 多租户创作入口：再建一个站点，上游填 `http://127.0.0.1:10888`。

## 7. 更新与回滚

```sh
# 更新到 latest
docker compose -f compose.yaml pull
docker compose -f compose.yaml up -d

# 回滚：把编排里的标签改为旧版本或 sha
# image: ghcr.io/ifty-r/toonflow-app:sha-<commit>
```

1Panel 编排页面同样提供拉取镜像与重建操作。不要启用自动更新，升级前先备份。

## 8. 备份

备份对象是 `data/` 整个目录，先停服务再复制：

```sh
docker compose -f compose.yaml stop
cp -a data "backup/toonflow-$(date +%Y%m%d)"
docker compose -f compose.yaml start
```

也可在 1Panel 计划任务中对 `data/` 目录做定时打包。

## 9. 常见问题

- **启动后无法写入、报权限错误**：宿主机 `data/` 属主不是 1000。执行 `chown -R 1000:1000 data`；若镜像内用户 uid 不同，用 `docker compose exec toonflow id bun` 核对后按实际 uid 调整。
- **报“模型加密密钥无效”**：自行覆盖的 `TOONFLOW_MULTI_TENANT_SECRET` 不是 32 字节 Base64；用 `openssl rand -base64 32` 重新生成，或删除该变量改用编排内置默认值。
- **报“多租户数据源配置无效”**：`data/multiTenant/dataSource.json` 字段不完整或 JSON 格式错误，按第 5 节结构核对。
- **10888 端口无响应**：多租户尚未在管理页开启，或编排中注释了该端口映射。
- **镜像拉取失败（denied / unauthorized）**：GHCR 镜像为私有时未配置认证，按第 6 节添加带 `read:packages` 权限的 Token；或把镜像可见性改为 Public。
