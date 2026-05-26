# 深职院考勤补签 Windows 客户端

这是把上级目录里的 Node.js 补签脚本整理成的 Flutter Windows 客户端。

## 功能

- 保存教务系统 Cookie、学号、实习计划 WID、地址、备注等配置
- 可启动浏览器登录，并从浏览器会话导入教务系统 Cookie
- 可按 IP 粗略获取地理信息，所有地址字段仍可手动修改
- 查询指定月份已有签到记录
- 支持选择开始月份到结束月份
- 支持一周 5 天、一周 6 天、全部日期三种默认勾选规则
- 拉取在线节假日数据，默认跳过节假日，但每个日期都可手动勾选或取消
- 列出过去且未签到的日期，支持手动勾选后逐个提交补签
- 提交前有确认弹窗，提交结果会显示在日期列表里

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

Windows 压缩包内包含 Cookie 捕获脚本和 `playwright-core` 依赖；APK 版本不支持自动读取外部浏览器 Cookie，需要手动粘贴。

## 配置说明

- `JW_COOKIE`：从浏览器或现有 `.env` 中复制教务系统 Cookie
- `打开浏览器登录`：启动浏览器进入统一认证并跳转教务页
- `读取 Cookie`：登录完成后导入 `jwxt-443.vpn5.szpu.edu.cn` 域名 Cookie
- `学号`：学生学号
- `实习计划 WID`：当前实习计划的 `JHXSWID`
- `开始月份`、`结束月份`：格式为 `YYYY-MM`
- `默认勾选规则`：一周 5 天、一周 6 天、全部日期
- `签到所在地`、`详细地址`、`补签备注`：提交补签时写入表单
- `按 IP 自动填地理信息`：只能作为粗略辅助，提交前应手动核对
- `间隔 ms`：批量提交时每次请求之间的等待时间

配置会保存到当前 Windows 用户目录下的：

```text
%APPDATA%\SzpuAttendanceClient\config.json
```

该文件包含登录态 Cookie，请只在个人电脑使用，不要发给别人。
