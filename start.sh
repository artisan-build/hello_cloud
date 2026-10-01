#!/bin/sh
# The entry point inside the bundle that ./app unpacks.
#
# basic-webserver's host reads its listen address from its own two environment
# variables and defaults to 127.0.0.1:8000, so this translates Cloud's $PORT
# and asks for the IPv6 wildcard before handing over to the server.
set -eu
BASE=$(cd "$(dirname "$0")" && pwd)
ROC_BASIC_WEBSERVER_HOST="[::]"
ROC_BASIC_WEBSERVER_PORT="${PORT:-3000}"
export ROC_BASIC_WEBSERVER_HOST ROC_BASIC_WEBSERVER_PORT
exec "$BASE/server"
