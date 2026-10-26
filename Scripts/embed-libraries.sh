#!/bin/bash
set -euo pipefail
source_dir="$SRCROOT/Vendor/lib"
target_dir="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$target_dir"
for source in "$source_dir"/*.dylib; do
  target="$target_dir/$(basename "$source")"
  cp "$source" "$target"
  chmod u+w "$target"
  if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$target"
  fi
done
mkdir -p "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Licenses"
cp "$SRCROOT"/Vendor/licenses/* "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Licenses/"
cp "$SRCROOT/LICENSE" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Licenses/MTPExplorer-MIT.txt"
cp "$SRCROOT/NOTICE" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Licenses/NOTICE.txt"
cp "$SRCROOT/Vendor/SOURCES.md" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Licenses/SOURCES.md"
