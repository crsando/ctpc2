# libctpc2 build / install
#
# Common usage:
#   make                              build with the default CTP version
#   make CTP_VER=openctp-6.7.10       build against another SDK under lib/
#   make DEBUG=1                      -O0, no fortify (for gdb)
#   make WERROR=1                     treat warnings as errors (CI)
#   sudo make install                 install to $(PREFIX)
#   make install DESTDIR=/tmp/stage   staged install (packaging)
#   make help                         list targets and variables

# ---------------------------------------------------------------------------
# Configuration (override on the command line)
# ---------------------------------------------------------------------------
PREFIX    ?= /usr/local
DESTDIR   ?=
CTP_VER   ?= ctp-6.7.10
BUILD_DIR ?= build/$(CTP_VER)
DEBUG     ?= 0
WERROR    ?= 0

# make has built-in defaults for CC/CXX, so `?=` would never apply here;
# only replace them when they come from make itself, not the env/cmdline.
ifeq ($(origin CC),default)
CC := gcc
endif
ifeq ($(origin CXX),default)
CXX := g++
endif

# User-overridable flags; mandatory flags are added separately below so that
# overriding CFLAGS on the command line cannot drop -fPIC or hardening.
CFLAGS   ?= -O2 -g
CXXFLAGS ?= -O2 -g
LDFLAGS  ?=

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
SRC_DIR := src
CTP_DIR := lib/$(CTP_VER)
TARGET  := $(BUILD_DIR)/libctpc2.so

INCLUDE_DIR := $(PREFIX)/include/ctpc2
LIB_DIR     := $(PREFIX)/lib
LUA_DIR     := $(PREFIX)/share/lua/5.1/lctp2

# Only the public API header is installed; queue/cond/log/macros are internal.
PUBLIC_HEADERS := $(SRC_DIR)/ctpc2.h
CTP_HEADERS    := $(CTP_DIR)/ThostFtdcUserApiDataType.h $(CTP_DIR)/ThostFtdcUserApiStruct.h
CTP_LIBS       := $(CTP_DIR)/libthostmduserapi_se.so $(CTP_DIR)/libthosttraderapi_se.so

ifeq ($(wildcard $(CTP_DIR)/ThostFtdcTraderApi.h),)
$(error CTP SDK not found: $(CTP_DIR). Available: $(notdir $(wildcard lib/*)))
endif

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
WARN_FLAGS := -Wall -Wextra -Wformat=2 -Wno-unused-parameter
ifeq ($(WERROR),1)
WARN_FLAGS += -Werror
endif

# Hardening: stack protector, fortified libc calls, full RELRO, non-exec stack.
HARDEN_CPPFLAGS := -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2
HARDEN_FLAGS    := -fstack-protector-strong -fstack-clash-protection
HARDEN_LDFLAGS  := -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack

ifeq ($(DEBUG),1)
CFLAGS          := -O0 -g3
CXXFLAGS        := -O0 -g3
HARDEN_CPPFLAGS :=
endif

ALL_CPPFLAGS := -I$(SRC_DIR) -I$(CTP_DIR) $(HARDEN_CPPFLAGS) $(CPPFLAGS)
ALL_CFLAGS   := -std=gnu11 -fPIC -MMD -MP $(WARN_FLAGS) $(HARDEN_FLAGS) $(CFLAGS)
ALL_CXXFLAGS := -std=gnu++17 -fPIC -MMD -MP $(WARN_FLAGS) $(HARDEN_FLAGS) $(CXXFLAGS)
# $ORIGIN: find the CTP libs next to libctpc2.so wherever it is installed,
# instead of baking an absolute path into the binary.
ALL_LDFLAGS  := -shared -Wl,--as-needed -Wl,-rpath,'$$ORIGIN' $(HARDEN_LDFLAGS) $(LDFLAGS)
LDLIBS       := -L$(CTP_DIR) -lthostmduserapi_se -lthosttraderapi_se -luv -lpthread

# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------
C_SOURCES   := $(wildcard $(SRC_DIR)/*.c)
CXX_SOURCES := $(wildcard $(SRC_DIR)/*.cpp)
OBJECTS     := $(C_SOURCES:$(SRC_DIR)/%.c=$(BUILD_DIR)/%.o) \
               $(CXX_SOURCES:$(SRC_DIR)/%.cpp=$(BUILD_DIR)/%.o)
DEPFILES    := $(OBJECTS:.o=.d)

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
.PHONY: all clean distclean install uninstall help
.DELETE_ON_ERROR:

all: $(TARGET)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(ALL_CPPFLAGS) $(ALL_CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cpp | $(BUILD_DIR)
	$(CXX) $(ALL_CPPFLAGS) $(ALL_CXXFLAGS) -c $< -o $@

$(TARGET): $(OBJECTS)
	$(CXX) $(ALL_CXXFLAGS) $(ALL_LDFLAGS) -o $@ $^ $(LDLIBS)

$(BUILD_DIR):
	@mkdir -p $@

clean:
	$(RM) -r $(BUILD_DIR)

distclean:
	$(RM) -r build

# lctp2/config.lua is generated at install time so the Lua side always finds
# the headers under the same PREFIX the library was installed to.
install: $(TARGET)
	install -d -m 0755 $(DESTDIR)$(INCLUDE_DIR) $(DESTDIR)$(LIB_DIR) $(DESTDIR)$(LUA_DIR)/templates
	install -m 0644 $(CTP_HEADERS) $(PUBLIC_HEADERS) $(DESTDIR)$(INCLUDE_DIR)/
	install -m 0755 $(CTP_LIBS) $(TARGET) $(DESTDIR)$(LIB_DIR)/
	install -m 0644 lctp2/*.lua $(DESTDIR)$(LUA_DIR)/
	install -m 0644 templates/*.lua $(DESTDIR)$(LUA_DIR)/templates/
	printf 'return { prefix = "%s", ctp_version = "%s" }\n' '$(PREFIX)' '$(CTP_VER)' \
		> $(DESTDIR)$(LUA_DIR)/config.lua
	chmod 0644 $(DESTDIR)$(LUA_DIR)/config.lua

uninstall:
	$(RM) $(DESTDIR)$(LIB_DIR)/libctpc2.so
	$(RM) $(DESTDIR)$(LIB_DIR)/libthostmduserapi_se.so
	$(RM) $(DESTDIR)$(LIB_DIR)/libthosttraderapi_se.so
	$(RM) -r $(DESTDIR)$(INCLUDE_DIR)
	$(RM) -r $(DESTDIR)$(LUA_DIR)

help:
	@echo "Targets:   all (default) | clean | distclean | install | uninstall | help"
	@echo "Variables: PREFIX=$(PREFIX) DESTDIR=$(DESTDIR) CTP_VER=$(CTP_VER)"
	@echo "           BUILD_DIR=$(BUILD_DIR) DEBUG=$(DEBUG) WERROR=$(WERROR)"
	@echo "SDKs:      $(notdir $(wildcard lib/*))"

-include $(DEPFILES)
