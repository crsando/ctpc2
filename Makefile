# Build and installation configuration. Override these values on the command line.
PREFIX ?= /usr/local
CTP_VER ?= ctp-6.7.10
BUILD_DIR ?= build/$(CTP_VER)

SRC_DIR := src
CTP_DIR := lib/$(CTP_VER)
TARGET := libctpc2.so

INCLUDE_PATH := $(PREFIX)/include/ctpc2
INST_LIB_PATH := $(PREFIX)/lib
LUA_SHARE := $(PREFIX)/share/lua/5.1

CC := gcc
CXX := g++
CPPFLAGS := -I$(SRC_DIR) -I$(CTP_DIR)
CFLAGS := -fPIC -MMD -MP
CXXFLAGS := -fPIC -MMD -MP
LDFLAGS := -shared -Wl,-rpath,$(INST_LIB_PATH)
LDLIBS := -L$(CTP_DIR) -lthostmduserapi_se -lthosttraderapi_se -luv -lpthread

C_SOURCES := $(wildcard $(SRC_DIR)/*.c)
CXX_SOURCES := $(wildcard $(SRC_DIR)/*.cpp)
C_OBJECTS := $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(C_SOURCES))
CXX_OBJECTS := $(patsubst $(SRC_DIR)/%.cpp,$(BUILD_DIR)/%.o,$(CXX_SOURCES))
OBJECTS := $(C_OBJECTS) $(CXX_OBJECTS)
DEPFILES := $(OBJECTS:.o=.d)

.PHONY: all clean install uninstall

all: $(TARGET)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cpp
	@mkdir -p $(@D)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

$(TARGET): $(OBJECTS)
	$(CXX) $(LDFLAGS) -o $@ $^ $(LDLIBS)

clean:
	$(RM) $(OBJECTS) $(DEPFILES) $(TARGET)

install: all
	install -d $(INCLUDE_PATH) $(INST_LIB_PATH) $(LUA_SHARE)/lctp2/templates
	install -m 0644 $(CTP_DIR)/*.h $(INCLUDE_PATH)/
	install -m 0644 $(SRC_DIR)/*.h $(INCLUDE_PATH)/
	install -m 0755 $(CTP_DIR)/libthostmduserapi_se.so $(INST_LIB_PATH)/
	install -m 0755 $(CTP_DIR)/libthosttraderapi_se.so $(INST_LIB_PATH)/
	install -m 0755 $(TARGET) $(INST_LIB_PATH)/
	install -m 0644 lctp2/*.lua $(LUA_SHARE)/lctp2/
	install -m 0644 templates/*.lua $(LUA_SHARE)/lctp2/templates/

uninstall:
	$(RM) $(INST_LIB_PATH)/libthostmduserapi_se.so
	$(RM) $(INST_LIB_PATH)/libthosttraderapi_se.so
	$(RM) $(INST_LIB_PATH)/libctpc2.so
	rm -rf $(LUA_SHARE)/lctp2

-include $(DEPFILES)
