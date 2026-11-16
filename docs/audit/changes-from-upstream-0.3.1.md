---
日期：2026-11-16
类型：记录
状态：现行（随每次改动追加）
关联：
  - 工作/审计标记.tsv（机器可读的标记表，44 项）
  - 记录/审计-0.3.1移植清单-20261115.md（上一轮移植审计）
  - 记录/流程-上游更新移植清单.md（同步上游的操作流程）
---

# 相对上游 0.3.1 的全部改动

本机基线：`构建/skyward-0.3.1`（上游 kirklin/skyward v0.3.1 + 下列改动）。
发布仓库：`mariusarva/skyward-pudding`，当前 Latest `v0.3.7`。

---

## 0. 同步上游时先看这一节

改动分三类，**冲突风险完全不同**：

| 类型 | 数量 | 拿到新版上游时的处理 |
|---|---|---|
| **A. 早期版本已实现**（我们自己在 0.2.0 那版做的，官方 0.2.0 也没有） | 24 项 | 这些官方从来没有，直接 graft 到新树，冲突风险低 |
| **B. 本次新增**（本轮会话做的） | 19 项 | 直接 graft 过去，冲突少 |
| **C. 修改上游已有行为** | **3 项** | **必查**。上游一旦改同一函数就要手工合并 |

**C 类的三项（最容易出问题）**：

1. **U 盘挂载从 `ro` 改 `rw`** — `crates/skyward-block/src/usb.rs` 的 `mount()`
   上游若也改成 rw，删掉我们的改动即可；若上游仍是 ro，必须保留。
2. **记住密码默认关闭** — `crates/skyward/src/ui.rs` 里 `app.state.remember` 的初值
   上游是 `remembered.is_some() || !OPTED_OUT.exists()`（默认开），我们改成 `remembered.is_some()`（默认关）。
3. **文件操作后按当前页刷新** — `crates/skyward/src/ui.rs` 的 `files_told()`
   上游固定重读 `state.files.path`，我们改成按 `screen()` 分派。

**基线事实**（2026-11-16 下载官方 tarball 核实）：

官方 `v0.2.0` 与 `v0.3.1` 里都**没有** `paint_shade`（下拉控制中心）、`remember.rs`（记住密码）、
`fileserve.rs`（无线传输）、`portal.rs`（二维码）、`avatar.rs`（账户行）。这些全部是本 fork 自己开发的，
不存在「上游本来有、我们搬回」的情况。

**验证命令**（改完后跑一遍，快速看哪项丢了）：

```sh
sh 工作/审计移植.sh 构建/skyward-0.3.1 临时/up/src<新tag>
```

---

## 1. 解密与记住密码

### 1.1 解密页显示记住状态（B 类，新增）
- 输密码后出现状态胶囊：`已记住密码` / `未记住密码`，右侧带开关
- 位置：密码点下方、底板居中的小胶囊（不是整行卡片）
- 涉及：`crates/skyward-ui/src/pages.rs::code()`
- 标记：`asking_remember`、`已记住密码`、`未记住密码`

### 1.2 风险悬浮窗（B 类，新增）
- 开启「记住」时弹出模态卡片，背景变暗、卡片居中、滑动确认
- 复用项目自带的 `widgets::confirm_card`（与删除确认同一套视觉）
- 文案：说清密码存在本机、拿走手机的人能直接读 data、丢失/被盗/送修时的风险
- 每次重新开启都弹，不记忆「已提示过」
- 涉及：
  - `crates/skyward-ui/src/app/draw.rs::compose_remember_risk()`（新增）
  - `crates/skyward-ui/src/app/draw.rs::compose()`（调用点）
  - `crates/skyward-ui/src/app/input.rs`（`asking_remember` 也吃手指；点卡片外取消）
  - `crates/skyward-ui/src/app/act.rs::confirmed()`（`Confirm::KeepLock` 落地）
- 标记：`compose_remember_risk`、`Confirm::KeepLock`

### 1.3 默认不记住（C 类，改了上游行为）
```rust
// 上游
app.state.remember = remembered.is_some() || !Path::new(crate::remember::OPTED_OUT).exists();
// 我们
app.state.remember = remembered.is_some();
```
- 涉及：`crates/skyward/src/ui.rs`（Pages::open 附近）
- 标记：`remembered.is_some()`

