define Device/focalcrest_gearhub
  $(call Device/FitImageGzip)
  DEVICE_VENDOR := FocalCrest
  DEVICE_MODEL := GearHub H3 (Hornbach Smart Home Gateway V2)
  DEVICE_PACKAGES := kmod-brcmfmac cypress-firmware-43430-sdio \
    wpad-basic-mbedtls kmod-gpio-button-hotplug kmod-rtc-sunxi kmod-leds-gpio \
    ser2net
  SOC := sun8i-h3
endef
TARGET_DEVICES += focalcrest_gearhub
