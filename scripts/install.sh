#!/bin/sh
set -eu

if [ ! -x "./neotranscoder" ]; then
  echo "expected executable ./neotranscoder next to install.sh" >&2
  echo "try: chmod +x neotranscoder install.sh" >&2
  exit 1
fi

exec ./neotranscoder init "$@"
