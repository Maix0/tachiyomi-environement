{
  description = "Flake utils demo";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.repository.url = "https://maix.me/tachiyomi_gradle_repo.tar";
  inputs.repository.flake = false;
  inputs.tachiyomi-extensions.url = "github:Maix0/tachiyomi-extensions";
  inputs.tachiyomi-extensions.flake = false;
  inputs.tachiyomi-apk.url = "https://github.com/tachiyomiorg/tachiyomi/releases/download/v0.14.6/tachiyomi-v0.14.6.apk";
  inputs.tachiyomi-apk.flake = false;

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    repository,
    tachiyomi-extensions,
    tachiyomi-apk,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          system = system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };
        defaultSdkArgs =
          {
            buildToolsVersions = ["30.0.3"];
            platformVersions = ["33"];
            abiVersions = ["arm64-v8a"];
            systemImageTypes = ["default"];
            cmdLineToolsVersion = "8.0";
          }
          // {
            includeEmulator = true;
            includeSystemImages = true;
            /*
              includeExtras = [
              "system-images;android-${
                builtins.head defaultSdkArgs.platformVersions
              };${
                builtins.head defaultSdkArgs.systemImageTypes
              };${
                builtins.head defaultSdkArgs.abiVersions
              }"
            ];
            */
          };

        buildExtension = (
          {
            gradleTask,
            name,
            packageName,
            buildType ? "debug",
            sdkArgs ? defaultSdkArgs,
          }
          : (
            let
              sdk = (pkgs.androidenv.composeAndroidPackages sdkArgs).androidsdk;
              ANDROID_SDK_ROOT = "${sdk}/libexec/android-sdk";
              patched_repository = pkgs.stdenv.mkDerivation {
                name = "repository-aapt2-patched";
                src = repository;
                buildPhase = with pkgs; ''
                  export CUR_DIR=$(pwd)
                  cd com/android/tools/build/aapt2/*/
                  ${unzip}/bin/unzip *.jar aapt2
                  ${patchelf}/bin/patchelf aapt2 --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)"
                  ${zip}/bin/zip -r *.jar aapt2
                  rm aapt2
                  cd "$CUR_DIR"
                '';
                installPhase = ''
                  mkdir -p $out
                  mv * $out/
                '';
              };

              repo_code = ''
                maven {url = uri("file://" + "${patched_repository}") }
              '';
            in
              pkgs.stdenv.mkDerivation {
                inherit name;
                src = tachiyomi-extensions;
                buildInputs = with pkgs; [gradle sdk openjdk kotlin fastmod ripgrep];
                unpackCmd = ''
                  cp -r $curSrc .
                '';

                passthru = {inherit packageName;};

                buildPhase = with pkgs; ''
                  export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}"
                  export ANDROID_NDK_ROOT="${ANDROID_SDK_ROOT}/ndk-bundle";
                  export PATH="${ANDROID_SDK_ROOT}/build-tools/${builtins.head sdkArgs.buildToolsVersions}:$PATH"
                  export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=${ANDROID_SDK_ROOT}/build-tools/${builtins.head sdkArgs.buildToolsVersions}/aapt2"
                  export GRADLE_USER_HOME="$(mktemp -d)"



                  echo "Fixing Repositories"
                  ${
                    builtins.concatStringsSep "\n" (builtins.map (
                        pat: ''
                          ${fastmod}/bin/fastmod --accept-all '${pat}' '${repo_code}'
                        ''
                      )
                      [''maven\(.*?\)'' ''mavenCentral\(\)'' ''google\(\)''])
                  }
                  echo "Fixed Repositories"

                  echo "Fixing Plugins"
                  ${fastmod}/bin/fastmod '`(.*?)`' '"${"$" + "{1}"}"' -e "kts,gradle" --accept-all
                  echo "Fixed Plugins"

                  echo "Fixing Android Config in .kts files"

                  export _DATA="$(${ripgrep}/bin/rg 'const val (\w+) = (.*)$' --replace "\$1 0000PLEASE_SWAP_WITH_AN_NEWLINE0000 \$2" ./buildSrc/src/main/kotlin/AndroidConfig.kt | sed -e "s/0000PLEASE_SWAP_WITH_AN_NEWLINE0000/\n/" | sed 's/^ *//;s/ *$//')"

                  echo "$_DATA" | while read -r name && read -r value; do
                    ${fastmod}/bin/fastmod -F "AndroidConfig.$name" "($value)" -e "kts,gradle" --accept-all
                  done;

                  echo "Fixed Android Config in .kts files"


                  echo "Generating Extension code"
                  ${gradle}/bin/gradle --no-daemon --console plain multisrc:generateExtensions || exit 1;
                  echo "Generated Extension code"
                  echo "Building Apk"
                  ${gradle}/bin/gradle --no-daemon --console plain "${gradleTask}"
                '';
                installPhase = ''
                  mkdir -p $out
                  mv ./generated-src/en/*/build/outputs/apk/${buildType}/*.apk $out/ || true
                '';
              }
          )
        );
      in rec {
        lib = {
          defaultSdkArgs = defaultSdkArgs;
          buildExtension = buildExtension;
          runEmulator = import ./emulate_app.nix {inherit pkgs defaultSdkArgs;};
        };
        apps = {
          enryu-extension = flake-utils.lib.mkApp {
            drv = lib.runEmulator {
              name = "enryu-emulator";
              installed = [(tachiyomi-apk // {passthru.packageName = "eu.kanade.tachiyomi";}) packages.enryu-apk];
              runPackage = "eu.kanade.tachiyomi";
              runActivity = "eu.kanade.tachiyomi.ui.main.MainActivity";
              runFlags = "-a eu.kanade.tachiyomi.SHOW_CATALOGUES";
            };
          };
        };

        packages = {
          enryu-apk = buildExtension {
            gradleTask = "extensions:multisrc:en:enryumanga:assembleDebug";
            name = "enryu-apk";
            packageName = "eu.kanade.tachiyomi.extension.en.enryumanga";
          };
          zahard-apk = buildExtension {
            gradleTask = "extensions:multisrc:en:zahard:assembleDebug";
            name = "zahard-apk";
            packageName = "eu.kanade.tachiyomi.extension.en.zahard";
          };
        };
      }
    );
}
