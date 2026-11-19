#!/usr/bin/env bash
# probe12: bridge=libnb.so, abilist НЕ трогаем, установка --abi arm64-v8a
set -x
SDK=/usr/local/lib/android/sdk
ADB=/usr/local/lib/android/sdk/platform-tools/adb

echo "=== 0. Файлы ==="
gh release download maps-apk --repo Xyllep/gha-android --dir /tmp/nbdl
mkdir -p nb && tar -xf /tmp/nbdl/libndk_translation-12.0.0.tar -C nb

echo "=== 1. Эмулятор ==="
$ADB emu kill 2>/dev/null; sleep 10; pkill -f qemu 2>/dev/null; sleep 5
nohup $SDK/emulator/emulator -avd pixel6a \
  -no-window -no-boot-anim -no-metrics -no-audio \
  -gpu swiftshader_indirect -accel on -writable-system \
  > /tmp/emu9.log 2>&1 &
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "BOOT OK $((i*5))s"; break; }; done
$ADB root && sleep 3
$ADB disable-verity 2>&1 | tail -1
$ADB reboot
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "REBOOT1 OK $((i*5))s"; break; }; done
sleep 8; $ADB root && sleep 3
$ADB remount 2>&1 | tail -1

echo "=== 2. Заливка транслятора ==="
cd nb
for F in $(tar -tf /tmp/nbdl/libndk_translation-12.0.0.tar | grep -v '/$'); do
  REL=${F#system/}
  $ADB shell mkdir -p "/system/$(dirname $REL)"
  $ADB push "$F" "/system/$REL" >/dev/null 2>&1 || echo "FAIL $REL"
done
$ADB shell chmod 755 /system/bin/arm64/* /system/bin/ndk_translation_program_runner_binfmt_misc_arm64 2>/dev/null || true
cd - >/dev/null
# только native bridge, abilist не трогаем!
$ADB shell "su 0 sed -i 's|^ro.dalvik.vm.native.bridge=.*|ro.dalvik.vm.native.bridge=libnb.so|' /system/build.prop"
$ADB reboot
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "REBOOT2 OK $((i*5))s"; break; }; done
sleep 10
echo "bridge: $($ADB shell getprop ro.dalvik.vm.native.bridge)"
echo "abilist: $($ADB shell getprop ro.product.cpu.abilist)"

echo "=== 3. Карты (--abi) ==="
$ADB install -r -g --abi arm64-v8a /tmp/nbdl/maps3021.apk 2>&1 | tail -3
cd /tmp/ya && $ADB install-multiple -r -g --abi arm64-v8a yandex_base.apk config.ru.apk config.xhdpi.apk 2>&1 | tail -3
echo "пакеты: $($ADB shell pm list packages | grep -E 'yandex' | tr '\n' ' ')"

echo "=== 4. Запуск ==="
$ADB logcat -c
$ADB shell monkey -p ru.yandex.yandexmaps -c android.intent.category.LAUNCHER 1 2>&1 | tail -2
sleep 40
echo "pid: $($ADB shell pidof ru.yandex.yandexmaps)"
$ADB shell logcat -d 2>/dev/null | grep -iE "ndk_translation|arm64|FATAL|yandexmaps" | head -20
$ADB shell uiautomator dump /sdcard/p12.xml >/dev/null 2>&1
$ADB shell cat /sdcard/p12.xml 2>/dev/null | grep -oE 'text="[^"]{3,60}"' | head -15
$ADB exec-out screencap -p > probe/screen_probe12.png 2>/dev/null || true
echo "shot: $(stat -c%s probe/screen_probe12.png 2>/dev/null || echo 0)"
