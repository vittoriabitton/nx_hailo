include $(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/packages/*/*.mk))

# Add hailort packages to the default build targets
TARGET_PACKAGES += hailort hailort-drivers
