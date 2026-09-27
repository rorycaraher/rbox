# Egress-allowlist forward proxy the task container is routed through.
# Debian ships two squid builds; only `squid-openssl` has ssl_bump support
# (SNI peek/splice) — the plain `squid` package is the GnuTLS flavour and
# doesn't understand the `ssl::server_name` ACL type at all.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      squid-openssl \
      openssl \
    && rm -rf /var/lib/apt/lists/*

# A self-signed cert to satisfy squid's ssl-bump port option. Never actually
# presented to a client: every allowed HTTPS connection is spliced through
# untouched after Squid reads the SNI, not decrypted and re-signed.
RUN mkdir -p /etc/squid/certs && \
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -keyout /etc/squid/certs/squid-ca.pem \
      -out /etc/squid/certs/squid-ca.pem \
      -subj "/CN=rbox-task-proxy-unused"

COPY squid.conf /etc/squid/squid.conf
COPY allowed_domains.txt /etc/squid/allowed_domains.txt

EXPOSE 3128
CMD ["squid", "-f", "/etc/squid/squid.conf", "-N", "-d", "1"]
