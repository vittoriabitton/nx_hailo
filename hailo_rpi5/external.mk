include $(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/packages/*/*.mk))

# Add hailort packages to the default build targets
LINUX_DEPENDENCIES += hailort hailort-drivers
TARGET_PACKAGES += hailort hailort-drivers
