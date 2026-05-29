# 小店扫码查价 - 技术实现文档

## 一、项目概述

**应用名称**：小店扫码查价  
**目标用户**：小卖部、便利店、杂货店店主  
**核心功能**：离线扫码查价、商品录入、条码自动识别  
**技术栈**：Flutter 3.24.0 + Dart + SQLite (sqflite)

---

## 二、技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                      表现层 (UI Layer)                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  HomePage   │  │ ScanPrice   │  │   GoodsListPage     │ │
│  │  (首页入口)  │  │  (扫码查价)  │  │   (商品管理列表)     │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                    │            │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────────▼──────────┐ │
│  │ AddGoodsPage│  │  ScanPage   │  │   AddGoodsPage      │ │
│  │ (录入/编辑)  │  │  (扫码器)    │  │   (编辑已有商品)     │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                      业务逻辑层 (Service Layer)              │
│  ┌─────────────────┐  ┌─────────────────────────────────┐  │
│  │  DBHelper       │  │      BarcodeService             │  │
│  │  (SQLite 操作)   │  │  (条码查询: 百川API + 比特福API) │  │
│  └─────────────────┘  └─────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                      数据层 (Data Layer)                     │
│  ┌─────────────────┐  ┌─────────────────────────────────┐  │
│  │   Goods Model   │  │   store_price.db (SQLite)        │  │
│  │   (数据模型)     │  │   存储路径: /data/data/...      │  │
│  └─────────────────┘  └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 依赖包说明

| 包名 | 版本 | 用途 |
|------|------|------|
| `sqflite` | ^2.3.2 | SQLite 本地数据库 |
| `path_provider` | ^2.1.2 | 获取应用文件路径 |
| `path` | ^1.9.0 | 路径拼接 |
| `mobile_scanner` | ^5.0.0 | 摄像头扫码 (支持 EAN-13/8, CODE-128) |
| `http` | ^1.2.1 | 网络请求查询条码信息 |
| `image_picker` | ^1.0.7 | 从相册选择商品图片 |
| `share_plus` | ^8.0.2 | 分享功能（预留） |
| `cached_network_image` | ^3.3.1 | 网络图片缓存 |
| `intl` | ^0.19.0 | 国际化/格式化 |
| `permission_handler` | ^11.3.0 | 权限申请 |

---

## 三、数据库设计详解

### 3.1 数据存储位置

**存储路径**：`/data/data/<package_name>/databases/store_price.db`

这是一条 **SQLite 数据库文件**，完全保存在手机本地存储中：
- ✅ 不需要网络，离线可用
- ✅ 数据隐私，不上传任何云端
- ❌ **每个手机的数据相互独立，无法自动共享**
- ❌ 卸载 App 或清除数据后，数据会丢失（需提前备份）

### 3.2 表结构

```sql
-- 商品表 goods
CREATE TABLE goods (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,  -- 自增主键
    barcode         VARCHAR(50) NOT NULL,                -- 商品条码 (EAN-13/EAN-8/CODE-128)
    goods_name      VARCHAR(200) NOT NULL,               -- 商品名称
    brand           VARCHAR(100),                        -- 品牌
    spec            VARCHAR(100),                        -- 规格/净含量
    goods_img       VARCHAR(500),                        -- 商品图片 URL 或本地路径
    purchase_price  DECIMAL(10,2),                       -- 进货价 (仅店主可见)
    sell_price      DECIMAL(10,2) NOT NULL,              -- 本店售价 (核心字段)
    remark          VARCHAR(200),                        -- 备注
    create_time     DATETIME NOT NULL,                   -- 创建时间 (ISO8601格式)
    update_time     DATETIME NOT NULL                    -- 更新时间 (ISO8601格式)
);

-- 条码索引 (加速扫码查价)
CREATE INDEX idx_barcode ON goods(barcode);
```

### 3.3 数据模型 (Goods)

```dart
class Goods {
  final int? id;                    // 数据库自增ID
  final String barcode;             // 条码 (唯一业务标识)
  final String goodsName;           // 商品名称
  final String? brand;              // 品牌 (可为空)
  final String? spec;               // 规格 (可为空)
  final String? goodsImg;           // 图片 (网络URL或本地路径)
  final double? purchasePrice;      // 进货价 (可为空)
  final double sellPrice;           // 售价 (必填)
  final String? remark;             // 备注 (可为空)
  final DateTime createTime;        // 创建时间
  final DateTime updateTime;        // 更新时间
}
```

### 3.4 核心数据库操作

| 方法 | 功能 | SQL 对应 |
|------|------|----------|
| `insertGoods()` | 插入新商品 | `INSERT INTO goods ...` |
| `updateGoods()` | 更新商品 | `UPDATE goods SET ... WHERE id = ?` |
| `deleteGoods()` | 删除商品 | `DELETE FROM goods WHERE id = ?` |
| `getGoodsByBarcode()` | 扫码查价 | `SELECT * FROM goods WHERE barcode = ?` |
| `getAllGoods()` | 商品列表+搜索 | `SELECT * FROM goods WHERE ... ORDER BY update_time DESC` |
| `barcodeExists()` | 检查条码是否已录入 | `SELECT COUNT(*) FROM goods WHERE barcode = ?` |

