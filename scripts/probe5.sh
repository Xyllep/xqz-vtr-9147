#!/usr/bin/env bash
# probe5: пробуем XAPK Яндекс Карт с APKPure (ищем x86_64 сплит)
set -x
mkdir -p /tmp/xapk && cd /tmp/xapk
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"

echo "=== 1. Качаем XAPK ==="
curl -sL -A "$UA" "https://d.apkpure.com/b/XAPK/com.yandex.yandexmaps?version=latest" -o maps.xapk --max-time 300
ls -la maps.xapk
file maps.xapk

echo "=== 2. Распаковка ==="
unzip -oq maps.xapk -d x 2>/dev/null || echo "unzip failed"
ls -la x/ 2>/dev/null | head -20
for A in x/*.apk; do
  [ -f "$A" ] || continue
  echo "== $(basename $A): $(unzip -l $A 2>/dev/null | grep -oE 'lib/[a-z0-9_-]+/' | sort -u | tr '\n' ' ')"
done

echo "=== 3. Если есть x86_64 сплит — ставим ==="
X64=$(ls x/*x86_64*.apk x/*arm64*.apk 2>/dev/null | head -1)
BASE=$(ls x/*base*.apk 2>/dev/null | head -1)
if [ -n "$BASE" ] && [ -n "$X64" ]; then
  $ADB install-multiple -r "$BASE" $X64 2>&1 | tail -3
  ls x/*.apk | grep -vE "base|x86_64|arm64" | while read S; do $ADB install -r "$S" 2>&1 | tail -1; done
elif ls x/*.apk >/dev/null 2>&1; then
  for A in x/*.apk; do
    LIBS=$(unzip -l "$A" 2>/dev/null | grep -oE 'lib/[a-z0-9_-]+/' | sort -u | tr '\n' ' ')
    echo "$A -> $LIBS"
  done
fi

echo "=== 4. Проверка установки и запуск ==="
$ADB shell pm list packages | grep yandex
$ADB logcat -c
$ADB shell monkey -p ru.yandex.yandexmaps -c android.intent.category.LAUNCHER 1 2>&1 | tail -2
sleep 25
echo "pid: $($ADB shell pidof ru.yandex.yandexmaps)"
$ADB shell uiautomator dump /sdcard/p5.xml >/dev/null 2>&1
$ADB shell cat /sdcard/p5.xml 2>/dev/null | grep -oE 'text="[^"]{3,60}"' | head -15
$ADB exec-out screencap -p > probe/screen_probe5.png 2>/dev/null || true
echo "shot: $(stat -c%s probe/screen_probe5.png 2>/dev/null || echo 0)"
