#!/bin/bash

dl_gh() {
    for repo in $1 ; do
    wget -qO- "https://api.github.com/repos/$2/$repo/releases/$3" \
    | jq -r '.assets[] | "\(.browser_download_url) \(.name)"' \
    | while read -r url names; do
        echo "Downloading $names from $url"
        wget -q -O "$names" $url
    done
    done
echo "All assets downloaded"
}

get_patches_key() {
    EXCLUDE_PATCHES=()
        for word in $(cat src/patches/$1/exclude-patches) ; do
            EXCLUDE_PATCHES+=("-e $word")
        done
    INCLUDE_PATCHES=()
        for word in $(cat src/patches/$1/include-patches) ; do
            INCLUDE_PATCHES+=("-i $word")
        done
}

req() { 
    wget -nv -O "$2" -U "Mozilla/5.0 (X11; Linux x86_64; rv:111.0) Gecko/20100101 Firefox/111.0" "$1"
}
get_apk_vers() { 
    req "$1" - | sed -n 's;.*Version:</span><span class="infoSlide-value">\(.*\) </span>.*;\1;p'
}
get_largest_ver() {
  local max=0
  while read -r v || [ -n "$v" ]; do   		
	if [[ ${v//[!0-9]/} -gt ${max//[!0-9]/} ]]; then max=$v; fi
	  done
      	if [[ $max = 0 ]]; then echo ""; else echo "$max"; fi
}

dl_apk() {
  local url=$1 regexp=$2 output=$3
  url="https://www.apkmirror.com$(req "$url" - | tr '\n' ' ' | sed -n "s/href=\"/@/g; s;.*${regexp}.*;\1;p")"
  echo "$url"
  url="https://www.apkmirror.com$(req "$url" - | tr '\n' ' ' | sed -n 's;.*href="\(.*key=[^"]*\)">.*;\1;p')"
  url="https://www.apkmirror.com$(req "$url" - | tr '\n' ' ' | sed -n 's;.*href="\(.*key=[^"]*\)">.*;\1;p')"
  req "$url" "$output"
}

get_apk() {
  if [[ -z $4 ]]; then
	url_regexp='APK</span>[^@]*@\([^#]*\)'
  else
    case $4 in
      arm64-v8a) url_regexp='arm64-v8a</div>[^@]*@\([^"]*\)' ;;
      armeabi-v7a) url_regexp='armeabi-v7a</div>[^@]*@\([^"]*\)' ;;
      x86) url_regexp='x86</div>[^@]*@\([^"]*\)' ;;
      x86_64) url_regexp='x86_64</div>[^@]*@\([^"]*\)' ;;
      *) return 1 ;;
    esac 
  fi
  export version="$version"
  if [[ -z $version ]]; then
    version=${version:-$(get_apk_vers "https://www.apkmirror.com/uploads/?appcategory=$2" | get_largest_ver)}
  fi
  local base_apk="$1.apk"
  local dl_url=$(dl_apk "https://www.apkmirror.com/apk/$3-${version//./-}-release/" \
			"$url_regexp" \
			"$base_apk")
}

get_ver() {
    version=$(jq -r --arg patch_name "$1" --arg pkg_name "$2" '
    .[]
    | select(.name == $patch_name)
    | .compatiblePackages[]
    | select(.name == $pkg_name)
    | .versions[-1]
    ' patches.json)
}

patch() {
    if [ -f "$1.apk" ]; then
    java -jar revanced-cli*.jar \
    -m revanced-integrations*.apk \
    -b revanced-patches*.jar \
    -a $1.apk \
    ${EXCLUDE_PATCHES[@]} \
    ${INCLUDE_PATCHES[@]} \
    --keystore=./src/ks.keystore \
    -o ./build/$2.apk
	if grep -q "/" <<< "$2"; then
		local name=$(basename “$2”)
		cp ./build/$2.apk ./build/$name.apk
	fi
    unset version
    unset EXCLUDE_PATCHES
    unset INCLUDE_PATCHES
    else 
        exit 1
    fi
}

merge_arch() {
    java -jar APKEditor*.jar m \
    -i ./build/$1
	mv -i ./build/"$1"_merged.apk ./build/"$1"-"$2".apk
}

archs=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")
libs=("x86_64 x86 armeabi-v7a" "x86_64 x86 arm64-v8a" "x86 armeabi-v7a arm64-v8a" "x86_64 armeabi-v7a arm64-v8a")
gen_rip_libs() {
    for lib in $@; do
        echo -n "--rip-lib $lib "
    done
}
split_arch() {
    if [ -f "./build/$1.apk" ]; then
    java -jar revanced-cli*.jar \
	-b revanced-patches*.jar \
    -a ./build/$1.apk \
    --keystore=./src/ks.keystore \
	$3 \
    -o ./build/$2.apk
    else 
        exit 1
    fi
}