---

## 四、核心业务流程

### 4.1 录入新商品流程

```
用户点击「录入新商品」
    │
    ▼
打开摄像头扫码 (mobile_scanner)
    │
    ▼
获取条码 → 调用 BarcodeService.queryBarcode()
    │         ├── 请求 https://api.baichuanhui.com/barcode/{barcode}
    │         └── 失败则请求 https://api.bitfu.cn/barcode/{barcode}
    │
    ▼
API 返回商品信息 (名称/品牌/规格/图片)
    │
    ├── 查询成功 ──→ 自动填充表单
    │
    └── 查询失败 ──→ 提示「手动录入模式」
    │
    ▼
用户补充/修改信息 (名称、售价必填)
    │
    ▼
点击保存 → DBHelper.insertGoods() → 存入 SQLite
    │
    ▼
弹出「保存成功」，返回首页
```

### 4.2 扫码查价流程

```
用户点击「快速扫码查价」
    │
    ▼
打开摄像头扫码
    │
    ▼
获取条码 → DBHelper.getGoodsByBarcode(barcode)
    │
    ├── 商品存在 ──→ 显示商品信息 + 超大字体售价
    │
    └── 商品不存在 ──→ 显示「未录入」+ 提供「前往录入」按钮
```

---

## 五、数据共享问题分析

### 5.1 当前现状

| 场景 | 是否可行 | 原因 |
|------|----------|------|
| 店主手机录入商品 | ✅ | 数据存在店主手机 SQLite 中 |
| 店员手机查价 | ❌ | 店员手机没有数据，SQLite 是独立的 |
| 换手机恢复数据 | ❌ | 数据库在旧手机本地，新手机为空 |
| 多设备同步 | ❌ | 无网络同步机制 |

### 5.2 为什么数据无法共享？

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│  店主手机 A   │         │  店员手机 B   │         │  店员手机 C   │
│              │         │              │         │              │
│ SQLite DB    │   ❌    │ SQLite DB    │   ❌    │ SQLite DB    │
│ (100条商品)   │  无连接  │ (0条商品)     │  无连接  │ (0条商品)     │
│              │         │              │         │              │
└──────────────┘         └──────────────┘         └──────────────┘
```

每个手机都是一个独立的 SQLite 数据库实例，没有云端服务器做数据中转，所以数据天然隔离。

---

## 六、数据共享方案：导出/导入功能

### 6.1 方案概述

为每个手机增加 **数据导出** 和 **数据导入** 功能，通过文件传输实现数据共享。

```
┌─────────────────────────────────────────────────────────────┐
│                      数据共享流程                            │
│                                                             │
│   店主手机 (主数据源)                                        │
│   ┌─────────────────┐                                      │
│   │  SQLite DB      │                                      │
│   │  (全部商品数据)  │                                      │
│   └────────┬────────┘                                      │
│            │ 导出                                            │
│            ▼                                                │
│   ┌─────────────────┐                                      │
│   │  goods_export   │   ──微信/QQ/邮件发送──→ 店员手机       │
│   │  .json / .csv   │                                      │
│   └─────────────────┘                                      │
│                              │                              │
│                              ▼ 导入                          │
│   ┌─────────────────────────────────────────┐              │
│   │  店员手机                                │              │
│   │  ┌─────────────┐  ┌─────────────────┐  │              │
│   │  │ SQLite DB   │◄─┤ 解析导入文件     │  │              │
│   │  │ +新数据      │  │ 合并到本地数据库  │  │              │
│   │  └─────────────┘  └─────────────────┘  │              │
│   └─────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 导出功能设计

**入口位置**：首页增加「数据管理」按钮，或商品列表页右上角菜单

**导出格式选择**：

| 格式 | 优点 | 缺点 | 推荐场景 |
|------|------|------|----------|
| **JSON** | 结构完整，含图片URL | 文件稍大，普通用户不直观 | ⭐ 推荐（程序友好） |
| **CSV** | Excel 可打开，用户直观 | 不支持嵌套，图片URL可能乱码 | 适合给财务看 |

**JSON 导出示例**：
```json
{
  "export_time": "2024-01-15T10:30:00Z",
  "app_version": "1.0.0",
  "total_count": 150,
  "goods": [
    {
      "barcode": "6901234567890",
      "goods_name": "可口可乐 330ml",
      "brand": "可口可乐",
      "spec": "330ml",
      "goods_img": "https://...",
      "purchase_price": 2.50,
      "sell_price": 3.50,
      "remark": "常温区",
      "create_time": "2024-01-10T08:00:00Z",
      "update_time": "2024-01-12T14:30:00Z"
    }
  ]
}
```

**导出后操作**：
1. 文件保存到 `/Download/store_goods_20240115.json`
2. 调用 `share_plus` 弹出分享面板（微信/QQ/邮件/蓝牙）
3. 店员接收文件后，使用「导入」功能合并数据

