include $(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/packages/*/*.mk))

# Ensure hailort is built
NERVES_SYSTEM_DEPS += hailort
NERVES_SYSTEM_DEPS += hailort-drivers
