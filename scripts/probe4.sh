#!/usr/bin/env bash
# probe4: ищем версию эмулятора с bundled ndk_translation
set -x
mkdir -p probe/emus

# известные сборки эмулятора (канонические URL dl.google.com)
declare -A EMUS=(
  [31.3.10]=https://dl.google.com/android/repository/emulator-linux_x64-9444347.zip
  [31.2.10]=https://dl.google.com/android/repository/emulator-linux_x64-8403352.zip
  [31.1.5]=https://dl.google.com/android/repository/emulator-linux_x64-7942061.zip
  [30.9.5]=https://dl.google.com/android/repository/emulator-linux_x64-7521544.zip
)

for V in 31.3.10 31.2.10 31.1.5 30.9.5; do
  URL=${EMUS[$V]}
  Z=probe/emus/emulator-$V.zip
  echo "=== $V: $URL"
  curl -sIL "$URL" -o /dev/null -w "http=%{http_code} size=%{size_download}\n" || continue
done

# качаем самый свежий из живых, ищем ndk
for V in 31.3.10 31.2.10 31.1.5 30.9.5; do
  URL=${EMUS[$V]}
  Z=probe/emus/emulator-$V.zip
  if curl -sL "$URL" -o "$Z" && [ $(stat -c%s "$Z" 2>/dev/null || echo 0) -gt 100000000 ]; then
    echo "== $V скачан: $(stat -c%s $Z)"
    unzip -l "$Z" | grep -i -E "ndk_translation|arm64" | head -8
    # если есть — распаковываем и сохраняем факт
    if unzip -l "$Z" | grep -qi "ndk_translation"; then
      mkdir -p probe/emu_$V
      unzip -oq "$Z" -d probe/emu_$V
      ls probe/emu_$V/ | head -5
      ls probe/emu_$V/lib64/ 2>/dev/null | grep -i ndk | head -5
      echo "FOUND_NDK_EMU=$V" | tee probe/found_emu.txt
      break
    fi
  else
    echo "== $V не скачался"
  fi
done
df -h / | tail -1
