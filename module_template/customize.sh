ui_print "Installing Turnip Vulkan driver..."
set_perm_recursive $MODPATH/system 0 0 0755 0644
set_perm $MODPATH/system/vendor/lib64/hw/vulkan.turnip.so 0 0 0644
ui_print "Default driver: Turnip (Vulkan 1.4)"
ui_print "Use the Magisk action button to toggle: Turnip / Adreno"
