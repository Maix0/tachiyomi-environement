#!/usr/bin/env bash
TMP=$(mktemp)


nix log "$1" 2>/dev/null | rg "file:" | rg '.*-source(.*)$' --replace "\$1" | rg '^.*$' -U --replace "https://dl.google.com/dl/android/maven2\$0 $REP_NEWLINE https://repo.maven.apache.org/maven2\$0 $REP_NEWLINE https://plugins.gradle.org/m2\$0" | sed -e "s/$REP_NEWLINE/\n/g" | rg "(.*?)\.(pom|jar|aar)" --replace "\$1.pom $REP_NEWLINE \$1.jar $REP_NEWLINE \$1.aar" | sed -e "s/$REP_NEWLINE/\n/g" | sed 's/ //g' > "$TMP"

./create_repo.sh "$TMP"
