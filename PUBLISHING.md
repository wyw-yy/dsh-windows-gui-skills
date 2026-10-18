# 发布手册（GitHub + npm）

插件包本体已经完成并通过本地验证。这份文件只记录「怎么把它发出去」，供下次照做。

## 0. 本地已完成的验证（2026-10-18）

```text
npm pack --dry-run      → 13 个文件，tarball 25 KB，unpacked 67 KB
dsh plugin --profile plugincheck add <tgz>
                        → 安装成功（pnpm 398 ms），并自动登记进 dsh.profile.bundles
dsh --profile plugincheck --dump-config
                        → 出现 windows-gui-skills-filesystem 层，
                          bundledSkillDir 解析到 ...\node_modules\dsh-windows-gui-skills\skills
node 复算 !!js 表达式   → 四个 SKILL.md 全部命中
```

尚未验证的一步：真正起一个会话看四个技能是否出现在技能列表里。需要等 npm 发布后，或本机直接装 tarball 之后做。

## 1. 建 GitHub 仓库

**A. 网页法（不用装东西）**

1. 打开 <https://github.com/new>
2. Repository name 填 `dsh-windows-gui-skills`，可见性选 Public，**不要**勾选 README / .gitignore / license（本地已经有）
3. 建好后把地址填进 `package.json` 的 `repository` / `homepage` / `bugs`（把 `OWNER` 换成你的用户名）
4. 推送：

```bash
cd dsh-windows-gui-skills
git config user.name  "你的名字"
git config user.email "你的邮箱"          # 用 GitHub 账号邮箱或 xxx@users.noreply.github.com
git add -A && git commit -m "feat: initial release"
git branch -M main
git remote add origin https://github.com/OWNER/dsh-windows-gui-skills.git
git push -u origin main
```

**B. gh CLI 法（全自动，需要 `winget install GitHub.cli` 后 `gh auth login`）**

```bash
gh repo create dsh-windows-gui-skills --public --source=. --remote=origin --push
```

## 2. 发布到 npm

插件要靠 `dsh plugin add <包名>` 安装，所以必须进 npm registry（不能只发 GitHub）。

```bash
npm login                      # 浏览器或 OTP 验证
npm whoami                     # 确认登录成功
npm publish --access public    # 非 scoped 包可省略 --access
```

发布前自查：

- `name` 未被占用：`npm view dsh-windows-gui-skills version` 应报 E404（当前确认未占用）
- `version` 必须比上次高（`npm version patch|minor|major`）
- 开了 2FA 的账号需要一次性验证码，或改用 Automation token
- `files` 白名单已限定，`npm pack --dry-run` 只应出现 13 个文件

## 3. 发布后验证

```bash
# 在干净 profile 里装（别拿自己的 desktop profile 试）
dsh plugin --profile plugincheck add dsh-windows-gui-skills
dsh --profile plugincheck --dump-config | Select-String skill-filesystem
```

然后开一个新会话，问一句「你现在有哪些 windows 相关的技能？」，应列出四项。
验证完删掉临时 profile：`Remove-Item -Recurse -Force $env:USERPROFILE\.dsh\profiles\plugincheck`。

## 4. 发版约定

- 版本号跟 `CHANGELOG.md` 同步；技能内容有实质改动就 minor，措辞/错字走 patch
- GitHub Release 里贴 `npm pack --dry-run` 的关键数字和验证记录
- 想进 DSH 插件市场（`dshmarket`）时，market 侧需要 `dsh` 字段 + `cordis.patch.yml`，本包已符合；再按市场仓库的收录说明提交

## 5. 已知坑

| 现象 | 原因 / 处理 |
|---|---|
| `dsh plugin add` 报 pnpm 找不到 | dsh 自带 pnpm，别用系统 npm 装；用 `dsh plugin` 转发 |
| 装完技能列表里没有 | 会话启动时才扫描，必须开新会话 |
| `!!js` 表达式报 `baseUrl` 未定义 | patch 里必须用宿主的 `baseUrl` 变量，不能自己拼路径 |
| 从 git 源直接 `add github:user/repo` | 仓库根不是 DSH 包，会被拒；只能装 npm 包或本地 tarball |
| 包名冲突 | 换 `@你的用户名/dsh-windows-gui-skills`（scoped 需 `--access public`），并同步改 `cordis.patch.yml` 里的包名 |
