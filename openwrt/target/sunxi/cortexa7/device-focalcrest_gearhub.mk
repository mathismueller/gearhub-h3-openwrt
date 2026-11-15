define Device/focalcrest_gearhub
  DEVICE_VENDOR := FocalCrest
  DEVICE_MODEL := GearHub H3 (Hornbach Smart Home Gateway V2)
  DEVICE_PACKAGES := kmod-brcmfmac cypress-firmware-43430-sdio \
    wpad-basic-mbedtls kmod-gpio-button-hotplug kmod-rtc-sunxi \
    kmod-rtc-pcf8563 kmod-spi-dev uboot-envtools gpiod-tools ser2net
  SOC := sun8i-h3
endef
TARGET_DEVICES += focalcrest_gearhub
