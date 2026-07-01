#!/bin/sh
set -eu

cd "$(dirname "$0")/../ui"
flutter pub get
flutter build web --release

cd ..
rm -rf internal/server/static
mkdir -p internal/server/static
cp -R ui/build/web/. internal/server/static/
echo "UI embedded into internal/server/static"
