#!/usr/bin/env bash
while read -r path; do
	for repo in "https://repo.maven.apache.org/maven2" "https://plugins.gradle.org/m2" "https://dl.google.com/dl/android/maven2/" "https://jitpack.io/"; do
		if curl -ILf "$repo/$path" >/dev/null 2>&1; then
			echo "$repo/$path"
			break
		fi
	done
done <out.list
