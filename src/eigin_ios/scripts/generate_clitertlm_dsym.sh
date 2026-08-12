#!/bin/sh
# LiteRT-LM ships CLiteRTLM.framework as a prebuilt dynamic framework with
# embedded DWARF but no companion dSYM. Xcode never builds one since it didn't
# compile the binary, which makes App Store Connect reject uploads for the
# missing UUID.
#
# Shared by the Eigin and EiginDev targets (see project.yml postbuildScripts).
if [ -z "${DWARF_DSYM_FOLDER_PATH:-}" ]; then
  exit 0
fi

# The dSYM is only consumed by App Store archives. Running dsymutil on every
# Debug build corrupts DerivedData and breaks the test runner, so skip it
# outside Release.
if [ "${CONFIGURATION:-}" != "Release" ]; then
  exit 0
fi

FRAMEWORK="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/CLiteRTLM.framework"
BINARY="${FRAMEWORK}/CLiteRTLM"

if [ -f "${BINARY}" ]; then
  mkdir -p "${DWARF_DSYM_FOLDER_PATH}"
  # dsymutil cannot place its temporary output into an existing bundle, so an
  # incremental build fails in lipo unless the old one is cleared.
  DSYM="${DWARF_DSYM_FOLDER_PATH}/CLiteRTLM.framework.dSYM"
  rm -rf "${DSYM}"
  dsymutil "${BINARY}" -o "${DSYM}"
fi
