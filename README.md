# 深职院考勤补签 Windows 客户端

这是把上级目录里的 Node.js 补签脚本整理成的 Flutter Windows 客户端。

## 功能

- 保存教务系统 Cookie、学号、实习计划 WID、地址、备注等配置
- 可启动浏览器登录，并从浏览器会话导入教务系统 Cookie
- 可按 IP 粗略获取地理信息，所有地址字段仍可手动修改
- 可按用户填写的实际到岗时间提交今日签到，使用已保存的签到所在地和详细地址
- 查询指定月份已有签到记录
- 支持选择开始月份到结束月份
- 支持一周 5 天、一周 6 天、全部日期三种默认勾选规则
- 拉取在线节假日数据，默认跳过节假日，但每个日期都可手动勾选或取消
- 列出过去且未签到的日期，支持手动勾选后逐个提交补签
- 提交前有确认弹窗，提交结果会显示在日期列表里
- 支持命令行今日签到：运行 `node auto_checkin.js`，浏览器登录后读取 Cookie、检查条件并在确认后提交今日签到

## 自动签到

`auto_checkin.js` 把“浏览器登录 → 获取 Cookie → 检查签到条件 → 确认提交”合并为一步：

```powershell
node auto_checkin.js
```

流程：
1. 打开浏览器进入统一认证页（与 `capture_auth_cookies.js` 相同）
2. 你手动登录（验证码/滑块/跳转）
3. 回到终端按 Enter
4. 脚本从 `config.json` 读取学号、所在地、地址、实际到岗时间
5. 依次检查：实习计划 → 今日签到记录 → 岗位权限 → 学年状态
6. 通过后显示将提交的信息，输入 `y` 才会提交今日签到
7. 显示成功或失败原因

参数：
- `--time 09:00:00` 指定到岗时间，不传则使用 Flutter 应用中已保存的值
- `--browser chrome` 指定浏览器 channel
- `--checkin-only` 跳过浏览器登录，直接用上次保存的 Cookie 提交（适合 Cookie 未过期时快速签到）
- `--dry-run` 只检查条件并显示将提交的信息，不真正提交
- `--yes` 跳过提交前确认，只适合你已经核对过实际到岗时间和地址的场景

前置条件：
- Flutter 应用中已配置好学号、所在地、详细地址、实际到岗时间
- 实际到岗时间不能晚于当前中国时间
- 当前有实习中的计划
- 今天尚未签到

## 运行

开发运行：

```powershell
flutter run -d windows
```

构建：

```powershell
flutter build windows
```

构建后的程序位于：

```text
build\windows\x64\runner\Release\attendance_client.exe
```

## 发布

推送 `v*` 标签会触发 GitHub Actions 自动构建并创建 Release：

- `attendance_client_windows_<tag>.zip`
- `attendance_client_android_<tag>.apk`

Windows 压缩包内包含 Cookie 捕获脚本、`playwright-core` 依赖和 `node.exe` 运行时；使用者解压后直接运行，不需要额外安装 Node.js。APK 版本不支持自动读取外部浏览器 Cookie，需要手动粘贴。

## 配置说明

- `JW_COOKIE`：从浏览器或现有 `.env` 中复制教务系统 Cookie
- `打开浏览器登录`：启动浏览器进入统一认证并跳转教务页
- `读取 Cookie`：登录完成后导入 `jwxt-443.vpn5.szpu.edu.cn` 域名 Cookie
- `学号`：学生学号，可在 Cookie 有效时从教务页面自动获取
- `实习计划 WID`：当前实习计划的 `JHXSWID`
- `实际到岗时间`：今日签到提交时间，格式为 `HH:mm` 或 `HH:mm:ss`
- `开始月份`、`结束月份`：格式为 `YYYY-MM`
- `默认勾选规则`：一周 5 天、一周 6 天、全部日期
- `签到所在地`、`详细地址`：今日签到和补签都会写入表单，提交前应确认真实准确
- `补签备注`：提交补签时写入表单
- `按 IP 自动填地理信息`：只能作为粗略辅助，提交前应手动核对
- `间隔 ms`：批量提交时每次请求之间的等待时间

配置会保存到当前 Windows 用户目录下的：

```text
%APPDATA%\SzpuAttendanceClient\config.json
```

该文件包含登录态 Cookie，请只在个人电脑使用，不要发给别人。
