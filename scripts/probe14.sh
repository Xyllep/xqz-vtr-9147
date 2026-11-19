#!/usr/bin/env bash
# probe14: правим ro.{odm,vendor,system}.product.cpu.abilist (union -> abilist)
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
  > /tmp/emu11.log 2>&1 &
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "BOOT OK $((i*5))s"; break; }; done
$ADB root && sleep 3
$ADB disable-verity 2>&1 | tail -1
$ADB reboot
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "REBOOT1 OK $((i*5))s"; break; }; done
sleep 8; $ADB root && sleep 3
$ADB remount 2>&1 | tail -1
$ADB shell mount -o remount,rw /odm 2>/dev/null || true

echo "=== 2. Заливка транслятора ==="
cd nb
for F in $(tar -tf /tmp/nbdl/libndk_translation-12.0.0.tar | grep -v '/$'); do
  REL=${F#system/}
  $ADB shell mkdir -p "/system/$(dirname $REL)"
  $ADB push "$F" "/system/$REL" >/dev/null 2>&1 || echo "FAIL $REL"
done
$ADB shell chmod 755 /system/bin/arm64/* /system/bin/ndk_translation_program_runner_binfmt_misc_arm64 2>/dev/null || true
cd - >/dev/null

echo "=== 3. Правим abilist-источники ==="
SED64='s|^ro.\(odm\|vendor\|system\).product.cpu.abilist=.*|ro.\1.product.cpu.abilist=x86_64,arm64-v8a|'
for PF in /system/build.prop /vendor/build.prop /odm/etc/build.prop; do
  $ADB pull $PF /tmp/bpx >/dev/null 2>&1 || { echo "нет $PF"; continue; }
  sed -i \
    -e "s|^ro.odm.product.cpu.abilist=.*|ro.odm.product.cpu.abilist=x86_64,arm64-v8a|" \
    -e "s|^ro.vendor.product.cpu.abilist=.*|ro.vendor.product.cpu.abilist=x86_64,arm64-v8a|" \
    -e "s|^ro.system.product.cpu.abilist=.*|ro.system.product.cpu.abilist=x86_64,arm64-v8a|" \
    -e "s|^ro.odm.product.cpu.abilist64=.*|ro.odm.product.cpu.abilist64=x86_64,arm64-v8a|" \
    -e "s|^ro.vendor.product.cpu.abilist64=.*|ro.vendor.product.cpu.abilist64=x86_64,arm64-v8a|" \
    -e "s|^ro.system.product.cpu.abilist64=.*|ro.system.product.cpu.abilist64=x86_64,arm64-v8a|" \
    -e "s|^ro.dalvik.vm.native.bridge=.*|ro.dalvik.vm.native.bridge=libnb.so|" \
    /tmp/bpx
  $ADB push /tmp/bpx $PF >/dev/null
  $ADB shell chmod 644 $PF
done
echo "--- что теперь в файлах ---"
$ADB shell "grep -h 'abilist' /system/build.prop /vendor/build.prop /odm/etc/build.prop | grep -v '^#'" || true
$ADB reboot
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "REBOOT2 OK $((i*5))s"; break; }; done
sleep 10
echo "abilist: $($ADB shell getprop ro.product.cpu.abilist)"
echo "abilist64: $($ADB shell getprop ro.product.cpu.abilist64)"
echo "bridge: $($ADB shell getprop ro.dalvik.vm.native.bridge)"

echo "=== 4. Карты ==="
$ADB install -r -g /tmp/nbdl/maps3021.apk 2>&1 | tee /tmp/ins.txt
head -3 /tmp/ins.txt
echo "пакеты: $($ADB shell pm list packages | grep yandex | tr '\n' ' ')"

echo "=== 5. Запуск ==="
$ADB logcat -c
$ADB shell monkey -p ru.yandex.yandexmaps -c android.intent.category.LAUNCHER 1 2>&1 | tail -2
sleep 40
echo "pid: $($ADB shell pidof ru.yandex.yandexmaps)"
$ADB shell logcat -d 2>/dev/null | grep -iE "ndk_translation|FATAL|yandexmaps" | head -15
$ADB shell uiautomator dump /sdcard/p14.xml >/dev/null 2>&1
$ADB shell cat /sdcard/p14.xml 2>/dev/null | grep -oE 'text="[^"]{3,60}"' | head -15
$ADB exec-out screencap -p > probe/screen_probe14.png 2>/dev/null || true
echo "shot: $(stat -c%s probe/screen_probe14.png 2>/dev/null || echo 0)"