### 1.4 跳过解密动画（B 类，新增）
- 未记住密码时，`Data::Closed | Data::Opening` 直接渲染输密码页（键盘暂不可点），不显示转圈
- 副作用：无锁机的机器会闪一下输密码页再进首页
- 涉及：`crates/skyward-ui/src/pages.rs::decrypt()`
- 标记：`Data::Closed | Data::Opening if`

### 1.5 解密完必进首页（B 类，改了上游行为但是增强）
- 上游 `decrypted()` 只在「当前正好在解密页」时跳
- 改为：data 一旦 Open，清空页面栈回首页
- 涉及：`crates/skyward-ui/src/app/decrypt.rs::decrypted()`
- 标记：`fn decrypted`

### 1.6 设置页移除记住密码入口（B 类）
- 删掉「取消记住密码」行、`Action::ForgetLock`、以及随之变空的「解密」分组
- 涉及：`crates/skyward-ui/src/pages.rs`（settings）、`crates/skyward-ui/src/app/act.rs`、`app/mod.rs`

---

## 2. U 盘文件管理（全新）

### 2.1 U 盘浏览页（B 类，新增）
- 新页面 `Screen::FilesOtg`，列出 U 盘全部文件（不过滤可安装项）
- 涉及：
  - `crates/skyward-ui/src/app/mod.rs`（Screen / Action / Effect 枚举）
  - `crates/skyward-ui/src/app/state.rs`（`otg: Folder` 字段 + `folder()/folder_mut()` 映射）
  - `crates/skyward-ui/src/app/manager.rs`（`set_otg()`）
  - `crates/skyward-ui/src/pages.rs`（`files_otg()` + `Screen::FilesOtg => files_otg(cx)`）
  - `crates/skyward/src/ui.rs`（`list_otg()` + `Effect::ReadOtg` 处理）
- 标记：`FilesOtg`、`ReadOtg`、`set_otg`

### 2.2 顶部位置切换（B 类，新增）
- 文件管理页顶部条：左边面包屑、右端一个位置胶囊（「U 盘」/「内部存储」），点了切换
- 涉及：`crates/skyward-ui/src/files.rs::strip_with()`（新增 `other` 参数）、`pages.rs::listing()`（新增 `places_other` 参数）
- 标记：`places_other`

### 2.3 面包屑省略（B 类，新增）
- 层级过深时中间收成「…」，保留首尾；「…」不可点
- 上游行为是向左溢出（`x` 变负数），我们改成省略
- 涉及：`crates/skyward-ui/src/files.rs::strip_with()`
- 标记：`elided`
- **注意**：测试 `files::tests::the_path_goes_up_by_its_capsules_and_shows_its_end_when_long` 的断言已按新行为改（不再断言 `x < 0`）

### 2.4 高级页入口（B 类，新增）
- 「U 盘管理」一行，`Action::FilesOtg`

### 2.5 互传（B 类，新增）
- 长按菜单按条目所在侧自动切换：
  - 手机上的文件 → `复制到 U 盘…` / `剪切到 U 盘…`
  - U 盘上的文件 → `复制到手机…` / `剪切到手机…`
- 两步式：设剪贴板 → 跳到目标页 → 浏览到目录 → 底部「复制到此处」落地
- 涉及：
  - `crates/skyward-ui/src/app/mod.rs`（`Action::ToDrive(FileOp)` / `ToPhone(FileOp)`）
  - `crates/skyward-ui/src/app/act.rs`（处理，含未插盘提示、自身嵌套、已在该处判断）
  - `crates/skyward-ui/src/pages.rs::file_info`（菜单两行，按 `s.file_on_drive` 分支）
  - `crates/skyward-ui/src/app/state.rs::folder_here()`（跨位置绝对路径换算）
  - `crates/skyward-ui/src/app/entry.rs::entry_path()`（按 `file_on_drive` 算源路径）
- 标记：`ToDrive`、`ToPhone`、`fn folder_here`、`file_on_drive`

