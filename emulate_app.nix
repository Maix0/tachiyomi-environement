{
  pkgs,
  defaultSdkArgs,
}: {
  name ? "android-emulator",
  installed ? [],
  runPackage,
  runActivity,
  runFlags ? "",
  sdkArgs ? defaultSdkArgs,
}: let
  sdk = (pkgs.androidenv.composeAndroidPackages sdkArgs).androidsdk;
in
  pkgs.writeScriptBin "run-test-emulator"
  ''
    #!${pkgs.runtimeShell} -e

    echo "$0"

    # We need a TMPDIR
    if [ "$TMPDIR" = "" ]
    then
        export TMPDIR=/tmp
    fi

    # Store the virtual devices somewhere else, instead of polluting a user's HOME directory
    export ANDROID_USER_HOME=$(mktemp -d $TMPDIR/nix-android-user-home-XXXX)


    export ANDROID_AVD_HOME=$ANDROID_USER_HOME/avd

    # We need to specify the location of the Android SDK root folder
    export ANDROID_SDK_ROOT=${sdk}/libexec/android-sdk


    # We have to look for a free TCP port

    echo "Looking for a free TCP port in range 5554-5584" >&2

    for i in $(seq 5554 2 5584)
    do
        if [ -z "$(${sdk}/bin/adb devices | grep emulator-$i)" ]
        then
            port=$i
            break
        fi
    done

    if [ -z "$port" ]
    then
        echo "Unfortunately, the emulator port space is exhausted!" >&2
        exit 1
    else
        echo "We have a free TCP port: $port" >&2
    fi

    export ANDROID_SERIAL="emulator-$port"

    # ${sdk}/bin/sdkmanager --list

    # Create a virtual android device for testing if it does not exist
    ${sdk}/bin/avdmanager list target

    if [ "$(${sdk}/bin/avdmanager list avd | grep 'Name: device')" = "" ]
    then
        echo "Creating a new device"
        # Create a virtual android device
        yes "" | ${sdk}/bin/avdmanager create avd --force -n device -k "system-images;android-${
      builtins.head sdkArgs.platformVersions
    };${
      builtins.head sdkArgs.systemImageTypes
    };${
      builtins.head sdkArgs.abiVersions
    }" -p $ANDROID_AVD_HOME $NIX_ANDROID_AVD_FLAGS

    fi

    # Launch the emulator
    echo -e "\nLaunch the emulator"
    $ANDROID_SDK_ROOT/emulator/emulator -avd device -no-boot-anim -port $port $NIX_ANDROID_EMULATOR_FLAGS &

    # Wait until the device has completely booted
    echo "Waiting until the emulator has booted the device and the package manager is ready..." >&2

    ${sdk}/libexec/android-sdk/platform-tools/adb -s emulator-$port wait-for-device

    echo "Device state has been reached" >&2

    while [ -z "$(${sdk}/libexec/android-sdk/platform-tools/adb -s emulator-$port shell getprop dev.bootcomplete | grep 1)" ]
    do
        sleep 5
    done

    echo "dev.bootcomplete property is 1" >&2


    echo "ready" >&2

    # Install the App through the debugger, if it has not been installed yet


    ${
      builtins.concatStringsSep "\n" (map (app:
        if app.passthru ? apkLocation && builtins.isString app.passthru.apkLocation
        then ''
          if [ "$(${sdk}/libexec/android-sdk/platform-tools/adb -s emulator-$port shell pm list packages | grep package:${app.passthru.packageName})" = "" ]
          then
              ${sdk}/libexec/android-sdk/platform-tools/adb -s emulator-$port install "${app}/${app.passthru.apkLocation}"
          fi
        ''
        else if app.passthru ? apkLocation && builtins.isList app.passthru.apkLocation
        then
          builtins.concatStringsSep "\n" (map (apkPath:
            if builtins.isString (apkPath ? null)
            then ''
              if [ "$(${sdk}/libexec/android-sdk/platform-tools/adb -s emulator-$port shell pm list packages | grep package:${app.passthru.packageName})" = "" ]
              then
                  ${sdk}/libexec/android-sdk/platform-tools/adb -s emulator-$port install "${app}/${apkPath}"
              fi
            ''
            else builtins.throw ''Given "apkPath" isn't a string. came from derivation "${
                if app ? name
                then app.name
                else "<no-name>"
              }" (${app})''))
          app.passthru.apkLocation
        else ''
          if [ "$(${sdk}/libexec/android-sdk/platform-tools/adb -s emulator-$port shell pm list packages | grep package:${app.passthru.packageName})" = "" ]
          then
              if [ -d "${app}" ]
              then
                  for apkFile in ${app}/*.apk; do
                    ${sdk}/libexec/android-sdk/platform-tools/adb -s emulator-$port install "$apkFile"
                  done;
              else
                  ${sdk}/libexec/android-sdk/platform-tools/adb -s emulator-$port install "${app}"
              fi
          fi
        '')
      installed)
    }

    # Start the application
    ${sdk}/libexec/android-sdk/platform-tools/adb -s emulator-$port shell am start -a android.intent.action.MAIN -n ${runPackage}/${runActivity} ${runFlags}

    echo "Waiting for the device to stop"
    while ${sdk}/libexec/android-sdk/platform-tools/adb -s emulator-$port get-state 1>/dev/null 2>/dev/null;
    do
        sleep 5
    done
  ''
