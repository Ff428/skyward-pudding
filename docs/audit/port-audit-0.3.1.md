# 0.3.1 移植审计（2026-11-15）

## 一、结论

用 `工作/审计移植.sh 构建/skyward-0.2.0 构建/skyward-0.3.1` 跑出来的结果：

```
有 18 · 需人工核 0 · 缺 2
```

缺的两项：`crates/skyward/src/aod.rs`（息屏显示）、`crates/skyward/src/touchprobe.rs`（驱动层双击/调试探针）。
其余 0.2.x 上验证过的改动都在 0.3.1 树里，位置与做法见 `工作/审计标记.tsv`。

## 二、本轮审计新查出的一个真 bug（OTG）

0.3.1 的 `usb_link()` 把「端口控制器不在」当成错误：

```rust
let controller = prop("sys.usb.controller").context(...)?;
fs::read_to_string("/sys/class/udc/<controller>/state")?   // OTG 插上时这里必失败
```

而双角色端口接 OTG 外设时，gadget 会被注销、`/sys/class/udc/<controller>` 消失——这是 0.2.x 专门处理过的
（`skyward_sys::usb::gadget_state`，注释写着「那一刻不是恢复失败，也不是接上了 adb」）。0.3.1 删了它，
于是插 U 盘时 `usb_link()` 返回 Err，而 `may_sleep()` 里就是 `usb_link()?`，错误会一路冒到主循环。

已修（0.0.53）：把 `gadget_state` 搬回 `skyward-sys`（ENOENT/ENODEV/ENXIO 读作 None），`usb_link()` 把
「控制器没有」「读不到」都当成未连接。

## 三、审计表（脚本判定的 20 项）

| 项 | 判定 |
|---|---|
| 明文 data 兜底（`keydirectory`） | 有 |
| `dm::status` 后 remove / `unmap` 幂等 / 无 `/data/unencrypted` 放行 | 有 |
| 跳过 HyperOS 第二空间 999 | 有 |
| `weaver_first` 与回退分支 | 有 |
| 记住密码 / 记住 WLAN / 记住排序 | 有 |
| 排序 UI（`SortKey`） | 有 |
| 无线传输（`fileserve`）/ 网络下载（`fetch`）/ 二维码（`portal`） | 有 |
| AVB 页（`avbctl::turn` 等库接口） | 有 |
| 界面优先 + 分段计时 | 有 |
| 密钥程序按接口名剔除 | 有 |
| 更新镜像表（`MIRRORS`） | 有 |
| OTG 端口无控制器 | 有（本轮补回） |
| 息屏显示 aod | **缺** |
| 双击驱动探测 touchprobe | **缺**（现用软件双击 + 面板不歇替代） |

## 四、下次上游更新怎么快

根本办法：**我们改过的每一处都要留下可 grep 的标记**，上游一更新，用脚本一次性列出「还在 / 被改 / 没了」，
只处理后两类。当前标记表 20 项，见 `工作/审计标记.tsv`；加新功能时同步加一行。

1. `工作/更新上游.sh <tag>` 拉新树到 `临时/up/src<tag>`，**不要**直接改在能出包的那套上
2. `sh 工作/审计移植.sh 构建/skyward-0.2.0 临时/up/src<tag>` —— 一条命令得到三列：有 / 需人工核 / 缺
3. 需人工核的项，按标记定位到上游新文件，判断是「换位置」还是「被上游删掉」
4. 本地先跑 `cargo build -p skyward-preview`（host）验证 UI 能编译，并出预览图，**不刷机**
5. 预检密钥链：离线读安装系统各分区的 `.rc`/`build.prop`，列出会启动的程序；按接口名剔除
   `android.hardware.secure_element.*` 与 `android.hardware.weaver.*`（本机跑不了）
6. 打包验证：一次刷机验 3～5 项，其余靠 persist 日志的阶段计时与 `was ready in` 定位

## 五、仍然无法自动的部分（老实说）

- `skyward-ui/src/app.rs`（0.2.x）→ 0.3.1 拆成了 25 个模块，行级 diff 没有意义；只能按功能标记核
- 备份/安装/双系统这类纯逻辑改动，标记只能覆盖到「关键函数名」级别，语义要靠人看
- 息屏显示 aod 要跟 `mi_disp` 的 doze 命令打交道，属设备特定交互，移植成本高于收益；真要做得单独一轮
