#!/usr/bin/env bash
# Compatibility launcher for existing d-environment commands and scripts.
source "$(dirname "${BASH_SOURCE[0]}")/devready"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
