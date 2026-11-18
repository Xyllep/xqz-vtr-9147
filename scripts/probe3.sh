#!/usr/bin/env bash
# probe3: включаем ARM-трансляцию принудительно и пробуем ставить Карты
set -x
SDK=/usr/local/lib/android/sdk
ADB=/usr/local/lib/android/sdk/platform-tools/adb

echo "=== 1. Есть ли ndk_translation в пакете эмулятора ==="
ls $SDK/emulator/lib64/ 2>/dev/null | grep -i -E "ndk|translation" || echo "нет в lib64"
ls $SDK/emulator/lib64/ndk_translation/ 2>/dev/null | head -10
find $SDK/emulator -maxdepth 2 -iname "*ndk*" 2>/dev/null | head -10
strings $SDK/emulator/emulator 2>/dev/null | grep -m3 -i "ndk_translation"

echo "=== 2. Что в build.prop образов ==="
IMG30=$(find $SDK/system-images/android-30 -name system.img | head -1)
IMG33=$(find $SDK/system-images/android-33 -name system.img | head -1)
debugfs -R 'cat /system/build.prop' "$IMG30" 2>/dev/null | grep -E "native.bridge|abi" | head -6
echo "--- api33:"
debugfs -R 'cat /system/build.prop' "$IMG33" 2>/dev/null | grep -E "native.bridge|abi" | head -6

echo "=== 3. Перезапуск эмулятора с трансляцией ==="
$ADB emu kill 2>/dev/null; sleep 10; pkill -f qemu 2>/dev/null; sleep 5
AVD_HOME=$(dirname $(find /home/runner -name pixel6a.avd -maxdepth 8 2>/dev/null | head -1))/..
nohup $SDK/emulator/emulator -avd pixel6a \
  -no-window -no-boot-anim -no-metrics -no-audio \
  -gpu swiftshader_indirect -accel on \
  -writable-system \
  -prop ro.dalvik.vm.native.bridge=libndk_translation.so \
  -prop ro.enable.native.bridge.exec=1 \
  > /tmp/emu2.log 2>&1 &
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "BOOT OK $((i*5))s"; break; }; done

echo "=== 4. Состояние трансляции ==="
$ADB shell getprop ro.dalvik.vm.native.bridge
$ADB shell getprop ro.product.cpu.abilist
$ADB shell ls -l /system/lib64/libndk_translation.so 2>&1 | head -2
$ADB shell ls /system/lib64/arm64 2>&1 | head -5

echo "=== 5. Установка Карт ==="
cd /tmp/apks 2>/dev/null || cd /tmp
$ADB install -r -g --abi arm64-v8a maps.apk 2>&1 | tail -3

echo "=== 6. Установка приложения Яндекс ==="
cd /tmp/ya 2>/dev/null || true
$ADB install-multiple -r yandex_base.apk config.ru.apk config.xhdpi.apk 2>&1 | tail -3

echo "=== 7. Запуск Карт ==="
$ADB logcat -c
$ADB shell monkey -p ru.yandex.yandexmaps -c android.intent.category.LAUNCHER 1 2>&1 | tail -2
sleep 25
echo "pid: $($ADB shell pidof ru.yandex.yandexmaps)"
$ADB logcat -d 2>/dev/null | grep -iE "yandexmaps.*(crash|died|fatal)|ndk_translation|nativebridge" | tail -15
$ADB exec-out screencap -p > probe/screen_probe3.png 2>/dev/null || true
$ADB shell uiautomator dump /sdcard/p3.xml >/dev/null 2>&1
$ADB shell cat /sdcard/p3.xml 2>/dev/null | head -c 2000
