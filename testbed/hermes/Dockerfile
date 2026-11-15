# Hermes backend at a pinned upstream commit. PyPI (0.19.0, 2026-07-20) lacks the RPCs the
# client needs (client.capabilities, session.events.since, groups.*), so build from git.
FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim
ARG HERMES_REF=d97007c32d6340f7ba79ac1dfb5773cc00846448
RUN apt-get update \
    && apt-get install -y --no-install-recommends git openssh-server ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
RUN git init -q /opt/hermes \
    && cd /opt/hermes \
    && git remote add origin https://github.com/NousResearch/hermes-agent \
    && git fetch -q --depth 1 origin "$HERMES_REF" \
    && git checkout -q FETCH_HEAD
WORKDIR /opt/hermes
RUN uv sync --frozen --no-dev || uv sync --frozen
ENV PATH=/opt/hermes/.venv/bin:$PATH
RUN ln -s /opt/hermes/.venv/bin/hermes /usr/local/bin/hermes
# sshd: non-root test user, key-only login. The key is mounted at runtime.
RUN useradd -m -s /bin/bash tester \
    && mkdir -p /run/sshd /home/tester/.ssh \
    && chown -R tester:tester /home/tester/.ssh \
    && chmod 700 /home/tester/.ssh \
    && printf 'PasswordAuthentication no\nPermitRootLogin no\nAllowUsers tester\nAllowTcpForwarding yes\n' > /etc/ssh/sshd_config.d/testbed.conf
COPY seed-config.sh /usr/local/bin/seed-config.sh
RUN chmod +x /usr/local/bin/seed-config.sh
