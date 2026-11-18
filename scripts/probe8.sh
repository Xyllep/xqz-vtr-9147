#!/usr/bin/env bash
# probe8: libndk из релиза -> /system -> bridge=libnb.so -> Карты
set -x
SDK=/usr/local/lib/android/sdk
ADB=/usr/local/lib/android/sdk/platform-tools/adb

echo "=== 1. Скачиваем tar из релиза ==="
gh release download maps-apk --repo Xyllep/gha-android --pattern 'libndk_translation-12.0.0.tar' --dir /tmp/nbdl
ls -la /tmp/nbdl/
mkdir -p nb && tar -xf /tmp/nbdl/libndk_translation-12.0.0.tar -C nb
find nb -maxdepth 3 -type d | head -15

echo "=== 2. Перезапуск эмулятора с -writable-system ==="
$ADB emu kill 2>/dev/null; sleep 10; pkill -f qemu 2>/dev/null; sleep 5
nohup $SDK/emulator/emulator -avd pixel6a \
  -no-window -no-boot-anim -no-metrics -no-audio \
  -gpu swiftshader_indirect -accel on -writable-system \
  > /tmp/emu5.log 2>&1 &
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "BOOT OK $((i*5))s"; break; }; done
$ADB root && sleep 3
$ADB remount 2>&1 | tail -1
$ADB shell mount -o remount,rw / 2>/dev/null || true
$ADB shell mount -o remount,rw /system 2>/dev/null || true
sleep 2
$ADB shell touch /system/.rwtest && { echo "/system writable"; $ADB shell rm /system/.rwtest; } || echo "/system STILL READ-ONLY"

echo "=== 3. Заливаем файлы ==="
cd nb
# в тарболе пути начинаются с system/ — кладём содержимое прямо в /system
for F in $(tar -tf /tmp/nbdl/libndk_translation-12.0.0.tar | grep -v '/$'); do
  REL=${F#system/}
  $ADB shell mkdir -p "/system/$(dirname $REL)"
  $ADB push "$F" "/system/$REL" >/dev/null 2>&1 && echo "ok $REL" || echo "FAIL $REL"
done
$ADB shell chmod 755 /system/bin/arm64/* /system/bin/ndk_translation_program_runner_binfmt_misc_arm64 2>/dev/null || true
$ADB shell chmod 644 /system/lib64/libndk_translation*.so /system/lib64/libnb.so /system/lib64/arm64/*.so /system/lib/libnb.so 2>/dev/null || true
cd - >/dev/null
echo "файлы на устройстве: $($ADB shell ls /system/lib64/arm64 | wc -l)"

echo "=== 4. build.prop + ребут ==="
$ADB shell "su 0 sed -i 's|^ro.dalvik.vm.native.bridge=.*|ro.dalvik.vm.native.bridge=libnb.so|' /system/build.prop"
$ADB shell getprop | grep -i nativebridge || true
$ADB reboot
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "REBOOT OK $((i*5))s"; break; }; done
sleep 10
echo "bridge: $($ADB shell getprop ro.dalvik.vm.native.bridge)"
echo "abilist: $($ADB shell getprop ro.product.cpu.abilist)"

echo "=== 5. Установка Карт ==="
cd /tmp/apks && $ADB install -r -g maps.apk 2>&1 | tail -3
cd /tmp/ya && $ADB install-multiple -r yandex_base.apk config.ru.apk config.xhdpi.apk 2>&1 | tail -3

echo "=== 6. Запуск Карт ==="
$ADB logcat -c
$ADB shell monkey -p ru.yandex.yandexmaps -c android.intent.category.LAUNCHER 1 2>&1 | tail -2
sleep 30
echo "pid: $($ADB shell pidof ru.yandex.yandexmaps)"
$ADB shell uiautomator dump /sdcard/p8.xml >/dev/null 2>&1
$ADB shell cat /sdcard/p8.xml 2>/dev/null | grep -oE 'text="[^"]{3,60}"' | head -15
$ADB exec-out screencap -p > probe/screen_probe8.png 2>/dev/null || true
echo "shot: $(stat -c%s probe/screen_probe8.png 2>/dev/null || echo 0)"
