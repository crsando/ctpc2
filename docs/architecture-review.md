# ctpc2 架构评估与改进路线

> 本文记录对 ctpc2 的整体梳理、已发现的问题和改进策略，作为后续重构的依据。
> 已完成的条目以 ✅ 标注。

## 1. 项目定位

ctpc2 是基于上期 CTP 接口、以 LuaJIT 为主力语言的个人期货交易基础设施：
提供行情采集（collector）、交易下单/查询（trader），并在其上以 actor 风格的微服务框架
（外部依赖 `service`，底层队列等原语来自 ltask）构建应用（demo 中为 tifa）。

### 分层

```
demo/services   root / collector / trader / book / gateway / bot   应用层（actor 服务）
templates/      ctp_collector.lua / ctp_trader.lua                 服务模板：查询队列、订单簿、协程挂起/唤醒
lctp2/          init.lua（FFI 绑定）+ parse.lua（解析 CTP 头文件）    Lua 绑定层
src/            libctpc2.so：Spi 回调 → SPSC 队列 → uv_async 唤醒   C/C++ 桥接层
lib/ctp-x.y.z   各版本 CTP / openctp SDK
```

### 数据流

1. CTP 回调线程中，`OnRtnXxx/OnRspXxx` 把结构体 `malloc+memcpy` 一份，推入 SPSC 无锁队列，再 `uv_async_send` 唤醒 Lua 侧 libuv loop。
2. Lua 服务在 `on_idle` 中非阻塞地取空队列，用头文件解析得到的元数据把 cdata 转成 table（`totable`）。
3. 查询：入队 → 1 次/秒 流控 → 按 `req_id` 收集 → `is_last` 时恢复协程。
4. 下单：用 FrontID+SessionID+OrderRef 生成 key，`OnRtnOrder/OnRtnTrade` 更新状态，到终态时恢复协程。

**总体评价**：思路正确。C 层只做搬运、策略放在 Lua；跨线程只用 `uv_async_send`；
用协程把异步查询写成同步风格。主要问题在于层次边界不清、健壮性不足、缺少可测试性。

## 2. 已知缺陷（会实际触发）

| # | 位置 | 问题 | 状态 |
|---|---|---|---|
| 1 | `templates/ctp_trader.lua` `query.reorder` | 循环变量不递增，导致死循环 | ✅ 已修 |
| 2 | `templates/ctp_trader.lua` | `log_deubg` 拼写错误 | ✅ 已修 |
| 3 | `query:request` 超时 | 超时后条目不出队，后续查询全部阻塞；超时回调不取消，可能错误唤醒已完成的协程 | 待修 |
| 4 | `ctp_rsp_free` | 只 `free(r)`，`field` 和 `rsp_info` 泄漏 | 待修 |
| 5 | `OrderRef` 生成 | `OnRtnOrder` 用任意回报（含 RESTART 重放、其他会话）覆盖 `lst_order_ref`；Lua 层在调用后读取该字段，与 SPI 线程竞态 | 待修 |
| 6 | `CustomMdSpi` 断线重连 | 重新登录后不重新订阅，行情悄无声息地停止 | 待修 |
| 7 | `init.lua` `hook` | 调用未实现的 `ctp_md_hook` | ✅ 已删 |
| 8 | 队列满 | `queue_push_ptr` 返回值被忽略，静默丢消息并泄漏内存 | 待修 |
| 9 | `_read_only = config.read_only or true` | 永远为 true，且从未检查，只读保护无效 | 待修 |
| 10 | `gateway.lua` | 监听 `0.0.0.0` 且无鉴权，`debug` 命令可调用任意服务/方法 | 待修 |

其他：`OnRtnTrade` 早于 `OnRtnOrder(AllTraded)` 时订单不结束；`rsp_info.ErrorID == 0`
在 Lua 中也为真值；`OnRspUserPasswordUpdate` 不入队；登录日志打印明文密码。

## 3. 架构改进策略（按收益排序）

### 3.1 C 层 / Lua 层边界
现状：市价单语义、OrderRef、登录链路，以及每个请求一个手写 C 函数（大量无长度检查的 `strcpy`）都在 C 层。

目标：C 层只保留通用请求派发和通用回调打包。
```c
int ctp_trader_req(ctp_trader_t*, int req_type, void* field);  // field 由 Lua ffi.new 构造
```
回调打包代码由脚本根据 `ThostFtdcTraderApi.h` 自动生成，覆盖全部 `OnRsp*/OnRtn*`。
登录状态机、OrderRef 生成、下单策略移到 Lua。

