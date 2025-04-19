# Include custom packages
include $(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/packages/*/*.mk))

# Add hailort packages to the default build targets
TARGET_PACKAGES += hailort hailort-drivers

# Register the custom packages path while preserving nerves system path
BR2_EXTERNAL := $(NERVES_DEFCONFIG_DIR):$(BR2_EXTERNAL_NERVES_PATH)
