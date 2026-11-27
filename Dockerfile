FROM oven/bun:1.4.3

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY . .

# ACT: 保留工作区与依赖以兼容运行时动态加载；需要缩减镜像时再拆分构建阶段。
RUN bun install --frozen-lockfile

# 应用版本号：由镜像构建参数注入，"关于"页展示与更新检查都读取它。
# 默认值与当前代码基线保持一致；workflow 会按 image-vX.Y.Z 标签覆盖。
ARG APP_VERSION=2.0.11
ENV appVersion=${APP_VERSION}

RUN bun run build:server \
    && mkdir -p data/workspaces/myProject \
    && chown -R bun:bun data

ENV NODE_ENV=production
ENV TOONFLOW_DATA_DIR=/app/data

USER bun
EXPOSE 3000

CMD ["bun", "build/server/index.js"]
