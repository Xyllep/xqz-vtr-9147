#!/usr/bin/env bash
# probe11: как probe10, но abilist пишем в system+vendor build.prop
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
  > /tmp/emu8.log 2>&1 &
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

echo "=== 3. Где определён abilist ==="
$ADB shell "grep -rln 'cpu.abilist' /system/build.prop /vendor/build.prop /odm/etc/ /product/build.prop /system/etc/prop.default 2>/dev/null" || true
$ADB shell getprop | grep -iE 'abilist|isa\.arm|native.bridge' || true

echo "=== 4. Прописываем во все prop-файлы ==="
APEND='ro.dalvik.vm.native.bridge=libnb.so
ro.product.cpu.abilist=x86_64,x86,arm64-v8a
ro.product.cpu.abilist32=x86
ro.product.cpu.abilist64=x86_64,arm64-v8a
ro.dalvik.vm.isa.arm=x86
ro.dalvik.vm.isa.arm64=x86_64'
for PF in /system/build.prop /vendor/build.prop; do
  $ADB shell "su 0 sed -i -e 's|^ro.product.cpu.abilist=.*|ro.product.cpu.abilist=x86_64,x86,arm64-v8a|' \
    -e 's|^ro.product.cpu.abilist32=.*|ro.product.cpu.abilist32=x86|' \
    -e 's|^ro.product.cpu.abilist64=.*|ro.product.cpu.abilist64=x86_64,arm64-v8a|' \
    -e 's|^ro.dalvik.vm.isa.arm=.*|ro.dalvik.vm.isa.arm=x86|' \
    -e 's|^ro.dalvik.vm.isa.arm64=.*|ro.dalvik.vm.isa.arm64=x86_64|' \
    -e 's|^ro.dalvik.vm.native.bridge=.*|ro.dalvik.vm.native.bridge=libnb.so|' $PF" || true
  $ADB shell "su 0 printf '$APEND\n' >> $PF"
done
# ro.system.product.* и ro.vendor.product.* тоже
$ADB shell "su 0 sed -i -e 's|^ro.system.product.cpu.abilist=.*|ro.system.product.cpu.abilist=x86_64,x86,arm64-v8a|' \
  -e 's|^ro.system.product.cpu.abilist64=.*|ro.system.product.cpu.abilist64=x86_64,arm64-v8a|' /system/build.prop" || true
$ADB shell "su 0 sed -i -e 's|^ro.vendor.product.cpu.abilist=.*|ro.vendor.product.cpu.abilist=x86_64,x86,arm64-v8a|' \
  -e 's|^ro.vendor.product.cpu.abilist64=.*|ro.vendor.product.cpu.abilist64=x86_64,arm64-v8a|' /vendor/build.prop" || true
$ADB reboot
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "REBOOT2 OK $((i*5))s"; break; }; done
sleep 10
echo "--- после ребута ---"
$ADB shell getprop | grep -iE 'abilist|isa\.arm|native.bridge' || true

echo "=== 5. Карты ==="
$ADB install -r -g /tmp/nbdl/maps3021.apk 2>&1 | tail -2
cd /tmp/ya && $ADB install-multiple -r yandex_base.apk config.ru.apk config.xhdpi.apk 2>&1 | tail -3

echo "=== 6. Запуск ==="
$ADB logcat -c
$ADB shell monkey -p ru.yandex.yandexmaps -c android.intent.category.LAUNCHER 1 2>&1 | tail -2
sleep 35
echo "pid: $($ADB shell pidof ru.yandex.yandexmaps)"
$ADB shell uiautomator dump /sdcard/p11.xml >/dev/null 2>&1
$ADB shell cat /sdcard/p11.xml 2>/dev/null | grep -oE 'text="[^"]{3,60}"' | head -15
$ADB exec-out screencap -p > probe/screen_probe11.png 2>/dev/null || true
echo "shot: $(stat -c%s probe/screen_probe11.png 2>/dev/null || echo 0)"