### 6.3 导入功能设计

**导入策略**（关键设计点）：

```
导入文件解析后，对每条商品数据：
    │
    ├── 条码已存在 ──→ 选择策略：
    │                   ├── 跳过 (保留本地)
    │                   ├── 覆盖 (用导入数据替换)
    │                   └── 智能合并 (保留较新的 update_time)
    │
    └── 条码不存在 ──→ 直接插入新记录
```

**导入冲突处理弹窗**：

```
┌─────────────────────────────────────┐
│ 导入数据冲突处理                      │
├─────────────────────────────────────┤
│ 发现 12 条重复条码的商品              │
│                                     │
│ ○ 跳过重复，只导入新商品              │
│ ● 用导入数据覆盖本地数据              │
│ ○ 智能合并（保留最新修改）            │
│                                     │
│         [  确认导入  ]               │
└─────────────────────────────────────┘
```

### 6.4 技术实现要点

**导出实现**：
```dart
// 1. 查询全部商品
final goodsList = await _db.getAllGoods();

// 2. 转为 JSON
final exportData = {
  'export_time': DateTime.now().toIso8601String(),
  'total_count': goodsList.length,
  'goods': goodsList.map((g) => g.toMap()).toList(),
};

// 3. 写入文件
final jsonStr = jsonEncode(exportData);
final file = File('/path/to/export.json');
await file.writeAsString(jsonStr);

// 4. 调用分享
await Share.shareXFiles([XFile(file.path)], text: '商品数据备份');
```

**导入实现**：
```dart
// 1. 选择文件 (使用 file_picker 包)
final result = await FilePicker.platform.pickFiles();

// 2. 读取并解析 JSON
final file = File(result.paths.first);
final jsonData = jsonDecode(await file.readAsString());

// 3. 逐条处理
for (final item in jsonData['goods']) {
  final barcode = item['barcode'];
  final exists = await _db.barcodeExists(barcode);

  if (exists) {
    // 根据用户选择的策略处理冲突
    await _handleConflict(item, strategy);
  } else {
    // 直接插入
    await _db.insertGoods(Goods.fromMap(item));
  }
}
```

### 6.5 需要新增/修改的文件

| 操作 | 文件 | 说明 |
|------|------|------|
| 新增 | `lib/services/export_service.dart` | 导出逻辑 |
| 新增 | `lib/services/import_service.dart` | 导入逻辑 |
| 新增 | `lib/pages/data_manage_page.dart` | 数据管理页面（导出/导入入口） |
| 修改 | `pubspec.yaml` | 添加 `file_picker: ^6.1.1` 依赖 |
| 修改 | `lib/pages/home_page.dart` | 首页增加「数据管理」入口 |

### 6.6 进阶：自动同步方案（可选未来扩展）

如果以后想更进一步，可以考虑：

| 方案 | 实现难度 | 成本 | 说明 |
|------|----------|------|------|
| **WiFi 局域网同步** | 中 | 免费 | 同一WiFi下，店主手机作为服务端，店员扫码连接同步 |
| **自建后端服务器** | 高 | 需服务器 | 数据存云端，实时同步，需开发后端API |
| **使用 Firebase** | 低 | 免费额度 | Google 提供，但需翻墙 |
| **使用 LeanCloud** | 低 | 免费额度 | 国内BaaS服务，适合小项目 |

---

## 七、项目目录结构

```
store_price_app/
├── android/                    # Android 原生配置
│   ├── app/build.gradle        # compileSdk=35, 应用配置
│   └── ...
├── lib/                        # Dart 源码
│   ├── main.dart               # 应用入口
│   ├── database/
│   │   └── db_helper.dart      # SQLite 数据库操作
│   ├── models/
│   │   └── goods.dart          # 商品数据模型
│   ├── pages/
│   │   ├── home_page.dart      # 首页
│   │   ├── scan_page.dart      # 扫码页面 (mobile_scanner)
│   │   ├── scan_price_page.dart # 扫码查价结果页
│   │   ├── add_goods_page.dart # 录入/编辑商品页
│   │   └── goods_list_page.dart # 商品列表管理页
│   ├── services/
│   │   └── barcode_service.dart # 条码网络查询服务
│   └── utils/
│       └── app_colors.dart     # 应用主题色
├── assets/                     # 静态资源
├── pubspec.yaml                # 依赖配置
└── TECH_DOC.md                 # 本技术文档
```

---

## 八、总结

| 问题 | 答案 |
|------|------|
| 数据存在哪里？ | **手机本地 SQLite 数据库**，路径 `/data/data/.../databases/store_price.db` |
| 换手机数据还在吗？ | **不在**，需要提前导出备份 |
| 多店员能共用数据吗？ | **不能直接共用**，需要通过导出/导入文件共享 |
| 数据会上传云端吗？ | **不会**，完全离线，隐私安全 |
| 推荐的数据共享方式？ | **导出 JSON 文件 → 微信发送 → 导入合并** |
