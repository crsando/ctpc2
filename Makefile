PREFIX=/usr/local
#CTP_VER=ctp-6.6.9
CTP_VER=ctp-6.7.7-20240524
# CTP_VER=openctp-6.6.9

INCLUDE_PATH=$(PREFIX)/include/ctpc2
INST_LIB_PATH=$(PREFIX)/lib
LUA_SHARE=$(PREFIX)/share/lua/5.1

all: libctpc2.so
	@echo --- make all

ctpc2.o: ./src/ctpc2.cpp
	g++ -c -fPIC ./src/ctpc2.cpp -I./$(CTP_VER) 
md.o: ./src/md.c
	gcc -c -fPIC ./src/md.c -lpthread -I./$(CTP_VER)
trader.o: ./src/trader.c
	gcc -c -fPIC ./src/trader.c -lpthread -I./$(CTP_VER)
CustomTradeSpi.o: ./src/CustomTradeSpi.cpp
	g++ -c -fPIC ./src/CustomTradeSpi.cpp -I./$(CTP_VER)
CustomMdSpi.o: ./src/CustomMdSpi.cpp
	g++ -c -fPIC ./src/CustomMdSpi.cpp -I./$(CTP_VER)
queue.o: ./src/queue.c
	gcc -c -fPIC ./src/queue.c -lpthread
reg.o: ./src/reg.c
	gcc -c -fPIC ./src/reg.c
log.o: ./src/log.c
	gcc -c -fPIC ./src/log.c
util.o: ./src/util.c
	gcc -c -fPIC ./src/util.c
position.o: ./src/position.c
	gcc -c -fPIC ./src/position.c -I./$(CTP_VER)

libctpc2.so: ctpc2.o md.o trader.o queue.o log.o CustomMdSpi.o CustomTradeSpi.o reg.o position.o util.o
	gcc ctpc2.o md.o trader.o queue.o log.o CustomTradeSpi.o CustomMdSpi.o reg.o position.o util.o \
		-shared -o libctpc2.so \
		-Wl,-rpath,$(INST_LIB_PATH) \
		-I./$(CTP_VER) -L./$(CTP_VER) -lthostmduserapi_se -lthosttraderapi_se

test: test.c
	gcc test.c \
		-I./$(CTP_VER) \
		-lctpc2 \
		-o test

clean:
	rm *.o

uninstall:
	rm $(INST_LIB_PATH)/libthostmduserapi_se.so
	rm $(INST_LIB_PATH)/libthosttraderapi_se.so
	rm $(INST_LIB_PATH)/libctpc2.so
	rm -r $(LUA_SHARE)/lctp2

install:
	mkdir -p $(INCLUDE_PATH)
	mkdir -p $(LUA_SHARE)/lctp2
	cp ./$(CTP_VER)/*.h $(INCLUDE_PATH)
	cp ./src/*.h $(INCLUDE_PATH)
	cp ./$(CTP_VER)/libthostmduserapi_se.so $(INST_LIB_PATH)
	cp ./$(CTP_VER)/libthosttraderapi_se.so $(INST_LIB_PATH)
	cp ./libctpc2.so $(INST_LIB_PATH)
	cp ./lctp2/*.lua $(LUA_SHARE)/lctp2/

REMOTE=root@47.101.204.234:

.PHONY: publish
publish:
	scp ./src/*.h $(REMOTE)$(INCLUDE_PATH)
	scp ./$(CTP_VER)/libthostmduserapi_se.so $(REMOTE)$(INST_LIB_PATH)
	scp ./$(CTP_VER)/libthosttraderapi_se.so $(REMOTE)$(INST_LIB_PATH)
	scp libctpc2.so $(REMOTE)$(INST_LIB_PATH)
	scp lctp2.lua $(REMOTE)/usr/local/share/lua/5.1/