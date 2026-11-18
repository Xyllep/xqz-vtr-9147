#!/usr/bin/env bash
# probe2: ищем libndk_translation в образах API 30/33/34, готовим файлы для пересадки
set -x
SDK=/usr/local/lib/android/sdk
MGR=$SDK/cmdline-tools/latest/bin/sdkmanager

echo "=== доступные образы x86_64 ==="
yes | $MGR --licenses >/dev/null 2>&1 || true
$MGR --list 2>/dev/null | grep -E "system-images;android-3[034];google_apis(_playstore)?;x86_64" | head -10

echo "=== качаем android-30 google_apis x86_64 (там точно был транслятор) ==="
$MGR --install "system-images;android-30;google_apis;x86_64" > /tmp/dl30.log 2>&1 && echo "dl30 OK" || tail -3 /tmp/dl30.log
IMG30=$(find $SDK/system-images/android-30 -name "system.img" 2>/dev/null | head -1)
echo "IMG30=$IMG30"
[ -n "$IMG30" ] && {
  echo "=== libndk в образе API30 ==="
  debugfs -R 'ls -l /system/lib64' "$IMG30" 2>/dev/null | grep -i -E "ndk|houdini|nativebridge" | head -10
  debugfs -R 'ls -l /system/lib64/arm64' "$IMG30" 2>/dev/null | head -5
  debugfs -R 'ls -l /system/bin' "$IMG30" 2>/dev/null | grep -i -E "ndk|houdini" | head -5
  mkdir -p probe/ndk30
  for F in libndk_translation.so; do
    debugfs -R "dump /system/lib64/$F probe/ndk30/$F" "$IMG30" 2>/dev/null && echo "dumped $F"
  done
  debugfs -R 'dump /system/etc/public.libraries.txt probe/ndk30/public.libraries.txt' "$IMG30" 2>/dev/null
  ls -la probe/ndk30/
}

echo "=== пробуем android-34 и playstore вариант (могут содержать транслятор) ==="
$MGR --install "system-images;android-34;google_apis;x86_64" > /tmp/dl34.log 2>&1 && echo "dl34 OK" || tail -2 /tmp/dl34.log
IMG34=$(find $SDK/system-images/android-34 -name "system.img" 2>/dev/null | head -1)
[ -n "$IMG34" ] && {
  echo "=== libndk в образе API34 ==="
  debugfs -R 'ls -l /system/lib64' "$IMG34" 2>/dev/null | grep -i -E "ndk|houdini" | head -5 || echo "нет"
}
IMG33=$(find $SDK/system-images/android-33 -name "system.img" 2>/dev/null | head -1)
[ -n "$IMG33" ] && {
  echo "=== libndk в нашем API33 ==="
  debugfs -R 'ls -l /system/lib64' "$IMG33" 2>/dev/null | grep -i -E "ndk|houdini" | head -5 || echo "нет"
}
df -h / | tail -1
