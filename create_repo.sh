#!/usr/bin/env bash
OUT_RAW=$(mktemp -d)
OUT="$OUT_RAW/data"

if [ -z "$1" ]; then
	exit 1
fi

mkdir -p "$OUT"

urls=$(while read -r url; do
	dest=$(if [[ $url =~ ^https://dl.google.com/dl/android/maven2/* ]]; then
		prefix="https://dl.google.com/dl/android/maven2/"
		echo "${url/#"$prefix"/}"
	elif [[ $url =~ ^https://jitpack.io/* ]]; then
		prefix="https://jitpack.io/"
		echo "${url/#"$prefix"/}"
	elif [[ $url =~ ^https://plugins.gradle.org/m2/* ]]; then
		prefix="https://plugins.gradle.org/m2/"
		echo "${url/#"$prefix"/}"
	elif [[ $url =~ ^https://repo.maven.apache.org/maven2/* ]]; then
		prefix="https://repo.maven.apache.org/maven2/"
		echo "${url/#"$prefix"/}"
	else
		echo "UNKNOWN URL: $url" >&2
		exit 1
	fi)
	echo "$dest $url"
done <"$1")

readarray -t inputs <<<"$urls"
for val in "${inputs[@]}"; do
	if read -r dest url; then
		mkdir -p "$(dirname "$OUT/$dest")"
		if curl -f -L -o "$OUT/$dest" "$url" >/dev/null 2>&1; then
			echo -e "[\x1b[32mOK\x1b[0m] $url"
		else
			echo -e "[\x1b[31mER\x1b[0m] $url"
		fi
	fi <<<"$val"
done

tar uvf repo.tar -C "$OUT_RAW" .

#echo "])"
