#!/usr/bin/env bash
# probe7: libndk_translation из zhouziyang репо (raw tar) -> API33 AVD -> Карты
set -x
SDK=/usr/local/lib/android/sdk
ADB=/usr/local/lib/android/sdk/platform-tools/adb

echo "=== 1. Скачиваем tar ==="
curl -sL https://raw.githubusercontent.com/zhouziyang/libndk_translation/master/libndk_translation-13.0.0.tar -o probe/nb13.tar
ls -la probe/nb13.tar
mkdir -p nb13 && tar -tf probe/nb13.tar | head -40
tar -xf probe/nb13.tar -C nb13
find nb13 -maxdepth 3 | head -50

echo "=== 2. Перезапуск эмулятора с -writable-system ==="
$ADB emu kill 2>/dev/null; sleep 10; pkill -f qemu 2>/dev/null; sleep 5
nohup $SDK/emulator/emulator -avd pixel6a \
  -no-window -no-boot-anim -no-metrics -no-audio \
  -gpu swiftshader_indirect -accel on -writable-system \
  > /tmp/emu4.log 2>&1 &
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "BOOT OK $((i*5))s"; break; }; done
$ADB root && sleep 3
$ADB remount 2>&1 | tail -1

echo "=== 3. Кладём файлы (рекурсивно, сохраняя пути) ==="
if [ -d nb13/system ]; then
  cd nb13/system
  find . -type d | while read D; do $ADB shell mkdir -p "/system/${D#./}"; done
  find . -type f | while read F; do
    TGT="/system/${F#./}"
    $ADB push "$F" "$TGT" >/dev/null 2>&1 && echo "pushed $TGT" || echo "FAILED $TGT"
  done
  find . -type l | while read L; do
    TGT="/system/${L#./}"
    LN=$(readlink "$L")
    $ADB shell ln -sf "$LN" "$TGT" 2>/dev/null && echo "linked $TGT -> $LN"
  done
  $ADB shell chmod -R 755 /system/bin/arm /system/bin/arm64 /system/lib/arm /system/lib/arm64 /system/lib64/arm /system/lib64/arm64 2>/dev/null || true
  cd - >/dev/null
else
  echo "WARN: нет nb13/system"
  find nb13 | head -30
fi

echo "=== 4. build.prop + ребут ==="
$ADB shell "su 0 sed -i 's|^ro.dalvik.vm.native.bridge=.*|ro.dalvik.vm.native.bridge=libnb.so|' /system/build.prop" 2>/dev/null || true
$ADB shell "su 0 grep -q native.bridge /system/build.prop && echo prop-exists || echo 'ro.dalvik.vm.native.bridge=libnb.so' >> /system/build.prop"
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
$ADB shell uiautomator dump /sdcard/p7.xml >/dev/null 2>&1
$ADB shell cat /sdcard/p7.xml 2>/dev/null | grep -oE 'text="[^"]{3,60}"' | head -15
$ADB exec-out screencap -p > probe/screen_probe7.png 2>/dev/null || true
echo "shot: $(stat -c%s probe/screen_probe7.png 2>/dev/null || echo 0)"
