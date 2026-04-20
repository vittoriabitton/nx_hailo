# Environment variables passed via elixir_make:
#   ERTS_INCLUDE_DIR, MIX_APP_PATH, FINE_INCLUDE_DIR, HAILO_TARGET
#   HAILORT_INCLUDE_DIR, HAILORT_LIB_DIR (optional, for finding HailoRT headers/libs)
# HAILO_TARGET = hailo10 (default) or hailo8
#   hailo10 -> c_src/nx_hailo_v5.cpp    (HailoRT v5 / InferModel)
#   hailo8  -> c_src/nx_hailo_hailo8.cpp (HailoRT hailo8 branch / VDevice)
#
# HailoRT must be installed. If not in default search paths, set:
#   HAILORT_INCLUDE_DIR = directory containing "hailo/" (e.g. /usr/local/include or <sdk>/include)
#   HAILORT_LIB_DIR     = directory containing libhailort.so (e.g. /usr/local/lib or <sdk>/lib)

HAILO_TARGET ?= hailo10

NX_HAILO_DIR = c_src
PRIV_DIR = $(MIX_APP_PATH)/priv
NIF_SO_NAME = libnx_hailo.so

ifeq ($(HAILO_TARGET),hailo8)
  NIF_SOURCE = $(NX_HAILO_DIR)/nx_hailo_hailo8.cpp
else
  NIF_SOURCE = $(NX_HAILO_DIR)/nx_hailo_v5.cpp
endif

HAILORT_LDFLAGS = -lhailort

NX_HAILO_CACHE_OBJ_DIR = cache/$(HAILO_TARGET)/objs
NX_HAILO_CACHE_SO = cache/$(HAILO_TARGET)/$(NIF_SO_NAME)
OBJECT = $(NX_HAILO_CACHE_OBJ_DIR)/$(basename $(notdir $(NIF_SOURCE))).o

# Build flags
CFLAGS += -fPIC -I$(FINE_INCLUDE_DIR) -fvisibility=hidden -I$(ERTS_INCLUDE_DIR) -Wall -std=c++17
CFLAGS += -Wno-deprecated-declarations

ifdef HAILORT_INCLUDE_DIR
CFLAGS += -I$(HAILORT_INCLUDE_DIR)
endif

ifdef HAILORT_LIB_DIR
LDFLAGS += -L$(HAILORT_LIB_DIR)
endif

ifdef DEBUG
CFLAGS += -g
else
CFLAGS += -O3
endif

LDFLAGS += -fPIC -shared $(HAILORT_LDFLAGS)

.PHONY: all clean

all: $(PRIV_DIR)/$(NIF_SO_NAME)
	@echo "NxHailo NIF ready: $(NIF_SO_NAME) ($(HAILO_TARGET))"

$(PRIV_DIR)/$(NIF_SO_NAME): $(NX_HAILO_CACHE_SO)
	@ mkdir -p $(PRIV_DIR)
	@ if [ "${MIX_BUILD_EMBEDDED}" = "true" ]; then \
		cp -a $(abspath $(NX_HAILO_CACHE_SO)) $(PRIV_DIR)/$(NIF_SO_NAME) ; \
	else \
		ln -sf ../$(NX_HAILO_CACHE_SO) $(PRIV_DIR)/$(NIF_SO_NAME) ; \
	fi

$(NX_HAILO_CACHE_SO): $(OBJECT)
	@ mkdir -p $(dir $(NX_HAILO_CACHE_SO))
	$(CXX) $(OBJECT) -o $(NX_HAILO_CACHE_SO) $(LDFLAGS)

$(OBJECT): $(NIF_SOURCE)
	@ mkdir -p $(NX_HAILO_CACHE_OBJ_DIR)
	$(CXX) $(CFLAGS) -c $(NIF_SOURCE) -o $(OBJECT)

clean:
	rm -rf cache
	rm -f $(PRIV_DIR)/libnx_hailo.so
