FROM factoriotools/factorio:1.1.104

RUN apt-get update && apt-get install -y rsync

ENV PREPARED_DIR=/factorio-prepared

# Add new entrypoint, make sure it's executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Add static files
COPY factorio ${PREPARED_DIR}

# Preemptively update/install mods
# Note: This must be run with secrets mounted for factorio user/token
# docker build --secret id=username,env=FACTORIO_USERNAME --secret id=token,env=FACTORIO_TOKEN .
RUN --mount=type=secret,id=username --mount=type=secret,id=token MODS=${PREPARED_DIR}/mods ./docker-update-mods.sh

ENTRYPOINT ["/entrypoint.sh"]