### 2.6 U 盘读写挂载（C 类，改了上游行为）
```rust
// 上游
["ro", "nosuid", "nodev", "noexec", own]
// 我们
["rw", "nosuid", "nodev", own]
```
- 原因：只读挂载导致往 U 盘复制必然 `Read-only file system`
- 涉及：`crates/skyward-block/src/usb.rs::mount()`
- 标记：`"rw", "nosuid"`

### 2.7 挂载前清理遗留（B 类，新增）
- 每次挂载前先 `umount_detach`，避免上个进程崩溃后留下的挂载导致挂错分区
- 涉及：`crates/skyward/src/ui.rs::look_for_drive()`
- 标记：`umount_detach`

---

## 3. 文件管理修复

### 3.1 操作后按当前页刷新（C 类，改了上游行为）
```rust
// 上游：固定重读内置存储
let folder = self.app.state.files.path.clone();
list(&mut self.app, folder)?;
// 我们：按当前页面分派
match self.app.screen() {
    Screen::FilesOtg => list_otg(...),
    Screen::Choose(place) => list_place(...),
    _ => list(...),
}
```
- 涉及：`crates/skyward/src/ui.rs::files_told()`
- 标记：`fn files_told`

### 3.2 进入 U 盘页崩溃（B 类，修复）
- 症状：`panicked at pages.rs: internal error: entered unreachable code: FilesOtg draws no list row by row`
- 原因：`pages::row()`（长列表逐行绘制）的 match 未识别新页面
- 修法：`Screen::Files | Screen::FilesOtg | Screen::Choose(_)`
- **同步上游时**：凡是 `match screen` 穷举 `Screen::Files` 的地方，新页面都要一并加进去。已知三处：`pages::row()`、`nav.rs` 的返回键、`nav.rs` 的回到页面重读

---

## 4. 诊断

### 4.1 panic 写内核日志（B 类，新增）
- 崩溃时把位置写进 kmsg，重启后仍可查
```rust
std::panic::set_hook(Box::new(|info| {
    let _ = skyward_sys::kmsg(&format!("the recovery ended on a panic at {at}: {info}"));
}));
```
- 涉及：`crates/skyward/src/main.rs::main()`
- 标记：`the recovery ended on a panic`
- 用法：`grep -a "ended on a panic" /storage/emulated/0/Skyward/logs/*/recovery.log`

### 4.2 文件操作日志（B 类，新增）
- 粘贴时记 `files: {op} {源} into {目标}`
- 涉及：`crates/skyward/src/ui.rs::paste()`

---

## 5. 更新页

### 5.1 显示精简更新日志（B 类，新增）
- 解析 GitHub release 的 `body`
- 优先取第一个 `##` 之前的要点；没有则取全文要点
- 每条上限 64 字、最多 4 条；去掉 `**`、`` ` ``、`#`，链接只留文字
- 跳过 `**加粗标题**`（`*` 不算列表标记）
- 涉及：
  - `crates/skyward-net/src/github.rs`（`Release.body`、`Newest.notes`、`brief()`、`points()`、`plain_words()`）
  - `crates/skyward-ui/src/pages.rs::skyward_update`（「本次更新」区块）
- 标记：`fn brief`、`本次更新`
- **发布约定**：release body 开头放 4 条以内的一句话摘要，`##` 之后写详细内容

---

## 6. 已验证但需要在线数据的点

| 项 | 依赖 |
|---|---|
| 检查更新 → 下载 → 写分区 | GitHub release 资产、`docs/update.json` |
| 更新页显示日志 | release body 开头有要点 |
| U 盘互传 | 真机插 U 盘 |

**内测包版本号约定**：内部测试用 `0.001`、`0.002`…（低于线上 `v0.3.NN`），这样进恢复点「检查更新」每回都显示可更新，等于一块常备试纸。

---

## 7. 已知遗留

- U 盘多分区时只挂最大的那个，其余分区没有单独入口
- 记住的密码在改密码/换锁屏方式后失效并自动清除（设计如此，写日志可查）
- 更新日志目前只显示 4 条，不做展开；长内容需去网页看
- 浏览器功能曾移植过一版（`构建/skyward-0.3.1-with-browser` 是当时备份），因不跑 JS、完整模式需 548MB 外置 Chromium，实用性不足，已完整撤销。**该备份可删**