### 3.2 消息与内存所有权
- 每条消息一次 malloc（header + field + rsp_info 连续存放），一次 free 释放。
- md 和 trader 使用统一的消息格式。
- 队列满策略显式化：计数并报警、扩容，或丢弃最旧的 tick；交易回报绝不能丢。
- 已有 `uv_async`，mutex+cond 只为阻塞式 `recv`（测试用）保留。

### 3.3 连接状态机
- `connected` 的 0~4 魔数改为枚举；每次状态迁移都作为消息推给 Lua，失败时带错误码。
- `start(true)` 和 `is_ready` 轮询改为带超时的等待，避免登录失败时永远阻塞。
- 重连：md 自动重订阅；trader 让进行中的查询立即失败，按新的 FrontID/SessionID 重新映射订单 key。

### 3.4 请求管理器（纯 Lua，可单测）
- 用 `req_id → pending` 哈希表管理请求，替换 FIFO + `first()`。
- 流控用令牌桶（查询 1 次/秒，报单单独流控）。
- 超时句柄与请求绑定：完成时取消超时，超时时出队并通知上层。

### 3.5 订单状态机
- OrderRef 只在一处唯一生成，`order_insert` 直接返回；按 FrontID+SessionID 过滤自己的回报。
- 终态判断不依赖回报到达顺序（`OnRtnOrder` 终态和累计成交量，任一满足即结束）。
- 明确 `THOST_TERT_RESTART` 的用途：用来重建订单簿，或者改为 QUICK，避免 cache 无限增长。

### 3.6 风控闸门
在策略与 trader 之间加一层 risk gate：只读开关、单笔最大手数、最大持仓、价格偏离、合约白名单。
gateway 和 bot 都必须经过它。

### 3.7 头文件解析放到构建期
- `make gen` 按 `CTP_VER` 生成 `lctp2/cdefs_<ver>.lua`（cdef 文本、常量、struct 元数据），替代运行时正则解析。
- `totable` 按 struct 生成专用转换函数（或保留 cdata 按需取字段），GBK→UTF-8 在此统一处理。

### 3.8 模板可注入、可测试
- 模板改为工厂函数 `function(service, config, trader_factory) ... return S end`，不在 require 时产生副作用。
- `lctp2/init.lua` 不再定义全局函数。
- 注入 fake trader，离线测试查询队列和订单状态机。

### 3.9 工程
- ✅ 删除 `init.lua` 中写死的账户配置，账户统一从 `~/.tifa/accounts.lua` 读取。
- ✅ Makefile：警告、加固、`DESTDIR`、`$ORIGIN` rpath、只安装公共头文件、安装时生成 `lctp2/config.lua`。
- ✅ 删除死代码（`reg.c`、`uthash.h`、`position.c`、`util.c`、`md->symbols`、未用的 Spi 方法、注释掉的旧实现）。
- ✅ `log_log` 加 `format(printf)` 属性，修复由此暴露的格式化串错误；Spi 类加虚析构函数。
- 日志不打印密码和 AuthCode。
- `lib/` 下多版本 SDK 二进制改用 git LFS 或下载脚本管理。
- 确认 luv 内嵌的 libuv 与系统 libuv 的 ABI 一致，或改为由 Lua 侧注入唤醒函数。

## 4. 推进顺序

1. **立即**：gateway 只监听 `127.0.0.1` 并去掉 `debug` 命令；日志脱敏。
2. **短期**：第 2 节缺陷 3、4、5、6、8、9。
3. **中期**：3.3 ~ 3.6（状态机、请求管理器、订单状态机、风控），同时完成 3.8 并补离线测试。
4. **长期**：3.1、3.7（C 层通用化和代码生成）。

## 5. 构建说明（新 Makefile）

```sh
make                              # 输出 build/<CTP_VER>/libctpc2.so
make CTP_VER=openctp-6.7.10       # 切换 SDK，不存在时报错并列出可用版本
make DEBUG=1                      # -O0 -g3，便于 gdb
make WERROR=1                     # CI 用，警告视为错误
make && sudo make install         # 先以普通用户构建，再以 root 安装
make install DESTDIR=/tmp/stage   # 打包用的分级安装
```

注意：`install` 依赖构建目标。如果直接 `sudo make install`，`build/` 会归 root 所有，
之后普通用户无法再构建。请先 `make`，再 `sudo make install`。
