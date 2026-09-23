# Environment variables passed via elixir_make:
#   ERTS_INCLUDE_DIR, MIX_APP_PATH, FINE_INCLUDE_DIR, HAILO_TARGET
#   HAILORT_INCLUDE_DIR, HAILORT_LIB_DIR (optional, for finding HailoRT headers/libs)
#
# HailoRT must be installed. If not in default search paths, set:
#   HAILORT_INCLUDE_DIR = directory containing "hailo/" (e.g. /usr/local/include or <sdk>/include)
#   HAILORT_LIB_DIR     = directory containing libhailort.so (e.g. /usr/local/lib or <sdk>/lib)

HAILO_TARGET ?= hailo10

NX_HAILO_DIR = c_src
PRIV_DIR = $(MIX_APP_PATH)/priv
NIF_SO_NAME = libnx_hailo.so

# The Hailo-8 family speaks the VDevice/InferVStreams API of the hailort
# "hailo8" branch; Hailo-10 and Hailo-15 speak the InferModel API of HailoRT v5.
# Anything else is a typo, and silently building the wrong backend produces a
# NIF that loads and then fails at inference time.
HAILO8_TARGETS = hailo8 hailo8l hailo8r
HAILO10_TARGETS = hailo10 hailo10h hailo15 hailo15h hailo15l

ifneq (,$(filter $(HAILO_TARGET),$(HAILO8_TARGETS)))
  NIF_SOURCE = $(NX_HAILO_DIR)/hailo8.cpp
else ifneq (,$(filter $(HAILO_TARGET),$(HAILO10_TARGETS)))
  NIF_SOURCE = $(NX_HAILO_DIR)/hailo10.cpp
else
  $(error Unknown HAILO_TARGET "$(HAILO_TARGET)". Expected one of: $(HAILO8_TARGETS) $(HAILO10_TARGETS))
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
		ln -sf $(abspath $(NX_HAILO_CACHE_SO)) $(PRIV_DIR)/$(NIF_SO_NAME) ; \
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
