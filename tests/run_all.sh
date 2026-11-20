#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

bash tests/test_manifest.sh
bash tests/test_asusctl_js.sh
bash tests/test_controller_static.sh
bash tests/test_controller_behavior.sh
bash tests/test_widget_static.sh
bash tests/test_widget_behavior.sh
bash tests/test_install_layout.sh
