#!/bin/bash
set -eou pipefail

# move the prepared save to the factorio directory with rsync
rsync -avhu --progress $PREPARED_DIR/ /factorio/

# run the original entrypoint
/docker-entrypoint.sh "$@"
