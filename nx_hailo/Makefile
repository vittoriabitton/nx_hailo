# Environment variables passed via elixir_make
# ERTS_INCLUDE_DIR
# MIX_APP_PATH

# Cache configuration
NX_HAILO_CACHE_SO = cache/libnx_hailo.so
NX_HAILO_CACHE_OBJ_DIR = cache/objs

# Private configuration
NX_HAILO_DIR = c_src
PRIV_DIR = $(MIX_APP_PATH)/priv
NX_HAILO_SO = $(PRIV_DIR)/libnx_hailo.so

# HailoRT configuration
HAILO_INCLUDE_DIR = $(NX_HAILO_DIR)/include
HAILO_LIB_DIR ?= /usr/lib

# Build flags
CFLAGS += -I$(FINE_INCLUDE_DIR) -I$(HAILO_INCLUDE_DIR) -fPIC -fvisibility=hidden -I$(ERTS_INCLUDE_DIR) -Wall -std=c++17 -O3
CFLAGS += -Wno-deprecated-declarations

# LDFLAGS must include the sysroot's lib directory for cross-compilation
# HAILORT_LIB_DIR defaulting to the setup in UTM
HAILORT_LIB_DIR ?= ../hailo_rpi5/.nerves/artifacts/hailo_rpi5-portable-0.4.0/target/usr/lib
LDFLAGS = -shared -L$(HAILORT_LIB_DIR) -lhailort

SOURCES = $(NX_HAILO_DIR)/nx_hailo.cpp
OBJECTS = $(patsubst $(NX_HAILO_DIR)/%.cpp,$(NX_HAILO_CACHE_OBJ_DIR)/%.o,$(SOURCES))

$(NX_HAILO_SO): $(NX_HAILO_CACHE_SO)
	@ mkdir -p $(PRIV_DIR)
	@ if [ "${MIX_BUILD_EMBEDDED}" = "true" ]; then \
		cp -a $(abspath $(NX_HAILO_CACHE_SO)) $(NX_HAILO_SO) ; \
	else \
		ln -sf ../$(NX_HAILO_CACHE_SO) $(NX_HAILO_SO) ; \
	fi

$(NX_HAILO_CACHE_OBJ_DIR)/%.o: $(NX_HAILO_DIR)/%.cpp
	@ mkdir -p $(NX_HAILO_CACHE_OBJ_DIR)
	$(CXX) $(CFLAGS) -c $< -o $@

$(NX_HAILO_CACHE_SO): $(OBJECTS)
	$(CXX) $(OBJECTS) -o $(NX_HAILO_CACHE_SO) $(LDFLAGS)

clean:
	rm -rf cache
