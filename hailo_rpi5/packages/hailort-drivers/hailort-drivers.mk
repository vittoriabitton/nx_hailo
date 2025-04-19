################################################################################
#
# hailort-drivers
#
################################################################################

HAILORT_DRIVERS_VERSION = v4.20.0
HAILORT_DRIVERS_SITE = https://github.com/hailo-ai/hailort-drivers.git
HAILORT_DRIVERS_SITE_METHOD = git
HAILORT_DRIVERS_GIT_SUBMODULES = YES
HAILORT_DRIVERS_LICENSE = GPL-2.0
HAILORT_DRIVERS_LICENSE_FILES = LICENSE
HAILORT_DRIVERS_DEPENDENCIES = linux hailort

define HAILORT_DRIVERS_BUILD_CMDS
	$(MAKE) $(LINUX_MAKE_FLAGS) -C $(LINUX_DIR) M=$(@D)/linux/pcie modules
endef

define HAILORT_DRIVERS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/linux/pcie/hailo_pci.ko \
		$(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/extra/hailo_pci.ko
endef

$(eval $(kernel-module))