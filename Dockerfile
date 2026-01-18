FROM astral/uv:python3.12-trixie-slim

RUN apt-get update \
	&& apt-get install -y --no-install-recommends locales apache2-utils \
	&& sed -i 's/^# \(ja_JP.UTF-8 UTF-8\)$/\1/' /etc/locale.gen \
	&& locale-gen \
	&& rm -rf /var/lib/apt/lists/*

ENV LANG=ja_JP.UTF-8 \
	LC_ALL=ja_JP.UTF-8

RUN pip install Trac Babel --break-system-packages

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
