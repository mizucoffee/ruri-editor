#!/usr/bin/env bash
set -euo pipefail

helper_dir="Tools/java-symbol-resolver"
tools_dir="Ruri/Resources/Tools"
gradle_cmd=("$helper_dir/gradlew")

if [[ ! -x "${gradle_cmd[0]}" ]]; then
  gradle_cmd=(gradle)
fi

mkdir -p "$tools_dir"
"${gradle_cmd[@]}" -p "$helper_dir" shadowJar
install -m 0644 "$helper_dir/build/libs/java-symbol-resolver.jar" "$tools_dir/java-symbol-resolver.jar"

echo "Installed java symbol resolver to ${tools_dir}/java-symbol-resolver.jar"
