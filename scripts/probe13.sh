#!/usr/bin/env bash
# probe13: abilist 64-only (x86_64+arm64-v8a), полный лог установки Карт
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
  > /tmp/emu10.log 2>&1 &
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

echo "=== 3. abilist 64-only ==="
$ADB pull /system/build.prop /tmp/bp13 >/dev/null
sed -i \
  -e 's|^ro.dalvik.vm.native.bridge=.*|ro.dalvik.vm.native.bridge=libnb.so|' \
  -e 's|^ro.product.cpu.abilist=.*|ro.product.cpu.abilist=x86_64,arm64-v8a|' \
  -e 's|^ro.product.cpu.abilist32=.*||' \
  -e 's|^ro.product.cpu.abilist64=.*|ro.product.cpu.abilist64=x86_64,arm64-v8a|' \
  -e 's|^ro.system.product.cpu.abilist=.*|ro.system.product.cpu.abilist=x86_64,arm64-v8a|' \
  -e 's|^ro.system.product.cpu.abilist32=.*||' \
  -e 's|^ro.system.product.cpu.abilist64=.*|ro.system.product.cpu.abilist64=x86_64,arm64-v8a|' \
  -e 's|^ro.dalvik.vm.isa.arm64=.*|ro.dalvik.vm.isa.arm64=x86_64|' \
  /tmp/bp13
$ADB push /tmp/bp13 /system/build.prop >/dev/null
$ADB shell chmod 644 /system/build.prop
$ADB reboot
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "REBOOT2 OK $((i*5))s"; break; }; done
sleep 10
echo "bridge: $($ADB shell getprop ro.dalvik.vm.native.bridge)"
echo "abilist: $($ADB shell getprop ro.product.cpu.abilist)"
echo "abilist64: $($ADB shell getprop ro.product.cpu.abilist64)"

echo "=== 4. Карты (полный лог) ==="
$ADB install -r -g /tmp/nbdl/maps3021.apk 2>&1 | tee probe/install_maps.txt
echo "--- хвост ошибки ---"
head -8 probe/install_maps.txt
cd /tmp/ya && $ADB install-multiple -r -g yandex_base.apk config.ru.apk config.xhdpi.apk 2>&1 | tee probe/install_ya.txt | tail -4
echo "пакеты: $($ADB shell pm list packages | grep yandex | tr '\n' ' ')"

echo "=== 5. Запуск ==="
$ADB logcat -c
$ADB shell monkey -p ru.yandex.yandexmaps -c android.intent.category.LAUNCHER 1 2>&1 | tail -2
sleep 40
echo "pid: $($ADB shell pidof ru.yandex.yandexmaps)"
$ADB shell logcat -d 2>/dev/null | grep -iE "ndk_translation|FATAL|yandexmaps" | head -15
$ADB shell uiautomator dump /sdcard/p13.xml >/dev/null 2>&1
$ADB shell cat /sdcard/p13.xml 2>/dev/null | grep -oE 'text="[^"]{3,60}"' | head -15
$ADB exec-out screencap -p > probe/screen_probe13.png 2>/dev/null || true
echo "shot: $(stat -c%s probe/screen_probe13.png 2>/dev/null || echo 0)"
