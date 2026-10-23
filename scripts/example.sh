#!/bin/bash
# Пример скрипта автоматизации: заменяй на свои команды
ADB=/usr/local/lib/android/sdk/platform-tools/adb
echo "Экран:"; $ADB shell wm size
echo "Модель:"; $ADB shell getprop ro.product.model
echo "Geo-провайдеры:"; $ADB shell settings get secure location_providers_allowed 2>/dev/null
# Пример тапа по центру экрана:
# $ADB shell input tap 540 1200
