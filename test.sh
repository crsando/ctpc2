echo '' > error.log
luajit demo_test_trader.lua 2> >(iconv -f gbk -t utf-8 | tee error.log >&2)