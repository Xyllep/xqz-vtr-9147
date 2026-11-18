#!/usr/bin/env bash
# probe6: пересадка libndk_translation (zhouziyang) в AVD API33 + установка Карт
set -x
SDK=/usr/local/lib/android/sdk
ADB=/usr/local/lib/android/sdk/platform-tools/adb

echo "=== 1. Скачиваем libndk_translation для Android 13 ==="
gh api repos/zhouziyang/libndk_translation/releases --jq '.[0] | {tag: .tag_name, assets: [.assets[].name]}' | tee probe/rel.json
URL=$(gh api repos/zhouziyang/libndk_translation/releases --jq '.[0].assets[] | select(.name | test("13")) | .browser_download_url' | head -1)
echo "URL=$URL"
curl -sL "$URL" -o probe/nb.tar
ls -la probe/nb.tar
mkdir -p nb && tar -xf probe/nb.tar -C nb 2>&1 | head -5
find nb -maxdepth 3 | head -30

echo "=== 2. Перезапуск эмулятора с -writable-system ==="
$ADB emu kill 2>/dev/null; sleep 10; pkill -f qemu 2>/dev/null; sleep 5
nohup $SDK/emulator/emulator -avd pixel6a \
  -no-window -no-boot-anim -no-metrics -no-audio \
  -gpu swiftshader_indirect -accel on -writable-system \
  > /tmp/emu3.log 2>&1 &
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "BOOT OK $((i*5))s"; break; }; done
$ADB root && sleep 3
$ADB remount 2>&1 | tail -2
sleep 2

echo "=== 3. Кладём файлы транслятора в /system ==="
# структура nb/: system/bin/arm64 ... lib64/... etc — заливаем всё как есть
find nb -type f -o -type l | head -50
if [ -d nb/system ]; then
  cd nb/system
  # lib64
  for F in lib64/libndk_translation.so lib64/libnb.so; do
    [ -f "$F" ] || [ -L "$F" ] || continue
    SRC=$(readlink -f "$F"); DST=${F#lib64/}
    $ADB push "$SRC" /system/lib64/$DST >/dev/null && echo "pushed $F"
  done
  $ADB shell mkdir -p /system/lib64/arm64
  for F in lib64/arm64/*.so; do
    [ -f "$F" ] || continue
    $ADB push "$F" /system/lib64/arm64/ >/dev/null && echo "pushed $F"
  done
  # bin/arm64 (linker64, app_process64)
  if [ -d bin/arm64 ]; then
    $ADB shell mkdir -p /system/bin/arm64
    for F in bin/arm64/*; do
      $ADB push "$F" /system/bin/arm64/ >/dev/null && echo "pushed $F"
    done
    $ADB shell chmod 755 /system/bin/arm64/* 2>/dev/null
  fi
  # etc конфиги
  for F in etc/ld.config.arm64.txt etc/ld.config.arm.txt etc/ndk_translation_arm64.rc; do
    [ -f "$F" ] && { $ADB push "$F" /system/${F#etc/} >/dev/null && echo "pushed $F"; }
  done
  cd - >/dev/null
else
  echo "WARN: структура nb/ неожиданная — смотрю и адаптирую"
  find nb -type f | head -40
fi

echo "=== 4. Прописываем native bridge в build.prop и ребут ==="
$ADB shell "su 0 sed -i 's/^ro.dalvik.vm.native.bridge=.*/ro.dalvik.vm.native.bridge=libndk_translation.so/' /system/build.prop" || true
$ADB shell "su 0 echo 'ro.dalvik.vm.native.bridge=libndk_translation.so' >> /system/build.prop" 2>/dev/null
$ADB shell getprop ro.dalvik.vm.native.bridge
$ADB reboot
for i in $(seq 1 60); do sleep 5; B=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$B" = "1" ] && { echo "REBOOT OK $((i*5))s"; break; }; done
sleep 10
echo "bridge now: $($ADB shell getprop ro.dalvik.vm.native.bridge)"
echo "abilist now: $($ADB shell getprop ro.product.cpu.abilist)"

echo "=== 5. Установка Карт ==="
cd /tmp/apks
$ADB install -r -g maps.apk 2>&1 | tail -3
cd /tmp/ya && $ADB install-multiple -r yandex_base.apk config.ru.apk config.xhdpi.apk 2>&1 | tail -3

echo "=== 6. Запуск Карт ==="
$ADB logcat -c
$ADB shell monkey -p ru.yandex.yandexmaps -c android.intent.category.LAUNCHER 1 2>&1 | tail -2
sleep 30
echo "pid: $($ADB shell pidof ru.yandex.yandexmaps)"
$ADB shell uiautomator dump /sdcard/p6.xml >/dev/null 2>&1
$ADB shell cat /sdcard/p6.xml 2>/dev/null | grep -oE 'text="[^"]{3,60}"' | head -15
$ADB exec-out screencap -p > probe/screen_probe6.png 2>/dev/null || true
echo "shot: $(stat -c%s probe/screen_probe6.png 2>/dev/null || echo 0)"
