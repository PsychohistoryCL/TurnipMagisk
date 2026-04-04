#!/system/bin/sh
CURRENT=$(getprop ro.hardware.vulkan)

if [ "$CURRENT" = "turnip" ]; then
    resetprop ro.hardware.vulkan adreno
    echo "Adreno (stock) is set as current vulkan driver."
else
    resetprop ro.hardware.vulkan turnip
    echo "Turnip (Vulkan 1.4) is set as current vulkan driver."
fi
sleep 10
