#!/usr/bin/env bash
# Диагностика: почему Яндекс Карты не ставятся/не открываются
set -x

echo "=== 1. Устройство ==="
$ADB shell getprop ro.build.version.sdk
$ADB shell getprop ro.product.cpu.abilist
$ADB shell getprop ro.product.cpu.abilist64
$ADB shell getprop ro.dalvik.vm.native.bridge
$ADB shell getprop ro.enable.native.bridge.exec
$ADB shell getprop ro.product.model

echo "=== 2. Транслятор ARM ==="
$ADB shell ls -l /system/lib64/libndk_translation* 2>&1 | head -5
$ADB shell ls -l /system/lib/libndk_translation* 2>&1 | head -5
$ADB shell ls /system/lib64/arm64 2>&1 | head -3
$ADB shell ls /system/etc/ 2>/dev/null | grep -i -E "ndk|nativebridge" | head -5

echo "=== 3. Установка Карт ==="
cd /tmp/apks 2>/dev/null || cd /tmp
$ADB uninstall ru.yandex.yandexmaps 2>/dev/null
$ADB install -r -g maps.apk 2>&1 | tail -3
echo "--- повтор с --abi arm64-v8a ---"
$ADB install -r -g --abi arm64-v8a maps.apk 2>&1 | tail -3

echo "=== 4. Что установлено ==="
$ADB shell pm list packages | grep -i -E "yandex|browser|chrome"

echo "=== 5. Попытка запуска Карт ==="
$ADB logcat -c
$ADB shell monkey -p ru.yandex.yandexmaps -c android.intent.category.LAUNCHER 1 2>&1 | tail -3
sleep 20
$ADB shell pidof ru.yandex.yandexmaps || echo "процесс Карт не запущен"
$ADB logcat -d 2>/dev/null | grep -i -E "yandexmaps|NO_MATCHING_ABIS|UnsatisfiedLink|dlopen|crash" | tail -25

echo "=== 6. Экран ==="
$ADB shell uiautomator dump /sdcard/probe.xml >/dev/null 2>&1 || true
$ADB shell cat /sdcard/probe.xml 2>/dev/null | head -c 3000
echo
$ADB exec-out screencap -p > /tmp/probe_screen.png 2>/dev/null || true
echo "screenshot bytes: $(stat -c%s /tmp/probe_screen.png 2>/dev/null || echo 0)"
